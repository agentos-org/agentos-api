import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../../services/toolkit/opentool_client.dart';

/// ToolKit Controller
///
/// Proxies requests to OpenTool service
class ToolKitController {
  ToolKitController({OpenToolClient? client})
    : _client = client ?? OpenToolClient();

  final OpenToolClient _client;

  Router get router {
    final router = Router();

    // Transparently proxy all requests to OpenTool
    router.all('/<path|.*>', _forwardAll);

    return router;
  }

  /// Forwards all requests
  Future<Response> _forwardAll(Request request) async {
    final path = request.params['path'] ?? '';
    return _proxy(request, path: '/$path');
  }

  Future<Response> _proxy(
    Request request, {
    required String path,
    bool stream = false,
  }) async {
    try {
      final bodyBytes = await _readBodyBytes(request);
      final response = await _client.send(
        method: request.method,
        path: path,
        queryParameters: request.url.queryParameters,
        headers: request.headers,
        body: bodyBytes,
        streamResponse: stream,
      );
      if (response.bodyStream != null) {
        return Response(
          response.statusCode,
          body: response.bodyStream,
          headers: response.headers,
          context: const {'shelf.io.buffer_output': false},
        );
      }
      return Response(
        response.statusCode,
        body: response.bodyBytes,
        headers: response.headers,
      );
    } on Exception catch (error) {
      return Response(502, body: 'OpenTool proxy error: $error');
    }
  }

  Future<List<int>?> _readBodyBytes(Request request) async {
    if (request.method == 'GET' || request.method == 'HEAD') {
      return null;
    }
    final bytes = await request.read().fold<List<int>>(<int>[], (buffer, data) {
      buffer.addAll(data);
      return buffer;
    });
    return bytes.isEmpty ? null : bytes;
  }
}
