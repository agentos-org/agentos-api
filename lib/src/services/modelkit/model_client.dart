import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:agentos_kernel/agentos_kernel.dart';
import 'package:unique_id_dart/unique_id_dart.dart';

import '../../config.dart';
import '../../locator.dart';
import '../../middleware.dart';
import 'sse_normalizer.dart';

/// Response returned by [ModelClient.send].
class ModelClientResponse {
  ModelClientResponse({
    required this.statusCode,
    required this.headers,
    this.bodyBytes,
    this.bodyStream,
  });

  final int statusCode;
  final Map<String, String> headers;
  final List<int>? bodyBytes;
  final Stream<List<int>>? bodyStream;
}

/// Task-oriented model categorization.
///
/// Replaces the legacy IO-shape oriented `LLMServiceType` (text / vision /
/// embedding / tts / asr). Vision-language models live behind
/// [ModelTask.chat] and are identified by `capabilities.vision = true`
/// rather than a separate task.
enum ModelTask {
  /// Chat / completions (text + vision).
  chat,

  /// Text and multimodal embeddings.
  embedding,

  /// Automatic speech recognition (speech-to-text).
  asr,

  /// Text-to-speech.
  tts,
}

/// Convenience helpers on [ModelTask].
extension ModelTaskX on ModelTask {
  /// Canonical service identifier used with `AgentOSServiceLocator`.
  String get serviceKey {
    switch (this) {
      case ModelTask.chat:
        return ApiConfig.serviceLlmChat;
      case ModelTask.embedding:
        return ApiConfig.serviceLlmEmbedding;
      case ModelTask.asr:
        return ApiConfig.serviceLlmAsr;
      case ModelTask.tts:
        return ApiConfig.serviceLlmTts;
    }
  }

  /// Wire identifier used in routing tables and request bodies.
  String get wireName {
    switch (this) {
      case ModelTask.chat:
        return 'chat';
      case ModelTask.embedding:
        return 'embedding';
      case ModelTask.asr:
        return 'asr';
      case ModelTask.tts:
        return 'tts';
    }
  }

  /// Default upstream endpoint when the caller hits the task root.
  String get defaultEndpoint {
    switch (this) {
      case ModelTask.chat:
        return '/chat/completions';
      case ModelTask.embedding:
        return '/embeddings';
      case ModelTask.asr:
        return '/audio/transcriptions';
      case ModelTask.tts:
        return '/audio/speech';
    }
  }

  /// English display name.
  String get displayName {
    switch (this) {
      case ModelTask.chat:
        return 'Chat';
      case ModelTask.embedding:
        return 'Embedding';
      case ModelTask.asr:
        return 'Speech-to-Text';
      case ModelTask.tts:
        return 'Text-to-Speech';
    }
  }
}

/// Service identifiers historically used by [LLMServiceType] callers that the
/// model resolver may emit through `LlmModelInfo.type`.
const Set<String> _legacyChatServiceKeys = {
  // ignore: deprecated_member_use_from_same_package
  ApiConfig.serviceLlmText,
  // ignore: deprecated_member_use_from_same_package
  ApiConfig.serviceLlmVision,
};

/// Task-oriented model proxy client.
///
/// This is the new entry point for ModelKit and replaces the legacy
/// `LLMClient` (which now delegates here). It speaks [ModelTask] instead of
/// `LLMServiceType`, routes chat (text + vision) through a single endpoint,
/// and identifies VLM by `capabilities.vision` on the resolved model rather
/// than by a dedicated path.
class ModelClient {
  static const int _errorBodyPreviewLimit = 512;

  ModelClient({
    HttpClient? httpClient,
    AgentOSServiceLocator? serviceLocator,
    required Future<KernelService?> kernelFuture,
  }) : _httpClient = httpClient ?? HttpClient(),
       _serviceLocator = serviceLocator ?? DefaultServiceLocator(),
       _kernelFuture = kernelFuture;

  final HttpClient _httpClient;
  final AgentOSServiceLocator _serviceLocator;
  final Future<KernelService?> _kernelFuture;

  /// Service locator currently in use.
  AgentOSServiceLocator get serviceLocator => _serviceLocator;

  /// Forwards a request to the upstream service responsible for [task].
  Future<ModelClientResponse> send({
    required ModelTask task,
    required String method,
    required String path,
    Map<String, String>? headers,
    Map<String, String>? queryParameters,
    List<int>? body,
    bool streamResponse = false,
  }) async {
    final requestId = uniqueId();
    final stopwatch = Stopwatch()..start();
    final requestStartTime = DateTime.now();

    var modelIdentifier = _extractModelName(body);
    var baseUrl = _extractBaseUrl(body);

    final kernel = await _kernelFuture;
    LlmMetrics? metrics;

    // When no model is specified for chat, fall back to kernel's default LLM
    // configuration if one is available.
    if (kernel != null &&
        task == ModelTask.chat &&
        (modelIdentifier == null || modelIdentifier.isEmpty)) {
      final availableConfig = kernel.getAvailableLlmConfig();
      if (availableConfig != null) {
        modelIdentifier = availableConfig.model;
        baseUrl ??= availableConfig.baseUrl;
      }
    }

    final resolvedModel = modelIdentifier != null && modelIdentifier.isNotEmpty
        ? await _resolveModel(modelIdentifier)
        : null;

    final modelName = resolvedModel?.name ?? modelIdentifier;
    var requestBody = _rewriteRequestBodyModel(
      body,
      resolvedModel: resolvedModel,
      upstreamModel: modelName,
    );
    requestBody = _injectReasoningContentPlaceholder(
      requestBody,
      task: task,
      modelName: modelName,
    );

    if (kernel != null && modelName != null) {
      metrics = kernel.createLlmMetrics(
        requestId: requestId,
        baseUrl: resolvedModel?.baseUrl ?? baseUrl ?? 'unknown',
        model: modelName,
        apiKey: null,
        jobId: null,
        userId: null,
      );
      metrics.start();
    }

    final Uri uri;
    final bool isRemoteRoute;
    String? remoteApiKey;

    if (resolvedModel != null && resolvedModel.isRemote) {
      isRemoteRoute = true;
      uri = _buildUri(
        Uri.parse(resolvedModel.baseUrl!),
        path,
        queryParameters,
        task: task,
      );
      remoteApiKey = resolvedModel.apiKey;
      if ((remoteApiKey == null || remoteApiKey.isEmpty) && kernel != null) {
        final availableConfig = kernel.getAvailableLlmConfig();
        if (availableConfig != null) {
          remoteApiKey = availableConfig.apiKey;
        }
      }
    } else {
      isRemoteRoute = false;
      final port = await _lookupServicePort(
        task,
        resolvedModel?.id ?? modelIdentifier,
      );
      if (port == null) {
        stopwatch.stop();
        final errorMsg = modelIdentifier != null && modelIdentifier.isNotEmpty
            ? 'Model "$modelIdentifier" unavailable'
            : '${task.displayName} service unavailable';
        metrics?.failed(errorMsg);
        return ModelClientResponse(
          statusCode: 503,
          headers: const {'content-type': 'application/json'},
          bodyBytes: utf8.encode(
            jsonEncode({'error': errorMsg, 'service': task.serviceKey}),
          ),
        );
      }
      final baseUri = Uri.parse(ApiConfig.getInternalUrl(port));
      uri = _buildUri(baseUri, path, queryParameters, task: task);
    }

    try {
      final request = await _httpClient.openUrl(method, uri);
      // Do not reuse pooled keep-alive connections for proxied (especially
      // streaming) upstream calls. A streaming response that is torn down early
      // (client disconnect, upstream error mid-stream) can be returned to the
      // pool with a lingering subscription on its underlying socket. The next
      // request reusing that connection then fails on its first
      // `response.listen`/`fold` with "Bad state: Stream has already been
      // listened to". Forcing a fresh connection per request eliminates that
      // class of corruption.
      request.persistentConnection = false;
      _applyRequestHeaders(request, headers, stripAuth: isRemoteRoute);
      if (isRemoteRoute && remoteApiKey != null && remoteApiKey.isNotEmpty) {
        request.headers.set(
          'Authorization',
          'Bearer $remoteApiKey',
          preserveHeaderCase: true,
        );
      }
      if (requestBody != null && requestBody.isNotEmpty) {
        request.add(requestBody);
      }
      final response = await request.close();
      final responseHeaders = _sanitizeResponseHeaders(response.headers);

      if (response.statusCode >= 400 && streamResponse) {
        requestLogger.warning(
          'Model proxy upstream error: '
          'task=${task.wireName} '
          'model=${modelName ?? '-'} '
          'method=$method '
          'uri=$uri '
          'status=${response.statusCode} '
          'stream=true',
        );

        final errorBytes = await response.fold<List<int>>(<int>[], (buf, data) {
          buf.addAll(data);
          return buf;
        });
        final normalized = _normalizeContextSizeError(
          errorBytes,
          response.statusCode,
        );
        if (normalized != null) {
          stopwatch.stop();
          metrics?.failed('context_length_exceeded');
          return ModelClientResponse(
            statusCode: normalized.statusCode,
            headers: const {'content-type': 'application/json'},
            bodyBytes: normalized.bodyBytes,
          );
        }

        return ModelClientResponse(
          statusCode: response.statusCode,
          headers: responseHeaders,
          bodyBytes: errorBytes,
        );
      }

      if (streamResponse) {
        // Re-frame quirky upstream chat SSE into canonical OpenAI before it
        // reaches the client, so third-party apps only need vanilla OpenAI
        // compatibility (see [_normalizeChatSseStream]).
        final Stream<List<int>> upstream = task == ModelTask.chat
            ? normalizeChatSseStream(response)
            : response;
        final monitoredStream = _createMonitoredStream(
          metrics: metrics,
          stream: upstream,
          startStopwatch: stopwatch,
          requestStartTime: requestStartTime,
        );

        return ModelClientResponse(
          statusCode: response.statusCode,
          headers: responseHeaders,
          bodyStream: monitoredStream,
        );
      }

      final bytes = await response.fold<List<int>>(<int>[], (buffer, data) {
        buffer.addAll(data);
        return buffer;
      });

      if (response.statusCode >= 400) {
        requestLogger.warning(
          'Model proxy upstream error: '
          'task=${task.wireName} '
          'model=${modelName ?? '-'} '
          'method=$method '
          'uri=$uri '
          'status=${response.statusCode} '
          'bodyPreview="${_truncateForLog(_decodeResponseBody(bytes))}"',
        );

        final normalized = _normalizeContextSizeError(
          bytes,
          response.statusCode,
        );
        if (normalized != null) {
          stopwatch.stop();
          metrics?.failed('context_length_exceeded');
          return ModelClientResponse(
            statusCode: normalized.statusCode,
            headers: const {'content-type': 'application/json'},
            bodyBytes: normalized.bodyBytes,
          );
        }
      }

      stopwatch.stop();
      final totalTokens = _extractTokenCountFromResponse(bytes);
      metrics?.completed(totalTokens ?? 0);

      // Normalize a non-streaming chat completion body to OpenAI-canonical
      // shape (reasoning field name, tool-call deltas) for the same reason
      // the streaming path is normalized.
      final responseBytes = task == ModelTask.chat && response.statusCode < 400
          ? normalizeChatJsonBody(bytes)
          : bytes;

      return ModelClientResponse(
        statusCode: response.statusCode,
        headers: responseHeaders,
        bodyBytes: responseBytes,
      );
    } catch (e, stackTrace) {
      stopwatch.stop();
      metrics?.failed(e.toString());
      requestLogger.severe(
        'Model proxy request failed: '
        'task=${task.wireName} '
        'model=${modelName ?? '-'} '
        'method=$method '
        'uri=$uri '
        'error=$e',
        e,
        stackTrace,
      );

      return ModelClientResponse(
        statusCode: 502,
        headers: const {'content-type': 'application/json'},
        bodyBytes: utf8.encode(
          jsonEncode({
            'error': 'Backend service unavailable',
            'service': task.serviceKey,
            'message': e.toString(),
          }),
        ),
      );
    }
  }

  /// Resolves a port for [task] from the service locator, transparently
  /// falling back to the deprecated `llm_text` / `llm_vision` keys so external
  /// `AgentOSServiceLocator` implementations that haven't migrated yet still
  /// work.
  Future<int?> _lookupServicePort(ModelTask task, String? modelId) async {
    // Prefer the canonical task service key.
    final primary = await _serviceLocator.getServicePort(
      task.serviceKey,
      modelId: modelId,
    );
    if (primary != null) return primary;

    // Chat task: also try the legacy text/vision keys so unmigrated locators
    // keep working.
    if (task == ModelTask.chat) {
      for (final legacy in _legacyChatServiceKeys) {
        final port = await _serviceLocator.getServicePort(
          legacy,
          modelId: modelId,
        );
        if (port != null) return port;
      }
    }
    return null;
  }

  /// Wraps the upstream stream with token-counting instrumentation.
  Stream<List<int>> _createMonitoredStream({
    required LlmMetrics? metrics,
    required Stream<List<int>> stream,
    required Stopwatch startStopwatch,
    required DateTime requestStartTime,
  }) {
    bool firstTokenReceived = false;
    int totalTokenCount = 0;
    DateTime? lastReportTime;
    int tokensSinceLastReport = 0;
    final buffer = StringBuffer();
    const reportIntervalMs = 1000;
    const minTokensForReport = 10;

    return stream.transform(
      StreamTransformer<List<int>, List<int>>.fromHandlers(
        handleData: (data, sink) {
          final parseResult = _parseSSETokens(data, buffer);
          var tokens = parseResult.incrementalTokens;
          final absoluteCompletionTokens = parseResult.absoluteCompletionTokens;
          if (absoluteCompletionTokens != null) {
            if (absoluteCompletionTokens > totalTokenCount) {
              tokens += absoluteCompletionTokens - totalTokenCount;
              totalTokenCount = absoluteCompletionTokens;
            }
          } else {
            totalTokenCount += tokens;
          }
          tokensSinceLastReport += tokens;

          final now = DateTime.now();
          if (!firstTokenReceived && (tokens > 0 || parseResult.hasContent)) {
            firstTokenReceived = true;
            metrics?.setFirstToken(now);
            lastReportTime = now;
          }
          if (lastReportTime != null &&
              tokensSinceLastReport >= minTokensForReport) {
            final elapsed = now.difference(lastReportTime!);
            if (elapsed.inMilliseconds >= reportIntervalMs) {
              final tps =
                  tokensSinceLastReport / max(1, elapsed.inMilliseconds) * 1000;
              metrics?.setTokenPerSecond(tps);
              lastReportTime = now;
              tokensSinceLastReport = 0;
            }
          }
          sink.add(data);
        },
        handleError: (error, stackTrace, sink) {
          metrics?.failed(error.toString());
          sink.addError(error, stackTrace);
        },
        handleDone: (sink) {
          startStopwatch.stop();
          metrics?.completed(totalTokenCount);
          sink.close();
        },
      ),
    );
  }

  _SSEParseResult _parseSSETokens(List<int> data, StringBuffer buffer) {
    int incrementalTokens = 0;
    int? absoluteCompletionTokens;
    bool hasContent = false;

    try {
      final text = utf8.decode(data, allowMalformed: true);
      buffer.write(text);

      final content = buffer.toString();
      final events = content.split('\n\n');
      buffer.clear();
      if (!content.endsWith('\n\n') && events.isNotEmpty) {
        buffer.write(events.removeLast());
      }

      for (final event in events) {
        if (event.trim().isEmpty) continue;
        final lines = event.split('\n');
        for (final line in lines) {
          if (line.startsWith('data:')) {
            final jsonStr = line.substring(5).trim();
            if (jsonStr == '[DONE]') continue;
            try {
              final json = jsonDecode(jsonStr) as Map<String, dynamic>;
              final usage = json['usage'] as Map<String, dynamic>?;
              if (usage != null) {
                final completionTokens = usage['completion_tokens'];
                if (completionTokens is int && completionTokens > 0) {
                  final previous = absoluteCompletionTokens ?? 0;
                  if (completionTokens > previous) {
                    absoluteCompletionTokens = completionTokens;
                  }
                  hasContent = true;
                  continue;
                }
              }
              final choices = json['choices'] as List<dynamic>?;
              if (choices != null && choices.isNotEmpty) {
                for (final choice in choices) {
                  if (choice is Map<String, dynamic>) {
                    final delta = choice['delta'] as Map<String, dynamic>?;
                    if (delta != null && delta.containsKey('content')) {
                      final content = delta['content'];
                      if (content != null && content.toString().isNotEmpty) {
                        incrementalTokens++;
                        hasContent = true;
                      }
                    }
                  }
                }
              }
            } catch (_) {
              // ignore parse error
            }
          }
        }
      }
    } catch (_) {
      if (data.isNotEmpty) {
        incrementalTokens = 1;
        hasContent = true;
      }
    }

    return _SSEParseResult(
      incrementalTokens: incrementalTokens,
      absoluteCompletionTokens: absoluteCompletionTokens,
      hasContent: hasContent,
    );
  }

  Future<LlmModelInfo?> _resolveModel(String identifier) async {
    final models = await _serviceLocator.getLlmModelList();
    // Build the ordered set of candidate identifiers a client may send. The
    // chat model list exposes ids shaped like `alias (name)` (see
    // `ModelKitController._menuModelLabel`), so we accept the raw identifier as
    // well as the alias / name parsed out of that label.
    final candidates = _modelIdentifierCandidates(identifier);

    for (final candidate in candidates) {
      for (final m in models) {
        if (m.id == candidate) return m;
      }
    }
    for (final candidate in candidates) {
      for (final m in models) {
        if (m.name == candidate) return m;
      }
    }
    for (final candidate in candidates) {
      for (final m in models) {
        if (m.alias.isNotEmpty && m.alias == candidate) return m;
      }
    }
    return null;
  }

  /// Expands a client-supplied model identifier into the candidates that may
  /// match an [LlmModelInfo].
  ///
  /// Handles the menu label format `alias (name)` by also yielding the trimmed
  /// alias (text before the final parenthesis group) and the inner name.
  static List<String> _modelIdentifierCandidates(String identifier) {
    final trimmed = identifier.trim();
    if (trimmed.isEmpty) return const [];

    final candidates = <String>[trimmed];

    if (trimmed.endsWith(')')) {
      final open = trimmed.lastIndexOf('(');
      if (open > 0) {
        final inner = trimmed.substring(open + 1, trimmed.length - 1).trim();
        final outer = trimmed.substring(0, open).trim();
        if (inner.isNotEmpty) candidates.add(inner);
        if (outer.isNotEmpty) candidates.add(outer);
      }
    }

    return candidates;
  }

  String? _extractModelName(List<int>? body) {
    if (body == null || body.isEmpty) return null;
    try {
      final bodyString = utf8.decode(body);
      final json = jsonDecode(bodyString) as Map<String, dynamic>;
      return json['model'] as String?;
    } catch (_) {
      return null;
    }
  }

  String? _extractBaseUrl(List<int>? body) {
    if (body == null || body.isEmpty) return null;
    try {
      final bodyString = utf8.decode(body);
      final json = jsonDecode(bodyString) as Map<String, dynamic>;
      return json['base_url'] as String?;
    } catch (_) {
      return null;
    }
  }

  int? _extractTokenCountFromResponse(List<int> bytes) {
    try {
      final text = utf8.decode(bytes);
      final json = jsonDecode(text) as Map<String, dynamic>;
      final usage = json['usage'] as Map<String, dynamic>?;
      if (usage != null) {
        final totalTokens = usage['total_tokens'];
        if (totalTokens is int) return totalTokens;
        final completionTokens = usage['completion_tokens'];
        if (completionTokens is int) return completionTokens;
      }
    } catch (_) {
      // ignore
    }
    return null;
  }

  Uri _buildUri(
    Uri baseUri,
    String path,
    Map<String, String>? queryParameters, {
    required ModelTask task,
  }) {
    final joinedPath = _resolveUpstreamPath(baseUri.path, path, task);
    return baseUri.replace(
      path: joinedPath,
      queryParameters: (queryParameters == null || queryParameters.isEmpty)
          ? null
          : queryParameters,
    );
  }

  void _applyRequestHeaders(
    HttpClientRequest request,
    Map<String, String>? headers, {
    bool stripAuth = false,
  }) {
    if (headers == null) return;
    headers.forEach((name, value) {
      final lowerName = name.toLowerCase();
      if (_isHopByHopHeader(lowerName) ||
          lowerName == 'host' ||
          lowerName == 'content-length' ||
          (stripAuth && lowerName == 'authorization')) {
        return;
      }
      request.headers.set(name, value, preserveHeaderCase: true);
    });
  }

  Map<String, String> _sanitizeResponseHeaders(HttpHeaders headers) {
    final result = <String, String>{};
    headers.forEach((name, values) {
      final lowerName = name.toLowerCase();
      if (_isHopByHopHeader(lowerName) ||
          lowerName == 'content-length' ||
          lowerName == 'content-encoding') {
        return;
      }
      result[name] = values.join(',');
    });
    return result;
  }

  bool _isHopByHopHeader(String name) {
    switch (name) {
      case 'connection':
      case 'keep-alive':
      case 'proxy-authenticate':
      case 'proxy-authorization':
      case 'te':
      case 'trailers':
      case 'transfer-encoding':
      case 'upgrade':
        return true;
    }
    return false;
  }

  String _resolveUpstreamPath(
    String basePath,
    String requestPath,
    ModelTask task,
  ) {
    final normalizedBase = _normalizeBasePath(basePath);
    final normalizedRequest = _normalizeRequestPath(requestPath);
    final defaultEndpoint = task.defaultEndpoint;

    if (_isCompleteEndpointPath(normalizedBase, defaultEndpoint)) {
      return normalizedBase;
    }

    if (_extractTrailingVersionSegment(normalizedBase) != null) {
      final requestSuffix = _stripLeadingVersionSegment(normalizedRequest);
      if (_isEmptyRequestPath(normalizedRequest) ||
          requestSuffix != normalizedRequest) {
        final normalizedSuffix = _normalizeEndpointSuffix(
          requestSuffix,
          defaultEndpoint,
        );
        if (normalizedSuffix != null) {
          return '$normalizedBase$normalizedSuffix';
        }
      }
    } else if (normalizedBase.isEmpty) {
      final normalizedSuffix = _normalizeEndpointSuffix(
        normalizedRequest,
        defaultEndpoint,
      );
      final requestVersion = _extractLeadingVersionSegment(normalizedRequest);
      if (normalizedSuffix != null) {
        final versionPrefix = requestVersion ?? '/v1';
        return '$versionPrefix$normalizedSuffix';
      }
    } else if (normalizedBase.isNotEmpty) {
      final requestVersion = _extractLeadingVersionSegment(normalizedRequest);
      final requestSuffix = requestVersion != null
          ? _stripLeadingVersionSegment(normalizedRequest)
          : normalizedRequest;
      final normalizedSuffix = _normalizeEndpointSuffix(
        requestSuffix,
        defaultEndpoint,
      );
      if (normalizedSuffix != null) {
        final versionPrefix = requestVersion ?? '/v1';
        return '$normalizedBase$versionPrefix$normalizedSuffix';
      }
    }

    return _joinPaths(normalizedBase, normalizedRequest);
  }

  String _joinPaths(String basePath, String path) {
    if (basePath.endsWith('/')) {
      return '${basePath.substring(0, basePath.length - 1)}$path';
    }
    return '$basePath$path';
  }

  String _normalizeBasePath(String path) {
    if (path.isEmpty || path == '/') return '';
    return path.endsWith('/') ? path.substring(0, path.length - 1) : path;
  }

  String _normalizeRequestPath(String path) {
    if (path.isEmpty || path == '/') return '/';
    return path.startsWith('/') ? path : '/$path';
  }

  bool _isEmptyRequestPath(String path) => path == '/';

  bool _isCompleteEndpointPath(String basePath, String endpoint) {
    return basePath == endpoint || basePath.endsWith(endpoint);
  }

  String? _extractTrailingVersionSegment(String path) {
    if (path.isEmpty) return null;
    final segments = Uri(path: path).pathSegments;
    if (segments.isEmpty) return null;
    final lastSegment = segments.last;
    return _isVersionSegment(lastSegment) ? '/$lastSegment' : null;
  }

  String? _extractLeadingVersionSegment(String path) {
    final segments = Uri(path: path).pathSegments;
    if (segments.isEmpty) return null;
    final firstSegment = segments.first;
    return _isVersionSegment(firstSegment) ? '/$firstSegment' : null;
  }

  String _stripLeadingVersionSegment(String path) {
    final segments = Uri(path: path).pathSegments;
    if (segments.isEmpty || !_isVersionSegment(segments.first)) {
      return path;
    }
    if (segments.length == 1) return '/';
    return '/${segments.skip(1).join('/')}';
  }

  bool _isVersionSegment(String segment) {
    return RegExp(r'^v\d+$').hasMatch(segment);
  }

  String? _normalizeEndpointSuffix(String path, String? defaultEndpoint) {
    if (_isEmptyRequestPath(path)) return defaultEndpoint;
    final pathWithoutVersion = _stripLeadingVersionSegment(path);
    if (_isEmptyRequestPath(pathWithoutVersion)) return defaultEndpoint;
    return pathWithoutVersion;
  }

  List<int>? _rewriteRequestBodyModel(
    List<int>? body, {
    required LlmModelInfo? resolvedModel,
    required String? upstreamModel,
  }) {
    if (body == null ||
        body.isEmpty ||
        resolvedModel == null ||
        !resolvedModel.isRemote ||
        upstreamModel == null ||
        upstreamModel.isEmpty) {
      return body;
    }
    try {
      final decoded = jsonDecode(utf8.decode(body));
      if (decoded is! Map<String, dynamic>) return body;
      if (decoded['model'] == upstreamModel) return body;
      decoded['model'] = upstreamModel;
      return utf8.encode(jsonEncode(decoded));
    } catch (_) {
      return body;
    }
  }

  /// Compatibility shim for "thinking-mode" models that require
  /// `reasoning_content` to be replayed on assistant messages carrying
  /// `tool_calls`.
  ///
  /// Some providers (currently DeepSeek V4+, Xiaomi MiMo V2.5+) reject
  /// multi-turn requests with `400 The reasoning_content in the thinking
  /// mode must be passed back to the API.` whenever an assistant message
  /// containing `tool_calls` is missing the `reasoning_content` from the
  /// turn that produced those tool calls. Most OpenAI-compatible clients
  /// (e.g. `@ai-sdk/openai`) silently drop the field on the way in and
  /// never replay it. This gateway-level shim injects an empty
  /// `reasoning_content` so the upstream validator passes; the previous
  /// turn's chain-of-thought context is lost but multi-turn tool calling
  /// keeps working.
  ///
  /// Family matching is governed by [_reasoningContentFamilies] — version
  /// numbers compare numerically, so any future same-family release
  /// (e.g. `deepseek-v5`, `MiMo-V3`) inherits the rule automatically.
  /// Scoped to [ModelTask.chat].
  List<int>? _injectReasoningContentPlaceholder(
    List<int>? body, {
    required ModelTask task,
    required String? modelName,
  }) {
    if (body == null || body.isEmpty) return body;
    if (task != ModelTask.chat) return body;
    if (modelName == null || !_requiresReasoningContentReplay(modelName)) {
      return body;
    }
    try {
      final decoded = jsonDecode(utf8.decode(body));
      if (decoded is! Map<String, dynamic>) return body;
      final messages = decoded['messages'];
      if (messages is! List) return body;

      var mutated = false;
      for (final message in messages) {
        if (message is! Map) continue;
        if (message['role'] != 'assistant') continue;
        final toolCalls = message['tool_calls'];
        if (toolCalls is! List || toolCalls.isEmpty) continue;
        final existing = message['reasoning_content'];
        if (existing is String && existing.isNotEmpty) continue;
        message['reasoning_content'] = '';
        mutated = true;
      }

      if (!mutated) return body;
      return utf8.encode(jsonEncode(decoded));
    } catch (_) {
      return body;
    }
  }

  /// Model families that enforce the thinking-mode `reasoning_content`
  /// replay contract. To extend coverage, add another entry here.
  static final List<_ReasoningContentFamily> _reasoningContentFamilies = [
    // DeepSeek V4 and above: deepseek-v4, deepseek-v4-pro, deepseek-v4-flash,
    // and any future v5 / v6 / v4.x release.
    _ReasoningContentFamily(
      pattern: RegExp(r'deepseek-v(\d+)(?:\.(\d+))?', caseSensitive: false),
      minVersion: const [4],
    ),
    // Xiaomi MiMo V2.5 and above: MiMo-V2.5, MiMo-V2.6, MiMo-V3, MiMo-V4, ...
    _ReasoningContentFamily(
      pattern: RegExp(r'mimo-v(\d+)(?:\.(\d+))?', caseSensitive: false),
      minVersion: const [2, 5],
    ),
  ];

  static bool _requiresReasoningContentReplay(String modelName) {
    for (final family in _reasoningContentFamilies) {
      final match = family.pattern.firstMatch(modelName);
      if (match == null) continue;
      final major = int.tryParse(match.group(1) ?? '');
      if (major == null) continue;
      final minor = int.tryParse(match.group(2) ?? '0') ?? 0;
      if (_compareVersionParts([major, minor], family.minVersion) >= 0) {
        return true;
      }
    }
    return false;
  }

  /// Element-wise numeric comparison padding the shorter list with zeros
  /// (so `[3]` reads as `[3, 0]` and `[2, 5]` outranks `[2]`).
  static int _compareVersionParts(List<int> a, List<int> b) {
    final length = a.length > b.length ? a.length : b.length;
    for (var i = 0; i < length; i++) {
      final av = i < a.length ? a[i] : 0;
      final bv = i < b.length ? b[i] : 0;
      if (av != bv) return av.compareTo(bv);
    }
    return 0;
  }

  _NormalizedError? _normalizeContextSizeError(
    List<int> bytes,
    int statusCode,
  ) {
    if (bytes.isEmpty) return null;
    try {
      final body = jsonDecode(utf8.decode(bytes, allowMalformed: true));
      if (body is! Map<String, dynamic>) return null;

      final error = body['error'];
      String? message;
      int? nPromptTokens;
      int? nCtx;
      bool matched = false;

      if (error is Map<String, dynamic>) {
        final type = error['type'] as String?;
        final code = error['code'];
        final codeStr = code is String ? code : (code is int ? '$code' : null);
        message = error['message'] as String?;
        final status = error['status'] as String?;
        nPromptTokens = error['n_prompt_tokens'] as int?;
        nCtx = error['n_ctx'] as int?;

        if (type == 'exceed_context_size_error') {
          matched = true;
        } else if (codeStr == 'context_length_exceeded') {
          matched = true;
        } else if (status == 'INVALID_ARGUMENT' &&
            message != null &&
            _isContextSizeMessage(message)) {
          matched = true;
        } else if (type == 'invalid_request_error' &&
            message != null &&
            _isContextSizeMessage(message)) {
          matched = true;
        } else if (message != null && _isContextSizeMessage(message)) {
          matched = true;
        }
      } else if (error is String && _isContextSizeMessage(error)) {
        message = error;
        matched = true;
      }

      if (!matched) return null;

      if (nPromptTokens == null || nCtx == null) {
        final extracted = _extractTokenCounts(message, nPromptTokens, nCtx);
        nPromptTokens ??= extracted.requested;
        nCtx ??= extracted.limit;
      }

      final userMessage = (nPromptTokens != null && nCtx != null)
          ? "This model's maximum context length is $nCtx tokens. "
                "However, your messages resulted in $nPromptTokens tokens. "
                "Please reduce the length of the messages."
          : message ?? 'The request exceeds the available context size.';

      final normalized = {
        'error': {
          'message': userMessage,
          'type': 'context_length_exceeded',
          'code': 'context_length_exceeded',
          // ignore: use_null_aware_elements
          if (nPromptTokens != null) 'n_prompt_tokens': nPromptTokens,
          // ignore: use_null_aware_elements
          if (nCtx != null) 'n_ctx': nCtx,
        },
      };
      return _NormalizedError(
        statusCode: 400,
        bodyBytes: utf8.encode(jsonEncode(normalized)),
      );
    } catch (_) {
      return null;
    }
  }

  static final _contextSizePatterns = [
    RegExp(
      r'exceeds?\s+the\s+available\s+context\s+size',
      caseSensitive: false,
    ),
    RegExp(
      r'input\s+is\s+larger\s+than\s+the\s+max\s+context\s+size',
      caseSensitive: false,
    ),
    RegExp(r'context\s+size\s+has\s+been\s+exceeded', caseSensitive: false),
    RegExp(
      r"maximum\s+context\s+length\s+is\s+\d+\s+tokens",
      caseSensitive: false,
    ),
    RegExp(r'exceeds?\s+the\s+context\s+window', caseSensitive: false),
    RegExp(r'exceed\s+context\s+window', caseSensitive: false),
    RegExp(
      r'requested\s+tokens.*exceed\s+context\s+window',
      caseSensitive: false,
    ),
    RegExp(r'prompt\s+is\s+too\s+long', caseSensitive: false),
    RegExp(r'exceed\s+context\s+limit', caseSensitive: false),
    RegExp(
      r'input\s+token\s+count\s*\(\d+\)\s*exceeds\s+the\s+maximum\s+number\s+of\s+tokens\s+allowed',
      caseSensitive: false,
    ),
    RegExp(
      r'keep\s+the\s+first\s+\d+\s+tokens\s+when\s+context\s+the\s+overflows',
      caseSensitive: false,
    ),
    RegExp(
      r'tokens\s+to\s+keep\s+from\s+the\s+initial\s+prompt\s+is\s+greater\s+than\s+the\s+context\s+length',
      caseSensitive: false,
    ),
    RegExp(r'token.{0,20}limit.{0,20}exceed', caseSensitive: false),
  ];

  bool _isContextSizeMessage(String message) {
    return _contextSizePatterns.any((p) => p.hasMatch(message));
  }

  static final _tokenCountPatterns = [
    RegExp(
      r'maximum\s+context\s+length\s+is\s+(\d+)\s+tokens.*?(\d+)\s+tokens',
      caseSensitive: false,
    ),
    RegExp(
      r'request\s*\((\d+)\s*tokens?\).*?context\s+size\s*\((\d+)\s*tokens?\)',
      caseSensitive: false,
    ),
    RegExp(
      r'prompt\s+is\s+too\s+long:\s*(\d+)\s*tokens?\s*>\s*(\d+)',
      caseSensitive: false,
    ),
    RegExp(
      r'exceed\s+context\s+limit:\s*(\d+)\s*\+\s*\d+\s*>\s*(\d+)',
      caseSensitive: false,
    ),
    RegExp(
      r'input\s+token\s+count\s*\((\d+)\).*?tokens\s+allowed\s*\((\d+)\)',
      caseSensitive: false,
    ),
    RegExp(
      r'keep\s+the\s+first\s+(\d+)\s+tokens.*?context\s+length\s+of\s+(?:only\s+)?(\d+)\s+tokens',
      caseSensitive: false,
    ),
  ];

  _TokenCountResult _extractTokenCounts(
    String? message,
    int? existingRequested,
    int? existingLimit,
  ) {
    if (existingRequested != null && existingLimit != null) {
      return _TokenCountResult(
        requested: existingRequested,
        limit: existingLimit,
      );
    }
    if (message == null || message.isEmpty) {
      return _TokenCountResult(
        requested: existingRequested,
        limit: existingLimit,
      );
    }
    for (final pattern in _tokenCountPatterns) {
      final match = pattern.firstMatch(message);
      if (match != null && match.groupCount >= 2) {
        final g1 = int.tryParse(match.group(1) ?? '');
        final g2 = int.tryParse(match.group(2) ?? '');
        if (g1 != null && g2 != null) {
          if (pattern == _tokenCountPatterns[0]) {
            return _TokenCountResult(
              requested: existingRequested ?? g2,
              limit: existingLimit ?? g1,
            );
          }
          return _TokenCountResult(
            requested: existingRequested ?? g1,
            limit: existingLimit ?? g2,
          );
        }
      }
    }
    return _TokenCountResult(
      requested: existingRequested,
      limit: existingLimit,
    );
  }

  String _decodeResponseBody(List<int> bytes) {
    if (bytes.isEmpty) return '';
    return utf8.decode(bytes, allowMalformed: true);
  }

  String _truncateForLog(String value) {
    final normalized = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.length <= _errorBodyPreviewLimit) return normalized;
    return '${normalized.substring(0, _errorBodyPreviewLimit)}...';
  }
}

class _NormalizedError {
  final int statusCode;
  final List<int> bodyBytes;
  const _NormalizedError({required this.statusCode, required this.bodyBytes});
}

class _TokenCountResult {
  final int? requested;
  final int? limit;
  const _TokenCountResult({this.requested, this.limit});
}

class _SSEParseResult {
  final int incrementalTokens;
  final int? absoluteCompletionTokens;
  final bool hasContent;
  const _SSEParseResult({
    required this.incrementalTokens,
    this.absoluteCompletionTokens,
    required this.hasContent,
  });
}

/// Descriptor for a model family that requires `reasoning_content` to be
/// present on assistant messages with `tool_calls`.
///
/// [pattern] must capture the model's numeric version as groups 1 (major)
/// and optionally 2 (minor). [minVersion] is `[major, minor]` (or `[major]`
/// when only the major matters) and is compared numerically; the shim is
/// applied when the parsed version is `>= minVersion`.
class _ReasoningContentFamily {
  const _ReasoningContentFamily({
    required this.pattern,
    required this.minVersion,
  });

  final RegExp pattern;
  final List<int> minVersion;
}
