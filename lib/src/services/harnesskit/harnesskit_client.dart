import 'dart:async';
import 'dart:io';

const defaultHarnessKitBundleId = 'com.litevar.agentosHarness';

/// Optional host-provided client overrides keyed by authenticated AppKit
/// bundle. AgentOS-managed Apps use the shared managed client instead.
final class HarnessKitClientRegistry {
  final Map<String, HarnessKitClient> _clients = <String, HarnessKitClient>{};

  HarnessKitClient? resolve(String bundleId) => _clients[bundleId];

  void register(String bundleId, HarnessKitClient client) {
    if (bundleId.isEmpty || bundleId != bundleId.trim()) {
      throw ArgumentError.value(
        bundleId,
        'bundleId',
        'must be non-empty and have no surrounding whitespace',
      );
    }
    final existing = _clients[bundleId];
    if (existing != null && !identical(existing, client)) {
      throw StateError(
        'Unregister the existing HarnessKit client before replacing it',
      );
    }
    for (final entry in _clients.entries) {
      if (entry.key != bundleId && identical(entry.value, client)) {
        throw ArgumentError(
          'A HarnessKit client cannot be shared by multiple AppKit bundles',
        );
      }
    }
    _clients[bundleId] = client;
  }

  HarnessKitClient? unregister(String bundleId) => _clients.remove(bundleId);

  Set<String> get registeredBundleIds => Set.unmodifiable(_clients.keys);
}

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
/// Gateway replaces it with the sidecar-specific internal bearer token.
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
    String? actorBundleId,
  }) async {
    final request = await _httpClient.openUrl(
      method,
      _buildUri(path, queryParameters),
    );
    _applyRequestHeaders(request, headers);
    request.headers.set('authorization', 'Bearer $_internalBearerToken');
    if (actorBundleId != null && actorBundleId.isNotEmpty) {
      request.headers.set('x-agentos-app-bundle-id', actorBundleId);
    }
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
          lowerName == 'authorization' ||
          lowerName == 'x-agentos-app-bundle-id') {
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

  /// Closes this client's connection pool. Call after removing it from the
  /// registry and shutting down its sidecar.
  void close({bool force = false}) => _httpClient.close(force: force);

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
