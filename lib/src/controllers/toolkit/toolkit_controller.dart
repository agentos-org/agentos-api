import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../../middleware.dart';
import '../../services/appkit/appkit_service.dart';
import '../../services/toolkit/opentool_client.dart';

/// ToolKit Controller
///
/// Proxies requests to OpenTool service
class ToolKitController {
  ToolKitController({OpenToolClient? client, AppKitService? appKitService})
    : _client = client ?? OpenToolClient(),
      _appKitService = appKitService ?? AppKitService();

  final OpenToolClient _client;
  final AppKitService _appKitService;

  Router get router {
    final router = Router();
    final guard = requireBearer();

    router.get('/list', guard(_forwardList));
    router.get('/<toolId>/load', guard(_forwardToolLoad));
    router.post('/<toolId>/call', guard(_forwardToolCall));
    router.post('/<toolId>/streamCall', guard(_forwardToolStreamCall));

    return router;
  }

  Future<Response> _forwardList(Request request) async {
    if (!_isAuthorized(request)) {
      requestLogger.warning('ToolKit: invalid bearer token.');
      return unauthorizedResponse();
    }
    return _proxy(request, path: '/list');
  }

  Future<Response> _forwardToolLoad(Request request) async {
    final toolId = request.params['toolId'];
    if (toolId == null || toolId.isEmpty) {
      return Response.notFound('Tool not found');
    }
    if (!_isAuthorized(request)) {
      requestLogger.warning('ToolKit: invalid bearer token.');
      return unauthorizedResponse();
    }
    return _proxy(request, path: '/$toolId/load');
  }

  Future<Response> _forwardToolCall(Request request) async {
    final toolId = request.params['toolId'];
    if (toolId == null || toolId.isEmpty) {
      return Response.notFound('Tool not found');
    }
    if (!_isAuthorized(request)) {
      requestLogger.warning('ToolKit: invalid bearer token.');
      return unauthorizedResponse();
    }
    return _proxy(request, path: '/$toolId/call');
  }

  Future<Response> _forwardToolStreamCall(Request request) async {
    final toolId = request.params['toolId'];
    if (toolId == null || toolId.isEmpty) {
      return Response.notFound('Tool not found');
    }
    if (!_isAuthorized(request)) {
      requestLogger.warning('ToolKit: invalid bearer token.');
      return unauthorizedResponse();
    }
    return _proxy(request, path: '/$toolId/streamCall', stream: true);
  }

  bool _isAuthorized(Request request) {
    final token = bearerTokenFrom(request);
    return token != null &&
        token.isNotEmpty &&
        _appKitService.isTokenValid(token);
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
