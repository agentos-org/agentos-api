import 'dart:async';
import 'dart:io';

/// Response returned by the internal Harness sidecar proxy.
class HarnessKitClientResponse {
  HarnessKitClientResponse({
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

/// HTTP client used by Gateway's internal HarnessKit bridge.
///
/// The browser-facing AppKit token is never forwarded to the sidecar. The
/// Gateway replaces it with a per-process internal bearer token instead.
class HarnessKitClient {
  HarnessKitClient({
    required Uri baseUri,
    required String internalBearerToken,
    HttpClient? httpClient,
  }) : _baseUri = baseUri,
       _internalBearerToken = internalBearerToken,
       _httpClient = httpClient ?? HttpClient();

  final Uri _baseUri;
  final String _internalBearerToken;
  final HttpClient _httpClient;

  Future<HarnessKitClientResponse> send({
    required String method,
    required String path,
    Map<String, String>? headers,
    Map<String, String>? queryParameters,
    List<int>? body,
    bool streamResponse = false,
  }) async {
    final request = await _httpClient.openUrl(
      method,
      _buildUri(path, queryParameters),
    );
    _applyRequestHeaders(request, headers);
    request.headers.set('authorization', 'Bearer $_internalBearerToken');
    if (body != null && body.isNotEmpty) {
      request.add(body);
    }

    final response = await request.close();
    final responseHeaders = _sanitizeResponseHeaders(response.headers);
    if (streamResponse) {
      return HarnessKitClientResponse(
        statusCode: response.statusCode,
        headers: responseHeaders,
        bodyStream: response,
      );
    }

    final bytes = await response.fold<List<int>>(<int>[], (buffer, data) {
      buffer.addAll(data);
      return buffer;
    });
    return HarnessKitClientResponse(
      statusCode: response.statusCode,
      headers: responseHeaders,
      bodyBytes: bytes,
    );
  }

  Uri _buildUri(String requestPath, Map<String, String>? queryParameters) {
    final basePath = _baseUri.path == '/' ? '' : _baseUri.path;
    final nextPath = requestPath.startsWith('/')
        ? requestPath
        : '/$requestPath';
    return _baseUri.replace(
      path: '$basePath$nextPath',
      queryParameters: queryParameters == null || queryParameters.isEmpty
          ? null
          : queryParameters,
    );
  }

  void _applyRequestHeaders(
    HttpClientRequest request,
    Map<String, String>? headers,
  ) {
    if (headers == null) return;
    headers.forEach((name, value) {
      final lowerName = name.toLowerCase();
      if (_isHopByHopHeader(lowerName) ||
          lowerName == 'host' ||
          lowerName == 'content-length' ||
          lowerName == 'authorization') {
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
}
