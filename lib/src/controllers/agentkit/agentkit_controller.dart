import 'dart:async';
import 'dart:convert';

import 'package:agentos_kernel/agentos_kernel.dart';
import 'package:liteagent_sdk_dart/liteagent_sdk_dart.dart';
import 'package:opentool_dart/opentool_client.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../../middleware.dart';
import '../../services/appkit/appkit_service.dart';

class AgentKitController {
  AgentKitController({
    required LiteAgentSDK sdk,
    AppKitService? appKitService,
    Future<KernelService?>? kernelFuture,
  })  : _sdk = sdk,
        _appKitService = appKitService,
        _kernelFuture = kernelFuture ?? Future.value(null);

  final LiteAgentSDK _sdk;
  final AppKitService? _appKitService;
  final Future<KernelService?> _kernelFuture;

  Router get router {
    final router = Router();
    final guard = requireBearer();
    router.get('/version', guard(_handleVersion));
    router.get('/agent', guard(_handleGetAgent));
    router.post('/agent/create', guard(_handleCreateAgent));
    router.post('/agent/update', guard(_handleUpdateAgent));
    router.get('/agent/delete', guard(_handleDeleteAgent));
    router.post('/initSession', guard(_handleInitSession));
    router.post('/initSimple', guard(_handleInitSimple));
    router.post('/chat', guard(_handleChat));
    router.post('/chat/simple', guard(_handleChatSimple));
    router.get('/history', guard(_handleHistory));
    router.get('/stop', guard(_handleStop));
    router.get('/clear', guard(_handleClear));
    router.post('/callback', guard(_handleCallback));
    router.post('/streamCallback', guard(_handleStreamCallback));
    return router;
  }

  // GET /version
  Future<Response> _handleVersion(Request request) async {
    try {
      final version = await _sdk.getVersion();
      return _jsonResponse(version.toJson());
    } catch (e) {
      return _errorResponse(e, 'version');
    }
  }

  // GET /agent?agentId=xxx
  Future<Response> _handleGetAgent(Request request) async {
    try {
      final agentId = request.url.queryParameters['agentId'];
      if (agentId == null || agentId.isEmpty) {
        return Response(400, body: jsonEncode({'error': 'agentId is required'}));
      }
      final agent = await _sdk.getAgent(agentId);
      return _jsonResponse(agent.toJson());
    } catch (e) {
      return _errorResponse(e, 'getAgent');
    }
  }

  // POST /agent/create
  Future<Response> _handleCreateAgent(Request request) async {
    try {
      final body = await _readJsonBody(request);
      await _injectLlmConfigForAgentBody(body);
      final agent = Agent.fromJson(body);
      final result = await _sdk.createAgent(agent);
      return _jsonResponse(result.toJson());
    } catch (e) {
      return _errorResponse(e, 'createAgent');
    }
  }

  // POST /agent/update?agentId=xxx
  Future<Response> _handleUpdateAgent(Request request) async {
    try {
      final agentId = request.url.queryParameters['agentId'];
      if (agentId == null || agentId.isEmpty) {
        return Response(400, body: jsonEncode({'error': 'agentId is required'}));
      }
      final body = await _readJsonBody(request);
      await _injectLlmConfigForAgentBody(body);
      final agent = Agent.fromJson(body);
      final result = await _sdk.updateAgent(agentId, agent);
      return _jsonResponse(result.toJson());
    } catch (e) {
      return _errorResponse(e, 'updateAgent');
    }
  }

  // GET /agent/delete?agentId=xxx
  Future<Response> _handleDeleteAgent(Request request) async {
    try {
      final agentId = request.url.queryParameters['agentId'];
      if (agentId == null || agentId.isEmpty) {
        return Response(400, body: jsonEncode({'error': 'agentId is required'}));
      }
      final result = await _sdk.deleteAgent(agentId);
      return _jsonResponse(result.toJson());
    } catch (e) {
      return _errorResponse(e, 'deleteAgent');
    }
  }

  // POST /initSession
  Future<Response> _handleInitSession(Request request) async {
    try {
      final agentId = request.url.queryParameters['agentId'];
      Capability? capability;
      if (agentId == null || agentId.isEmpty) {
        final body = await _readJsonBody(request);
        await _injectLlmConfigForCapabilityBody(body);
        capability = Capability.fromJson(body);
      }
      final session = await _sdk.initSession(
        capability: capability,
        agentId: agentId,
      );
      return _jsonResponse(session.toJson());
    } catch (e) {
      return _errorResponse(e, 'initSession');
    }
  }

  // POST /initSimple
  Future<Response> _handleInitSimple(Request request) async {
    try {
      final body = await _readJsonBody(request);
      await _injectLlmConfigForCapabilityBody(body);
      final simpleCapability = SimpleCapability.fromJson(body);
      final session = await _sdk.initSimple(simpleCapability);
      return _jsonResponse(session.toJson());
    } catch (e) {
      return _errorResponse(e, 'initSimple');
    }
  }

  // POST /chat (SSE streaming)
  Future<Response> _handleChat(Request request) async {
    try {
      final sessionId = request.url.queryParameters['sessionId'];
      if (sessionId == null || sessionId.isEmpty) {
        return Response(
          400,
          body: jsonEncode({'error': 'sessionId is required'}),
        );
      }
      final body = await _readJsonBody(request);
      final userTask = UserTask.fromJson(body);
      final session = Session(sessionId: sessionId);

      final token = bearerTokenFrom(request);
      final bundleId = (token != null && _appKitService != null)
          ? _appKitService.bundleIdForToken(token)
          : null;

      final controller = StreamController<List<int>>();

      final handler = _GatewayAgentMessageHandler(
        onMessage: (agentMessage) {
          final json = jsonEncode(agentMessage.toJson());
          controller.add(utf8.encode('event:message\ndata:$json\n\n'));
          _recordAgentMessage(agentMessage, userId: token, bundleId: bundleId);
        },
        onChunk: (chunk) {
          final json = jsonEncode(chunk.toJson());
          controller.add(utf8.encode('event:chunk\ndata:$json\n\n'));
        },
        onDone: () {
          controller.close();
        },
        onError: (e) {
          controller.addError(e);
          controller.close();
        },
      );

      // Don't await — sdk.chat completes when SSE stream ends
      _sdk.chat(session, userTask, handler);

      return Response.ok(
        controller.stream,
        headers: {
          'content-type': 'text/event-stream',
          'cache-control': 'no-cache',
          'connection': 'keep-alive',
        },
        context: const {'shelf.io.buffer_output': false},
      );
    } catch (e) {
      return _errorResponse(e, 'chat');
    }
  }

  // POST /chat/simple
  Future<Response> _handleChatSimple(Request request) async {
    try {
      final sessionId = request.url.queryParameters['sessionId'];
      if (sessionId == null || sessionId.isEmpty) {
        return Response(
          400,
          body: jsonEncode({'error': 'sessionId is required'}),
        );
      }
      final body = await _readJsonBody(request);
      final userTask = UserTask.fromJson(body);
      final session = Session(sessionId: sessionId);
      final message = await _sdk.chatSimple(session, userTask);

      final token = bearerTokenFrom(request);
      final bundleId = (token != null && _appKitService != null)
          ? _appKitService.bundleIdForToken(token)
          : null;
      _recordAgentMessage(message, userId: token, bundleId: bundleId);

      return _jsonResponse(message.toJson());
    } catch (e) {
      return _errorResponse(e, 'chatSimple');
    }
  }

  // GET /history?sessionId=xxx
  Future<Response> _handleHistory(Request request) async {
    try {
      final sessionId = request.url.queryParameters['sessionId'];
      if (sessionId == null || sessionId.isEmpty) {
        return Response(
          400,
          body: jsonEncode({'error': 'sessionId is required'}),
        );
      }
      final session = Session(sessionId: sessionId);
      final messages = await _sdk.getHistory(session);
      return _jsonResponse(messages.map((m) => m.toJson()).toList());
    } catch (e) {
      return _errorResponse(e, 'history');
    }
  }

  // GET /stop?sessionId=xxx&taskId=xxx
  Future<Response> _handleStop(Request request) async {
    try {
      final sessionId = request.url.queryParameters['sessionId'];
      if (sessionId == null || sessionId.isEmpty) {
        return Response(
          400,
          body: jsonEncode({'error': 'sessionId is required'}),
        );
      }
      final taskId = request.url.queryParameters['taskId'];
      final session = Session(sessionId: sessionId);
      await _sdk.stop(session, taskId: taskId);
      return _jsonResponse({'status': 'ok'});
    } catch (e) {
      return _errorResponse(e, 'stop');
    }
  }

  // GET /clear?sessionId=xxx
  Future<Response> _handleClear(Request request) async {
    try {
      final sessionId = request.url.queryParameters['sessionId'];
      if (sessionId == null || sessionId.isEmpty) {
        return Response(
          400,
          body: jsonEncode({'error': 'sessionId is required'}),
        );
      }
      final session = Session(sessionId: sessionId);
      await _sdk.clear(session);
      return _jsonResponse({'status': 'ok'});
    } catch (e) {
      return _errorResponse(e, 'clear');
    }
  }

  // POST /callback?sessionId=xxx
  Future<Response> _handleCallback(Request request) async {
    try {
      final sessionId = request.url.queryParameters['sessionId'];
      if (sessionId == null || sessionId.isEmpty) {
        return Response(
          400,
          body: jsonEncode({'error': 'sessionId is required'}),
        );
      }
      final body = await _readJsonBody(request);
      final toolReturn = ToolReturn.fromJson(body);
      final session = Session(sessionId: sessionId);
      await _sdk.callback(session, toolReturn);
      return _jsonResponse({'status': 'ok'});
    } catch (e) {
      return _errorResponse(e, 'callback');
    }
  }

  // POST /streamCallback?sessionId=xxx
  Future<Response> _handleStreamCallback(Request request) async {
    try {
      final sessionId = request.url.queryParameters['sessionId'];
      if (sessionId == null || sessionId.isEmpty) {
        return Response(
          400,
          body: jsonEncode({'error': 'sessionId is required'}),
        );
      }
      final body = await _readJsonBody(request);
      final streamToolReturn = EventToolReturn.fromJson(body);
      final session = Session(sessionId: sessionId);
      await _sdk.streamCallback(session, streamToolReturn);
      return _jsonResponse({'status': 'ok'});
    } catch (e) {
      return _errorResponse(e, 'streamCallback');
    }
  }

  // --- LLM Config Injection ---

  /// Returns an available LLM config from kernel as LiteAgent-compatible JSON.
  ///
  /// Returns null when kernel is unavailable or no model is currently available.
  Future<Map<String, dynamic>?> _getAvailableLlmConfigJson() async {
    final kernel = await _kernelFuture;
    if (kernel == null) return null;

    final config = kernel.getAvailableLlmConfig();
    if (config == null) return null;

    final result = <String, dynamic>{
      'baseUrl': config.baseUrl,
      'apiKey': config.apiKey,
      'model': config.model,
      'temperature': config.temperature,
      'maxTokens': config.maxTokens,
      'contextWindowSize': config.contextWindowSize,
      'topP': config.topP,
      'supportsToolCalling': config.supportsToolCalling,
      'supportsDeepThinking': config.supportsDeepThinking,
    };
    result.removeWhere((_, value) => value == null);
    return result;
  }

  /// Injects llmConfig fallback into capability-level body
  /// (for /initSession, /initSimple, /chat, /chat/simple).
  ///
  /// Only injects when no llmConfig is present.
  Future<void> _injectLlmConfigForCapabilityBody(
    Map<String, dynamic> body,
  ) async {
    if (body['llmConfig'] != null) return;

    final llmConfig = await _getAvailableLlmConfigJson();
    if (llmConfig == null || llmConfig.isEmpty) return;

    body['llmConfig'] = llmConfig;
    requestLogger.info('AgentKit injected llmConfig fallback for capability');
  }

  /// Injects llmConfig fallback into agent body
  /// (for /agent/create, /agent/update).
  ///
  /// Only injects when capability.llmConfig is not present.
  Future<void> _injectLlmConfigForAgentBody(
    Map<String, dynamic> body,
  ) async {
    final capability = body['capability'];
    if (capability is Map<String, dynamic>) {
      if (capability['llmConfig'] != null) return;

      final llmConfig = await _getAvailableLlmConfigJson();
      if (llmConfig == null || llmConfig.isEmpty) return;

      capability['llmConfig'] = llmConfig;
      requestLogger.info('AgentKit injected llmConfig fallback for agent');
    } else if (capability is Map) {
      final mapped = Map<String, dynamic>.from(capability);
      if (mapped['llmConfig'] != null) return;

      final llmConfig = await _getAvailableLlmConfigJson();
      if (llmConfig == null || llmConfig.isEmpty) return;

      mapped['llmConfig'] = llmConfig;
      body['capability'] = mapped;
      requestLogger.info('AgentKit injected llmConfig fallback for agent');
    }
  }

  // --- Helpers ---

  Future<Map<String, dynamic>> _readJsonBody(Request request) async {
    final bodyStr = await request.readAsString();
    return jsonDecode(bodyStr) as Map<String, dynamic>;
  }

  Response _jsonResponse(dynamic data) {
    return Response.ok(
      jsonEncode(data),
      headers: {'content-type': 'application/json'},
    );
  }

  Response _errorResponse(dynamic error, String operation) {
    requestLogger.severe('AgentKit $operation error: $error');
    final message = error.toString();
    return Response(
      502,
      body: jsonEncode({'error': message}),
      headers: {'content-type': 'application/json'},
    );
  }

  void _recordAgentMessage(
    AgentMessage agentMessage, {
    String? userId,
    String? bundleId,
  }) {
    if (userId == null || bundleId == null) return;
    _kernelFuture.then((kernel) {
      if (kernel == null) return;
      kernel.recordAgentMessage(
        userId: userId,
        bundleId: bundleId,
        agentMessage: agentMessage,
      );
    }).catchError((_) {});
  }
}

/// AgentMessageHandler for gateway SSE streaming
class _GatewayAgentMessageHandler extends AgentMessageHandler {
  final void Function(AgentMessage) _onMessage;
  final void Function(AgentMessageChunk) _onChunk;
  final void Function() _onDone;
  final void Function(Exception) _onError;

  _GatewayAgentMessageHandler({
    required void Function(AgentMessage) onMessage,
    required void Function(AgentMessageChunk) onChunk,
    required void Function() onDone,
    required void Function(Exception) onError,
  })  : _onMessage = onMessage,
        _onChunk = onChunk,
        _onDone = onDone,
        _onError = onError;

  @override
  Future<void> onMessage(String sessionId, AgentMessage agentMessage) async {
    _onMessage(agentMessage);
  }

  @override
  Future<void> onChunk(
    String sessionId,
    AgentMessageChunk agentMessageChunk,
  ) async {
    _onChunk(agentMessageChunk);
  }

  @override
  Future<void> onDone() async {
    _onDone();
  }

  @override
  Future<void> onError(Exception e) async {
    _onError(e);
  }
}
