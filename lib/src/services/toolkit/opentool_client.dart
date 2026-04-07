import 'dart:async';
import 'dart:io';

import '../../locator.dart';
import '../../config.dart';

/// OpenTool client response
class OpenToolClientResponse {
  OpenToolClientResponse({
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

/// OpenTool Client
///
/// Used to proxy requests to OpenTool service
class OpenToolClient {
  /// Creates OpenToolClient
  ///
  /// Priority:
  /// 1. Explicitly provided [baseUri]
  /// 2. Obtained from [serviceLocator]
  /// 3. Use default port
  OpenToolClient({
    Uri? baseUri,
    HttpClient? httpClient,
    AgentOSServiceLocator? serviceLocator,
  }) : _baseUri = baseUri,
       _httpClient = httpClient ?? HttpClient(),
       _serviceLocator = serviceLocator ?? DefaultServiceLocator();

  final Uri? _baseUri;
  final HttpClient _httpClient;
  final AgentOSServiceLocator _serviceLocator;

  /// Gets the currently used ServiceLocator
  AgentOSServiceLocator get serviceLocator => _serviceLocator;

  /// Sends request to OpenTool service
  Future<OpenToolClientResponse> send({
    required String method,
    required String path,
    Map<String, String>? headers,
    Map<String, String>? queryParameters,
    List<int>? body,
    bool streamResponse = false,
  }) async {
    final baseUri = await _resolveBaseUri();
    if (baseUri == null) {
      return OpenToolClientResponse(
        statusCode: 503,
        headers: {'content-type': 'application/json'},
        bodyBytes: '{"error": "OpenTool service unavailable"}'.codeUnits,
      );
    }

    final uri = _buildUri(baseUri, path, queryParameters);
    final request = await _httpClient.openUrl(method, uri);
    _applyRequestHeaders(request, headers);
    if (body != null && body.isNotEmpty) {
      request.add(body);
    }
    final response = await request.close();
    final responseHeaders = _sanitizeResponseHeaders(response.headers);
    if (streamResponse) {
      return OpenToolClientResponse(
        statusCode: response.statusCode,
        headers: responseHeaders,
        bodyStream: response,
      );
    }
    final bytes = await response.fold<List<int>>(<int>[], (buffer, data) {
      buffer.addAll(data);
      return buffer;
    });
    return OpenToolClientResponse(
      statusCode: response.statusCode,
      headers: responseHeaders,
      bodyBytes: bytes,
    );
  }

  Future<Uri?> _resolveBaseUri() async {
    if (_baseUri != null) {
      return _baseUri;
    }
    final port = await _serviceLocator.getServicePort(
      ApiConfig.serviceOpentool,
    );
    if (port == null) {
      return null;
    }
    return Uri.parse(ApiConfig.getInternalUrl(port));
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
