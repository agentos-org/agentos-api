import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../../middleware.dart';
import '../../services/appkit/appkit_service.dart';
import '../../services/harnesskit/harnesskit_client.dart';

/// Gateway bridge for the built-in Harness WebApp.
///
/// Requests must carry a valid AppKit bundle token. Once authorized, the
/// controller forwards the request to the loopback Harness sidecar with the
/// sidecar-only internal token.
class HarnessKitController {
  HarnessKitController({
    required HarnessKitClient client,
    required AppKitService appKitService,
    this.bundleId = 'com.litevar.agentosHarness',
  }) : _client = client,
       _appKitService = appKitService;

  final HarnessKitClient _client;
  final AppKitService _appKitService;
  final String bundleId;

  Router get router {
    final router = Router();
    final guard = requireBearer();
    router.all('/', guard(_forwardRoot));
    router.all('/<path|.*>', guard(_forwardPath));
    return router;
  }

  Future<Response> _forwardRoot(Request request) =>
      _forward(request, path: '/');

  Future<Response> _forwardPath(Request request) {
    final rawPath = request.params['path'] ?? '';
    return _forward(request, path: rawPath.isEmpty ? '/' : '/$rawPath');
  }

  Future<Response> _forward(Request request, {required String path}) async {
    final token = bearerTokenFrom(request);
    if (token == null ||
        token.isEmpty ||
        !_appKitService.isTokenValid(token) ||
        _appKitService.bundleIdForToken(token) != bundleId) {
      requestLogger.warning('HarnessKit: invalid bearer token.');
      return unauthorizedResponse();
    }

    try {
      final response = await _client.send(
        method: request.method,
        path: path,
        headers: request.headers,
        queryParameters: request.url.queryParameters,
        body: await _readBodyBytes(request),
        streamResponse: _isStreamingRequest(request, path),
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
    } catch (error) {
      requestLogger.warning('HarnessKit proxy unavailable: $error');
      return Response(
        502,
        body: jsonEncode({
          'error': {
            'code': 'harness_unavailable',
            'message': 'Harness service unavailable',
          },
        }),
        headers: const {'content-type': 'application/json'},
      );
    }
  }

  bool _isStreamingRequest(Request request, String path) {
    final accept = request.headers['accept']?.toLowerCase() ?? '';
    return accept.contains('text/event-stream') || path.endsWith('/events');
  }

  Future<List<int>?> _readBodyBytes(Request request) async {
    if (request.method == 'GET' || request.method == 'HEAD') return null;
    final bytes = await request.read().fold<List<int>>(<int>[], (buffer, data) {
      buffer.addAll(data);
      return buffer;
    });
    return bytes.isEmpty ? null : bytes;
  }
}
