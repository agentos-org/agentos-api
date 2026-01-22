import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../contracts/service_locator.dart';
import '../../contracts/default_service_locator.dart';
import '../../gateway/gateway_config.dart';

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
enum LLMServiceType {
  text,
  vision,
  embedding,
  tts,
  asr,
}

/// LLM service type extension
extension LLMServiceTypeExtension on LLMServiceType {
  /// Gets service identifier
  String get serviceKey {
    switch (this) {
      case LLMServiceType.text:
        return GatewayConfig.serviceLlmText;
      case LLMServiceType.vision:
        return GatewayConfig.serviceLlmVision;
      case LLMServiceType.embedding:
        return GatewayConfig.serviceLlmEmbedding;
      case LLMServiceType.tts:
        return GatewayConfig.serviceLlmTts;
      case LLMServiceType.asr:
        return GatewayConfig.serviceLlmAsr;
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
  LLMClient({
    HttpClient? httpClient,
    AgentOSServiceLocator? serviceLocator,
  })  : _httpClient = httpClient ?? HttpClient(),
        _serviceLocator = serviceLocator ?? DefaultServiceLocator();

  final HttpClient _httpClient;
  final AgentOSServiceLocator _serviceLocator;

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
    // Resolve target port (LLM services need dynamic routing based on model field)
    final port = await _serviceLocator.resolveLLMPort(
      serviceType.serviceKey,
      body,
    );

    if (port == null) {
      return LLMClientResponse(
        statusCode: 503,
        headers: {'content-type': 'application/json'},
        bodyBytes: utf8.encode(jsonEncode({
          'error': '${serviceType.displayName} service unavailable',
          'service': serviceType.serviceKey,
        })),
      );
    }

    final baseUri = Uri.parse(GatewayConfig.getInternalUrl(port));
    final uri = _buildUri(baseUri, path, queryParameters);

    try {
      final request = await _httpClient.openUrl(method, uri);
      _applyRequestHeaders(request, headers);
      if (body != null && body.isNotEmpty) {
        request.add(body);
      }
      final response = await request.close();
      final responseHeaders = _sanitizeResponseHeaders(response.headers);

      if (streamResponse) {
        return LLMClientResponse(
          statusCode: response.statusCode,
          headers: responseHeaders,
          bodyStream: response,
        );
      }
      final bytes = await response.fold<List<int>>(<int>[], (buffer, data) {
        buffer.addAll(data);
        return buffer;
      });
      return LLMClientResponse(
        statusCode: response.statusCode,
        headers: responseHeaders,
        bodyBytes: bytes,
      );
    } catch (e) {
      return LLMClientResponse(
        statusCode: 502,
        headers: {'content-type': 'application/json'},
        bodyBytes: utf8.encode(jsonEncode({
          'error': 'Backend service unavailable',
          'service': serviceType.serviceKey,
          'message': e.toString(),
        })),
      );
    }
  }

  Uri _buildUri(Uri baseUri, String path, Map<String, String>? queryParameters) {
    final joinedPath = _joinPaths(baseUri.path, path);
    return baseUri.replace(
      path: joinedPath,
      queryParameters:
          (queryParameters == null || queryParameters.isEmpty)
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
    final normalizedBase =
        basePath.isEmpty || basePath == '/' ? '' : basePath;
    final normalizedNext = path.startsWith('/') ? path : '/$path';
    if (normalizedBase.endsWith('/')) {
      return '${normalizedBase.substring(0, normalizedBase.length - 1)}'
          '$normalizedNext';
    }
    return '$normalizedBase$normalizedNext';
  }
}
