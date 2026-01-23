import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../../middleware.dart';
import '../../services/agentkit/liteagent_client.dart';

class AgentKitController {
  AgentKitController({LiteagentClient? client})
      : _client = client ?? LiteagentClient();

  final LiteagentClient _client;

  Router get router {
    final router = Router();
    final guard = requireBearer();
    router.get('/version', guard(_forward('/version')));
    router.get('/agent', guard(_forward('/agent')));
    router.post('/agent/create', guard(_forward('/agent/create')));
    router.post('/agent/update', guard(_forward('/agent/update')));
    router.get('/agent/delete', guard(_forward('/agent/delete')));
    router.post('/initSession', guard(_forward('/initSession')));
    router.post('/initSimple', guard(_forward('/initSimple')));
    router.post('/chat', guard(_forward('/chat', stream: true)));
    router.post('/chat/simple', guard(_forward('/chat/simple')));
    router.get('/history', guard(_forward('/history')));
    router.get('/stop', guard(_forward('/stop')));
    router.get('/clear', guard(_forward('/clear')));
    router.post('/callback', guard(_forward('/callback')));
    router.post('/streamCallback', guard(_forward('/streamCallback')));
    return router;
  }

  Handler _forward(String path, {bool stream = false}) {
    return (Request request) => _proxy(request, path: path, stream: stream);
  }

  Future<Response> _proxy(
    Request request, {
    required String path,
    bool stream = false,
  }) async {
    try {
      final bodyBytes = await _readBodyBytes(request);
      requestLogger.info(
        'AgentKit proxy ${request.method} $path '
        'query=${request.url.queryParameters} '
        'headers=${_redactHeaders(request.headers)} '
        'bodyBytes=${bodyBytes?.length ?? 0} '
        'stream=$stream',
      );
      final response = await _client.send(
        method: request.method,
        path: path,
        queryParameters: request.url.queryParameters,
        headers: request.headers,
        body: bodyBytes,
        streamResponse: stream,
      );
      if (response.statusCode >= 500) {
        requestLogger.warning(
          'LiteAgent error ${response.statusCode} for $path '
          'body=${_previewBody(response.bodyBytes)}',
        );
      } else {
        requestLogger.info(
          'LiteAgent response ${response.statusCode} for $path',
        );
      }
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
      requestLogger.severe('Liteagent proxy error for $path: $error');
      return Response(502, body: 'Liteagent proxy error: $error');
    }
  }

  Future<List<int>?> _readBodyBytes(Request request) async {
    if (request.method == 'GET' || request.method == 'HEAD') {
      return null;
    }
    final bytes = await request.read().fold<List<int>>(
      <int>[],
      (buffer, data) {
        buffer.addAll(data);
        return buffer;
      },
    );
    return bytes.isEmpty ? null : bytes;
  }

  Map<String, String> _redactHeaders(Map<String, String> headers) {
    final redacted = <String, String>{};
    headers.forEach((name, value) {
      if (name.toLowerCase() == 'authorization') {
        redacted[name] = 'Bearer ***';
      } else {
        redacted[name] = value;
      }
    });
    return redacted;
  }

  String _previewBody(List<int>? bytes) {
    if (bytes == null || bytes.isEmpty) {
      return '';
    }
    final decoded = utf8.decode(bytes, allowMalformed: true);
    if (decoded.length <= 500) {
      return decoded;
    }
    return '${decoded.substring(0, 500)}...';
  }
}
