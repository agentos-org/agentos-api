import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:agentos_kernel/agentos_kernel.dart';
import 'package:unique_id_dart/unique_id_dart.dart';

import '../../locator.dart';
import '../../config.dart';
import '../../middleware.dart';

/// LLM client response
class LLMClientResponse {
  LLMClientResponse({
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

/// LLM service type
enum LLMServiceType { text, vision, embedding, tts, asr }

/// LLM service type extension
extension LLMServiceTypeExtension on LLMServiceType {
  /// Gets service identifier
  String get serviceKey {
    switch (this) {
      case LLMServiceType.text:
        return ApiConfig.serviceLlmText;
      case LLMServiceType.vision:
        return ApiConfig.serviceLlmVision;
      case LLMServiceType.embedding:
        return ApiConfig.serviceLlmEmbedding;
      case LLMServiceType.tts:
        return ApiConfig.serviceLlmTts;
      case LLMServiceType.asr:
        return ApiConfig.serviceLlmAsr;
    }
  }

  /// Gets display name
  String get displayName {
    switch (this) {
      case LLMServiceType.text:
        return 'Text Generation';
      case LLMServiceType.vision:
        return 'Image-Text-to-Text';
      case LLMServiceType.embedding:
        return 'Text Embedding';
      case LLMServiceType.tts:
        return 'Text-to-Speech';
      case LLMServiceType.asr:
        return 'Speech-to-Text';
    }
  }
}

/// LLM Client
///
/// Used to proxy requests to various LLM services
class LLMClient {
  static const int _errorBodyPreviewLimit = 512;

  /// Creates LLMClient
  ///
  /// [httpClient] HTTP client for making requests
  /// [serviceLocator] Service locator for dynamic service discovery
  /// [kernelFuture] Future that resolves to KernelService for metrics tracking
  LLMClient({
    HttpClient? httpClient,
    AgentOSServiceLocator? serviceLocator,
    required Future<KernelService?> kernelFuture,
  }) : _httpClient = httpClient ?? HttpClient(),
       _serviceLocator = serviceLocator ?? DefaultServiceLocator(),
       _kernelFuture = kernelFuture;

  final HttpClient _httpClient;
  final AgentOSServiceLocator _serviceLocator;
  final Future<KernelService?> _kernelFuture;

  /// Gets the currently used ServiceLocator
  AgentOSServiceLocator get serviceLocator => _serviceLocator;

  /// Sends request to LLM service
  ///
  /// [serviceType] LLM service type
  /// [method] HTTP method
  /// [path] Request path
  /// [headers] Request headers
  /// [queryParameters] Query parameters
  /// [body] Request body
  /// [streamResponse] Whether to use streaming response
  Future<LLMClientResponse> send({
    required LLMServiceType serviceType,
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

    // When no model specified, fall back to kernel's available config.
    if (kernel != null &&
        serviceType == LLMServiceType.text &&
        (modelIdentifier == null || modelIdentifier.isEmpty)) {
      final availableConfig = kernel.getAvailableLlmConfig();
      if (availableConfig != null) {
        modelIdentifier = availableConfig.model;
        baseUrl ??= availableConfig.baseUrl;
      }
    }

    // Resolve model: look up all models (local + remote), match by id first, then name.
    final resolvedModel = modelIdentifier != null && modelIdentifier.isNotEmpty
        ? await _resolveModel(modelIdentifier)
        : null;

    final modelName = resolvedModel?.name ?? modelIdentifier;
    final requestBody = _rewriteRequestBodyModel(
      body,
      resolvedModel: resolvedModel,
      upstreamModel: modelName,
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

    // Route decision: remote model endpoint vs local service port.
    final Uri uri;
    Map<String, String>? remoteAuthHeaders;

    if (resolvedModel != null && resolvedModel.isRemote) {
      uri = _buildUri(
        Uri.parse(resolvedModel.baseUrl!),
        path,
        queryParameters,
        serviceType: serviceType,
      );
      final apiKey = resolvedModel.apiKey;
      if (apiKey != null && apiKey.isNotEmpty) {
        remoteAuthHeaders = {'authorization': 'Bearer $apiKey'};
      }
    } else {
      final port = await _serviceLocator.getServicePort(
        serviceType.serviceKey,
        modelId: resolvedModel?.id ?? modelIdentifier,
      );
      if (port == null) {
        stopwatch.stop();
        final errorMsg = modelIdentifier != null && modelIdentifier.isNotEmpty
            ? 'Model "$modelIdentifier" unavailable'
            : '${serviceType.displayName} service unavailable';
        metrics?.failed(errorMsg);
        return LLMClientResponse(
          statusCode: 503,
          headers: {'content-type': 'application/json'},
          bodyBytes: utf8.encode(
            jsonEncode({'error': errorMsg, 'service': serviceType.serviceKey}),
          ),
        );
      }
      final baseUri = Uri.parse(ApiConfig.getInternalUrl(port));
      uri = _buildUri(baseUri, path, queryParameters, serviceType: serviceType);
    }

    try {
      final request = await _httpClient.openUrl(method, uri);
      _applyRequestHeaders(request, headers);
      if (remoteAuthHeaders != null) {
        remoteAuthHeaders.forEach((name, value) {
          request.headers.set(name, value);
        });
      }
      if (requestBody != null && requestBody.isNotEmpty) {
        request.add(requestBody);
      }
      final response = await request.close();
      final responseHeaders = _sanitizeResponseHeaders(response.headers);

      if (response.statusCode >= 400 && streamResponse) {
        requestLogger.warning(
          'LLM proxy upstream error: '
          'service=${serviceType.serviceKey} '
          'model=${modelName ?? '-'} '
          'method=$method '
          'uri=$uri '
          'status=${response.statusCode} '
          'stream=true',
        );

        // For error responses on stream requests, read the full body and check
        // for context size errors (llama server returns JSON, not SSE, on error)
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
          return LLMClientResponse(
            statusCode: normalized.statusCode,
            headers: {'content-type': 'application/json'},
            bodyBytes: normalized.bodyBytes,
          );
        }

        // Not a context size error, return original error as non-stream
        return LLMClientResponse(
          statusCode: response.statusCode,
          headers: responseHeaders,
          bodyBytes: errorBytes,
        );
      }

      if (streamResponse) {
        // Wrap the stream to monitor tokens
        final monitoredStream = _createMonitoredStream(
          metrics: metrics,
          stream: response,
          startStopwatch: stopwatch,
          requestStartTime: requestStartTime,
        );

        return LLMClientResponse(
          statusCode: response.statusCode,
          headers: responseHeaders,
          bodyStream: monitoredStream,
        );
      }

      // Non-streaming response
      final bytes = await response.fold<List<int>>(<int>[], (buffer, data) {
        buffer.addAll(data);
        return buffer;
      });

      if (response.statusCode >= 400) {
        requestLogger.warning(
          'LLM proxy upstream error: '
          'service=${serviceType.serviceKey} '
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
          return LLMClientResponse(
            statusCode: normalized.statusCode,
            headers: {'content-type': 'application/json'},
            bodyBytes: normalized.bodyBytes,
          );
        }
      }

      // Complete tracking
      stopwatch.stop();
      final totalTokens = _extractTokenCountFromResponse(bytes);
      metrics?.completed(totalTokens ?? 0);

      return LLMClientResponse(
        statusCode: response.statusCode,
        headers: responseHeaders,
        bodyBytes: bytes,
      );
    } catch (e, stackTrace) {
      // Mark as failed
      stopwatch.stop();
      metrics?.failed(e.toString());
      requestLogger.severe(
        'LLM proxy request failed: '
        'service=${serviceType.serviceKey} '
        'model=${modelName ?? '-'} '
        'method=$method '
        'uri=$uri '
        'error=$e',
        e,
        stackTrace,
      );

      return LLMClientResponse(
        statusCode: 502,
        headers: {'content-type': 'application/json'},
        bodyBytes: utf8.encode(
          jsonEncode({
            'error': 'Backend service unavailable',
            'service': serviceType.serviceKey,
            'message': e.toString(),
          }),
        ),
      );
    }
  }

  /// Creates a monitored stream that tracks token metrics
  ///
  /// Token counting strategy for streaming responses:
  /// 1. Parse each SSE event to extract token count from usage field (most accurate)
  /// 2. Count SSE data events containing content delta (fallback)
  /// 3. Each data event with content typically represents one token
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

    // Accumulated buffer for parsing incomplete SSE events
    final buffer = StringBuffer();

    // Report interval: every second or minimum 10 tokens
    const reportIntervalMs = 1000;
    const minTokensForReport = 10;

    return stream.transform(
      StreamTransformer<List<int>, List<int>>.fromHandlers(
        handleData: (data, sink) {
          // Parse SSE events to count tokens
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

          // First token notification - triggered when we receive any content
          if (!firstTokenReceived && (tokens > 0 || parseResult.hasContent)) {
            firstTokenReceived = true;
            // Kernel's LlmMetrics.setFirstToken expects DateTime
            metrics?.setFirstToken(now);
            lastReportTime = now;
          }

          // TPS reporting - report periodically
          if (lastReportTime != null &&
              tokensSinceLastReport >= minTokensForReport) {
            final elapsed = now.difference(lastReportTime!);
            if (elapsed.inMilliseconds >= reportIntervalMs) {
              final tps =
                  tokensSinceLastReport / max(1, elapsed.inMilliseconds) * 1000;
              // Kernel's LlmMetrics.setTokenPerSecond expects only double tps
              metrics?.setTokenPerSecond(tps);
              lastReportTime = now;
              tokensSinceLastReport = 0;
            }
          }

          sink.add(data);
        },
        handleError: (error, stackTrace, sink) {
          // Kernel's LlmMetrics.failed expects only String error
          metrics?.failed(error.toString());
          sink.addError(error, stackTrace);
        },
        handleDone: (sink) {
          startStopwatch.stop();

          // Final completion notification
          // Kernel's LlmMetrics.completed expects only int totalTokens
          metrics?.completed(totalTokenCount);

          sink.close();
        },
      ),
    );
  }

  /// Parses SSE data to extract token information
  ///
  /// SSE format: "data: {json}\n\n"
  /// OpenAI streaming format includes usage in the final chunk:
  /// - Regular chunks: {"choices":[{"delta":{"content":"..."}}]}
  /// - Final chunk: {"choices":[{"delta":{}}],"usage":{"completion_tokens":N}}
  _SSEParseResult _parseSSETokens(List<int> data, StringBuffer buffer) {
    int incrementalTokens = 0;
    int? absoluteCompletionTokens;
    bool hasContent = false;

    try {
      final text = utf8.decode(data, allowMalformed: true);
      buffer.write(text);

      // Process complete SSE events (ending with \n\n)
      final content = buffer.toString();
      final events = content.split('\n\n');

      // Keep the last incomplete event in buffer
      buffer.clear();
      if (!content.endsWith('\n\n') && events.isNotEmpty) {
        buffer.write(events.removeLast());
      }

      for (final event in events) {
        if (event.trim().isEmpty) continue;

        // Extract data payload from SSE event
        final lines = event.split('\n');
        for (final line in lines) {
          if (line.startsWith('data:')) {
            final jsonStr = line.substring(5).trim();
            if (jsonStr == '[DONE]') continue;

            try {
              final json = jsonDecode(jsonStr) as Map<String, dynamic>;
              final usage = json['usage'] as Map<String, dynamic>?;

              // Check for usage field (most accurate token count)
              if (usage != null) {
                final completionTokens = usage['completion_tokens'];
                if (completionTokens is int && completionTokens > 0) {
                  // completion_tokens is usually absolute total, not delta.
                  final previous = absoluteCompletionTokens ?? 0;
                  if (completionTokens > previous) {
                    absoluteCompletionTokens = completionTokens;
                  }
                  hasContent = true;
                  continue;
                }
              }

              // Check for content in delta (each delta with content = 1 token)
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
              // JSON parse error - skip this event
            }
          }
        }
      }
    } catch (_) {
      // UTF-8 decode error - return minimal count based on data presence
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

  /// Resolves a model by identifier (modelId or modelName).
  ///
  /// Queries all registered models (local + remote) via [getLlmModelList].
  /// Priority: exact id match first, then exact name match.
  Future<LlmModelInfo?> _resolveModel(String identifier) async {
    final models = await _serviceLocator.getLlmModelList();
    // Priority 1: exact id match
    for (final m in models) {
      if (m.id == identifier) return m;
    }
    // Priority 2: exact name match
    for (final m in models) {
      if (m.name == identifier) return m;
    }
    return null;
  }

  /// Extracts model name from request body
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

  /// Extracts base URL from request body (if present)
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

  /// Extracts token count from non-streaming response
  ///
  /// For non-streaming responses, the LLM typically returns usage statistics
  /// in the response body. This method extracts the token count from:
  /// - usage.total_tokens (total tokens including prompt and completion)
  /// - usage.completion_tokens (only completion tokens)
  int? _extractTokenCountFromResponse(List<int> bytes) {
    try {
      final text = utf8.decode(bytes);
      final json = jsonDecode(text) as Map<String, dynamic>;

      // Extract from OpenAI-style usage field
      final usage = json['usage'] as Map<String, dynamic>?;
      if (usage != null) {
        // Prefer total_tokens if available
        final totalTokens = usage['total_tokens'];
        if (totalTokens is int) return totalTokens;

        // Fallback to completion_tokens
        final completionTokens = usage['completion_tokens'];
        if (completionTokens is int) return completionTokens;
      }
    } catch (_) {
      // Ignore parsing errors
    }
    return null;
  }

  Uri _buildUri(
    Uri baseUri,
    String path,
    Map<String, String>? queryParameters, {
    required LLMServiceType serviceType,
  }) {
    final joinedPath = _resolveUpstreamPath(baseUri.path, path, serviceType);
    return baseUri.replace(
      path: joinedPath,
      queryParameters: (queryParameters == null || queryParameters.isEmpty)
          ? null
          : queryParameters,
    );
  }

  void _applyRequestHeaders(
    HttpClientRequest request,
    Map<String, String>? headers,
  ) {
    if (headers == null) {
      return;
    }
    headers.forEach((name, value) {
      final lowerName = name.toLowerCase();
      if (_isHopByHopHeader(lowerName) ||
          lowerName == 'host' ||
          lowerName == 'content-length') {
        return;
      }
      request.headers.set(name, value);
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
    LLMServiceType serviceType,
  ) {
    final normalizedBase = _normalizeBasePath(basePath);
    final normalizedRequest = _normalizeRequestPath(requestPath);
    final defaultEndpoint = _defaultEndpointFor(serviceType);

    if (defaultEndpoint != null &&
        _isCompleteEndpointPath(normalizedBase, defaultEndpoint)) {
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
    if (path.isEmpty || path == '/') {
      return '';
    }
    return path.endsWith('/') ? path.substring(0, path.length - 1) : path;
  }

  String _normalizeRequestPath(String path) {
    if (path.isEmpty || path == '/') {
      return '/';
    }
    return path.startsWith('/') ? path : '/$path';
  }

  bool _isEmptyRequestPath(String path) => path == '/';

  String? _defaultEndpointFor(LLMServiceType serviceType) {
    switch (serviceType) {
      case LLMServiceType.text:
      case LLMServiceType.vision:
        return '/chat/completions';
      case LLMServiceType.embedding:
        return '/embeddings';
      case LLMServiceType.tts:
        return '/audio/speech';
      case LLMServiceType.asr:
        return '/audio/transcriptions';
    }
  }

  bool _isCompleteEndpointPath(String basePath, String endpoint) {
    return basePath == endpoint || basePath.endsWith(endpoint);
  }

  String? _extractTrailingVersionSegment(String path) {
    if (path.isEmpty) {
      return null;
    }
    final segments = Uri(path: path).pathSegments;
    if (segments.isEmpty) {
      return null;
    }
    final lastSegment = segments.last;
    return _isVersionSegment(lastSegment) ? '/$lastSegment' : null;
  }

  String? _extractLeadingVersionSegment(String path) {
    final segments = Uri(path: path).pathSegments;
    if (segments.isEmpty) {
      return null;
    }
    final firstSegment = segments.first;
    return _isVersionSegment(firstSegment) ? '/$firstSegment' : null;
  }

  String _stripLeadingVersionSegment(String path) {
    final segments = Uri(path: path).pathSegments;
    if (segments.isEmpty || !_isVersionSegment(segments.first)) {
      return path;
    }
    if (segments.length == 1) {
      return '/';
    }
    return '/${segments.skip(1).join('/')}';
  }

  bool _isVersionSegment(String segment) {
    return RegExp(r'^v\d+$').hasMatch(segment);
  }

  String? _normalizeEndpointSuffix(String path, String? defaultEndpoint) {
    if (_isEmptyRequestPath(path)) {
      return defaultEndpoint;
    }
    final pathWithoutVersion = _stripLeadingVersionSegment(path);
    if (_isEmptyRequestPath(pathWithoutVersion)) {
      return defaultEndpoint;
    }
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
      if (decoded is! Map<String, dynamic>) {
        return body;
      }
      if (decoded['model'] == upstreamModel) {
        return body;
      }

      decoded['model'] = upstreamModel;
      return utf8.encode(jsonEncode(decoded));
    } catch (_) {
      return body;
    }
  }

  /// Detects context-size-exceeded errors from any LLM provider and normalizes
  /// them to a unified OpenAI-compatible `context_length_exceeded` format.
  ///
  /// Supported providers:
  ///   - llama.cpp: type "exceed_context_size_error", fields n_prompt_tokens/n_ctx
  ///   - OpenAI: code "context_length_exceeded"
  ///   - Anthropic: type "invalid_request_error" + context message
  ///   - Gemini: status "INVALID_ARGUMENT" + token count message
  ///   - LM Studio: plain string error with "keep the first X tokens when context the overflows"
  ///   - Generic OpenAI-compatible: fallback message pattern matching
  ///
  /// Returns null if the error is not a context size error.
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

        // llama.cpp structured fields
        nPromptTokens = error['n_prompt_tokens'] as int?;
        nCtx = error['n_ctx'] as int?;

        // 1. llama.cpp: type == "exceed_context_size_error"
        if (type == 'exceed_context_size_error') {
          matched = true;
        }
        // 2. OpenAI: code == "context_length_exceeded"
        else if (codeStr == 'context_length_exceeded') {
          matched = true;
        }
        // 3. Gemini: status == "INVALID_ARGUMENT" + token count message
        else if (status == 'INVALID_ARGUMENT' &&
            message != null &&
            _isContextSizeMessage(message)) {
          matched = true;
        }
        // 4. Anthropic / generic: type == "invalid_request_error" + context-related message
        else if (type == 'invalid_request_error' &&
            message != null &&
            _isContextSizeMessage(message)) {
          matched = true;
        }
        // 5. Fallback: any message that matches context size patterns
        else if (message != null && _isContextSizeMessage(message)) {
          matched = true;
        }
      } else if (error is String && _isContextSizeMessage(error)) {
        message = error;
        matched = true;
      }

      if (!matched) return null;

      // Extract token counts from the message if not already provided by structured fields
      if (nPromptTokens == null || nCtx == null) {
        final extracted = _extractTokenCounts(message, nPromptTokens, nCtx);
        nPromptTokens ??= extracted.requested;
        nCtx ??= extracted.limit;
      }

      // Build unified OpenAI-compatible error response
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
          if (nPromptTokens != null) 'n_prompt_tokens': nPromptTokens,
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

  /// Patterns that identify context-size-exceeded errors across providers.
  static final _contextSizePatterns = [
    // llama.cpp
    RegExp(
      r'exceeds?\s+the\s+available\s+context\s+size',
      caseSensitive: false,
    ),
    RegExp(
      r'input\s+is\s+larger\s+than\s+the\s+max\s+context\s+size',
      caseSensitive: false,
    ),
    RegExp(r'context\s+size\s+has\s+been\s+exceeded', caseSensitive: false),
    // OpenAI / OpenAI-compatible
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
    // Anthropic
    RegExp(r'prompt\s+is\s+too\s+long', caseSensitive: false),
    RegExp(r'exceed\s+context\s+limit', caseSensitive: false),
    // Gemini
    RegExp(
      r'input\s+token\s+count\s*\(\d+\)\s*exceeds\s+the\s+maximum\s+number\s+of\s+tokens\s+allowed',
      caseSensitive: false,
    ),
    // LM Studio
    RegExp(
      r'keep\s+the\s+first\s+\d+\s+tokens\s+when\s+context\s+the\s+overflows',
      caseSensitive: false,
    ),
    RegExp(
      r'tokens\s+to\s+keep\s+from\s+the\s+initial\s+prompt\s+is\s+greater\s+than\s+the\s+context\s+length',
      caseSensitive: false,
    ),
    // Generic
    RegExp(r'token.{0,20}limit.{0,20}exceed', caseSensitive: false),
  ];

  bool _isContextSizeMessage(String message) {
    return _contextSizePatterns.any((p) => p.hasMatch(message));
  }

  /// Extracts (requested_tokens, limit_tokens) from various error message formats.
  ///
  /// Supports:
  ///   - "maximum context length is 8192 tokens, but you requested 9000 tokens"
  ///   - "request (4390 tokens) exceeds the available context size (4096 tokens)"
  ///   - "prompt is too long: 201543 tokens > 200000 maximum"
  ///   - "input token count (1067544) exceeds the maximum number of tokens allowed (1048576)"
  ///   - "input length and max_tokens exceed context limit: 184915 + 20000 > 200000"
  ///   - "keep the first 15857 tokens when context the overflows...context length of only 4096 tokens"
  static final _tokenCountPatterns = [
    // OpenAI: "maximum context length is X tokens...requested Y tokens"
    RegExp(
      r'maximum\s+context\s+length\s+is\s+(\d+)\s+tokens.*?(\d+)\s+tokens',
      caseSensitive: false,
    ),
    // llama.cpp: "request (X tokens) exceeds...context size (Y tokens)"
    RegExp(
      r'request\s*\((\d+)\s*tokens?\).*?context\s+size\s*\((\d+)\s*tokens?\)',
      caseSensitive: false,
    ),
    // Anthropic: "prompt is too long: X tokens > Y maximum"
    RegExp(
      r'prompt\s+is\s+too\s+long:\s*(\d+)\s*tokens?\s*>\s*(\d+)',
      caseSensitive: false,
    ),
    // Anthropic: "input length and max_tokens exceed context limit: X + Y > Z"
    RegExp(
      r'exceed\s+context\s+limit:\s*(\d+)\s*\+\s*\d+\s*>\s*(\d+)',
      caseSensitive: false,
    ),
    // Gemini: "input token count (X) exceeds...tokens allowed (Y)"
    RegExp(
      r'input\s+token\s+count\s*\((\d+)\).*?tokens\s+allowed\s*\((\d+)\)',
      caseSensitive: false,
    ),
    // LM Studio: "keep the first X tokens when context the overflows...context length of only Y tokens"
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
          // For OpenAI pattern, group 1 is limit, group 2 is requested
          if (pattern == _tokenCountPatterns[0]) {
            return _TokenCountResult(
              requested: existingRequested ?? g2,
              limit: existingLimit ?? g1,
            );
          }
          // For all other patterns, group 1 is requested, group 2 is limit
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
    if (bytes.isEmpty) {
      return '';
    }
    return utf8.decode(bytes, allowMalformed: true);
  }

  String _truncateForLog(String value) {
    final normalized = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.length <= _errorBodyPreviewLimit) {
      return normalized;
    }
    return '${normalized.substring(0, _errorBodyPreviewLimit)}...';
  }
}

/// Normalized error response
class _NormalizedError {
  final int statusCode;
  final List<int> bodyBytes;

  const _NormalizedError({required this.statusCode, required this.bodyBytes});
}

/// Result of extracting token counts from error messages
class _TokenCountResult {
  final int? requested;
  final int? limit;

  const _TokenCountResult({this.requested, this.limit});
}

/// Result of parsing SSE data for tokens
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
