import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../../middleware.dart';
import '../../services/agentkit/liteagent_client.dart';
import '../../services/appkit/appkit_service.dart';

class AgentKitController {
  AgentKitController({LiteagentClient? client, AppKitService? appKitService})
    : _client = client ?? LiteagentClient(),
      _appKitService = appKitService;

  final LiteagentClient _client;
  final AppKitService? _appKitService;

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
      final forwardedBodyBytes = await _injectAvailableLlmConfigIfNeeded(
        request: request,
        path: path,
        bodyBytes: bodyBytes,
      );

      final token = bearerTokenFrom(request);
      final bundleId = (token != null && _appKitService != null)
          ? _appKitService.bundleIdForToken(token)
          : null;

      final response = await _client.send(
        method: request.method,
        path: path,
        queryParameters: request.url.queryParameters,
        headers: request.headers,
        body: forwardedBodyBytes,
        streamResponse: stream,
        userId: token,
        bundleId: bundleId,
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
    final bytes = await request.read().fold<List<int>>(<int>[], (buffer, data) {
      buffer.addAll(data);
      return buffer;
    });
    return bytes.isEmpty ? null : bytes;
  }

  Future<List<int>?> _injectAvailableLlmConfigIfNeeded({
    required Request request,
    required String path,
    required List<int>? bodyBytes,
  }) async {
    if (bodyBytes == null || bodyBytes.isEmpty) {
      return bodyBytes;
    }
    if (!_needsLlmConfigInjection(path)) {
      return bodyBytes;
    }
    if (path == '/initSession' &&
        request.url.queryParameters['agentId'] != null) {
      return bodyBytes;
    }

    Map<String, dynamic>? jsonBody;
    try {
      final decoded = jsonDecode(utf8.decode(bodyBytes, allowMalformed: true));
      if (decoded is Map<String, dynamic>) {
        jsonBody = decoded;
      } else if (decoded is Map) {
        jsonBody = Map<String, dynamic>.from(decoded);
      }
    } catch (_) {
      return bodyBytes;
    }
    if (jsonBody == null) {
      return bodyBytes;
    }

    final availableLlmConfig = await _client.getAvailableLlmConfigJson();
    if (availableLlmConfig == null || availableLlmConfig.isEmpty) {
      return bodyBytes;
    }

    final changed = _applyLlmConfigFallback(
      path: path,
      jsonBody: jsonBody,
      llmConfig: availableLlmConfig,
    );
    if (!changed) {
      return bodyBytes;
    }

    requestLogger.info('AgentKit injected llmConfig fallback for $path');
    return utf8.encode(jsonEncode(jsonBody));
  }

  bool _needsLlmConfigInjection(String path) {
    switch (path) {
      case '/chat':
      case '/chat/simple':
      case '/initSimple':
      case '/initSession':
      case '/agent/create':
      case '/agent/update':
        return true;
    }
    return false;
  }

  bool _applyLlmConfigFallback({
    required String path,
    required Map<String, dynamic> jsonBody,
    required Map<String, dynamic> llmConfig,
  }) {
    switch (path) {
      case '/chat':
      case '/chat/simple':
      case '/initSimple':
      case '/initSession':
        final current = jsonBody['llmConfig'];
        if (current != null) {
          return false;
        }
        jsonBody['llmConfig'] = llmConfig;
        return true;
      case '/agent/create':
      case '/agent/update':
        final capability = jsonBody['capability'];
        if (capability is Map<String, dynamic>) {
          if (capability['llmConfig'] != null) {
            return false;
          }
          capability['llmConfig'] = llmConfig;
          return true;
        }
        if (capability is Map) {
          final mapped = Map<String, dynamic>.from(capability);
          if (mapped['llmConfig'] != null) {
            return false;
          }
          mapped['llmConfig'] = llmConfig;
          jsonBody['capability'] = mapped;
          return true;
        }
        return false;
    }
    return false;
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
