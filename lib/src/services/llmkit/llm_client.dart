import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:agentos_kernel/agentos_kernel.dart';
import 'package:unique_id_dart/unique_id_dart.dart';

import '../../locator.dart';
import '../../config.dart';

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
      uri = _buildUri(Uri.parse(resolvedModel.baseUrl!), path, queryParameters);
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
            jsonEncode({
              'error': errorMsg,
              'service': serviceType.serviceKey,
            }),
          ),
        );
      }
      final baseUri = Uri.parse(ApiConfig.getInternalUrl(port));
      uri = _buildUri(baseUri, path, queryParameters);
    }

    try {
      final request = await _httpClient.openUrl(method, uri);
      _applyRequestHeaders(request, headers);
      if (remoteAuthHeaders != null) {
        remoteAuthHeaders.forEach((name, value) {
          request.headers.set(name, value);
        });
      }
      if (body != null && body.isNotEmpty) {
        request.add(body);
      }
      final response = await request.close();
      final responseHeaders = _sanitizeResponseHeaders(response.headers);

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

      // Complete tracking
      stopwatch.stop();
      final totalTokens = _extractTokenCountFromResponse(bytes);
      metrics?.completed(totalTokens ?? 0);

      return LLMClientResponse(
        statusCode: response.statusCode,
        headers: responseHeaders,
        bodyBytes: bytes,
      );
    } catch (e) {
      // Mark as failed
      stopwatch.stop();
      metrics?.failed(e.toString());

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

              // Check for usage field (most accurate token count)
              final usage = json['usage'] as Map<String, dynamic>?;
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
    Map<String, String>? queryParameters,
  ) {
    final joinedPath = _joinPaths(baseUri.path, path);
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

  String _joinPaths(String basePath, String path) {
    final normalizedBase = basePath.isEmpty || basePath == '/' ? '' : basePath;
    final normalizedNext = path.startsWith('/') ? path : '/$path';
    if (normalizedBase.endsWith('/')) {
      return '${normalizedBase.substring(0, normalizedBase.length - 1)}'
          '$normalizedNext';
    }
    return '$normalizedBase$normalizedNext';
  }
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
