import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:agentos_kernel/agentos_kernel.dart';
import 'package:liteagent_sdk_dart/liteagent_sdk_dart.dart';

import '../../locator.dart';

class LiteagentClientResponse {
  LiteagentClientResponse({
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

class LiteagentClient {
  /// Creates LiteagentClient
  ///
  /// Priority:
  /// 1. Explicitly provided [baseUri]
  /// 2. Obtained from [serviceLocator]
  /// 3. Resolved from environment variables (default behavior)
  ///
  /// [kernelFuture] Future that resolves to KernelService for agent message recording
  LiteagentClient({
    Uri? baseUri,
    HttpClient? httpClient,
    AgentOSServiceLocator? serviceLocator,
    Future<KernelService?>? kernelFuture,
  }) : _baseUri = baseUri ?? _resolveBaseUri(serviceLocator),
       _httpClient = httpClient ?? HttpClient(),
       _serviceLocator = serviceLocator,
       _kernelFuture = kernelFuture ?? Future.value(null);

  final Uri _baseUri;
  final HttpClient _httpClient;
  final AgentOSServiceLocator? _serviceLocator;
  final Future<KernelService?> _kernelFuture;

  /// Gets the currently used ServiceLocator
  AgentOSServiceLocator? get serviceLocator => _serviceLocator;

  /// Returns an available LLM config from kernel as LiteAgent-compatible JSON.
  ///
  /// Returns null when kernel is unavailable or no model is currently available.
  Future<Map<String, dynamic>?> getAvailableLlmConfigJson() async {
    final kernel = await _kernelFuture;
    if (kernel == null) {
      return null;
    }
    final config = kernel.getAvailableLlmConfig();
    if (config == null) {
      return null;
    }

    final dynamic llm = config;
    final result = <String, dynamic>{
      'baseUrl': llm.baseUrl,
      'apiKey': llm.apiKey,
      'model': llm.model,
      'temperature': llm.temperature,
      'maxTokens': llm.maxTokens,
      'contextWindowSize': llm.contextWindowSize,
      'topP': llm.topP,
      'supportsToolCall': llm.supportsToolCalling,
      'supportsReasoning': llm.supportsDeepThinking,
    };
    result.removeWhere((_, value) => value == null);
    return result;
  }

  /// Sends request to LiteAgent service
  ///
  /// [method] HTTP method
  /// [path] Request path
  /// [headers] Request headers
  /// [queryParameters] Query parameters
  /// [body] Request body
  /// [streamResponse] Whether to use streaming response
  /// [userId] User ID for agent message recording
  /// [bundleId] Bundle ID for agent message recording
  Future<LiteagentClientResponse> send({
    required String method,
    required String path,
    Map<String, String>? headers,
    Map<String, String>? queryParameters,
    List<int>? body,
    bool streamResponse = false,
    String? userId,
    String? bundleId,
  }) async {
    final uri = _buildUri(path, queryParameters);
    final request = await _httpClient.openUrl(method, uri);
    _applyRequestHeaders(request, headers);
    if (body != null && body.isNotEmpty) {
      request.add(body);
    }
    final response = await request.close();
    final responseHeaders = _sanitizeResponseHeaders(response.headers);
    if (streamResponse) {
      final monitoredStream = _createMonitoredStream(
        stream: response,
        userId: userId,
        bundleId: bundleId,
      );
      return LiteagentClientResponse(
        statusCode: response.statusCode,
        headers: responseHeaders,
        bodyStream: monitoredStream,
      );
    }
    final bytes = await response.fold<List<int>>(<int>[], (buffer, data) {
      buffer.addAll(data);
      return buffer;
    });

    _recordAgentMessagesFromBytes(bytes, userId: userId, bundleId: bundleId);

    return LiteagentClientResponse(
      statusCode: response.statusCode,
      headers: responseHeaders,
      bodyBytes: bytes,
    );
  }

  /// Creates a monitored stream that records agent messages from SSE events
  ///
  /// SSE format from LiteAgent:
  /// - event:MESSAGE\ndata:{AgentMessage json}\n\n
  /// - event:CHUNK\ndata:{AgentMessageChunk json}\n\n
  /// - event:FUNCTION_CALL\ndata:{AgentMessage json}\n\n
  Stream<List<int>> _createMonitoredStream({
    required Stream<List<int>> stream,
    String? userId,
    String? bundleId,
  }) {
    final buffer = StringBuffer();

    return stream.transform(
      StreamTransformer<List<int>, List<int>>.fromHandlers(
        handleData: (data, sink) {
          _parseAndRecordSSEMessages(
            data,
            buffer,
            userId: userId,
            bundleId: bundleId,
          );
          sink.add(data);
        },
        handleError: (error, stackTrace, sink) {
          sink.addError(error, stackTrace);
        },
        handleDone: (sink) {
          sink.close();
        },
      ),
    );
  }

  /// Parses SSE data and records AgentMessage events to KernelService
  void _parseAndRecordSSEMessages(
    List<int> data,
    StringBuffer buffer, {
    String? userId,
    String? bundleId,
  }) {
    if (userId == null || bundleId == null) return;

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

        String? eventType;
        String? dataPayload;

        final lines = event.split('\n');
        for (final line in lines) {
          if (line.startsWith('event:')) {
            eventType = line.substring(6).trim();
          } else if (line.startsWith('data:')) {
            dataPayload = line.substring(5).trim();
          }
        }

        if (eventType == 'MESSAGE' && dataPayload != null) {
          _recordSingleAgentMessage(
            dataPayload,
            userId: userId,
            bundleId: bundleId,
          );
        }
      }
    } catch (_) {
      //
    }
  }

  /// Records a single AgentMessage from JSON string
  void _recordSingleAgentMessage(
    String jsonStr, {
    required String userId,
    required String bundleId,
  }) {
    try {
      final json = jsonDecode(jsonStr) as Map<String, dynamic>;
      final agentMessage = AgentMessage.fromJson(json);

      _kernelFuture
          .then((kernel) {
            if (kernel == null) return;
            kernel.recordAgentMessage(
              userId: userId,
              bundleId: bundleId,
              agentMessage: agentMessage,
            );
          })
          .catchError((_) {
            //
          });
    } catch (_) {
      //
    }
  }

  /// Records AgentMessages from non-streaming response bytes
  void _recordAgentMessagesFromBytes(
    List<int> bytes, {
    String? userId,
    String? bundleId,
  }) {
    if (userId == null || bundleId == null) return;
    if (bytes.isEmpty) return;

    try {
      final text = utf8.decode(bytes, allowMalformed: true);
      final json = jsonDecode(text);

      if (json is Map<String, dynamic>) {
        _recordSingleAgentMessage(
          jsonEncode(json),
          userId: userId,
          bundleId: bundleId,
        );
      } else if (json is List) {
        for (final item in json) {
          if (item is Map<String, dynamic>) {
            _recordSingleAgentMessage(
              jsonEncode(item),
              userId: userId,
              bundleId: bundleId,
            );
          }
        }
      }
    } catch (_) {
      //
    }
  }

  Uri _buildUri(String path, Map<String, String>? queryParameters) {
    final joinedPath = _joinPaths(_baseUri.path, path);
    return _baseUri.replace(
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

  static Uri _resolveBaseUri(AgentOSServiceLocator? serviceLocator) {
    if (serviceLocator != null) {
      return Uri.parse(serviceLocator.liteagentBaseUrl);
    }
    // Use default implementation (based on environment variables)
    return Uri.parse(DefaultServiceLocator().liteagentBaseUrl);
  }
}
