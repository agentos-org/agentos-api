import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:agentos_kernel/agentos_kernel.dart';
import 'package:liteagent_sdk_dart/liteagent_sdk_dart.dart';
import 'package:opentool_dart/opentool_client.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../../config.dart';
import '../../locator.dart';
import '../../middleware.dart';
import '../../services/agentkit/agent_request_context_service.dart';
import '../../services/agentkit/agentkit_service.dart';
import '../../services/appkit/appkit_service.dart';

class AgentKitController {
  AgentKitController({
    required LiteAgentSDK sdk,
    AppKitService? appKitService,
    Future<KernelService?>? kernelFuture,
    AgentOSServiceLocator? serviceLocator,
  }) : _sdk = sdk,
       _kernelFuture = kernelFuture ?? Future.value(null),
       _serviceLocator = serviceLocator ?? DefaultServiceLocator(),
       _agentKitService = AgentKitService(
         kernelFuture: kernelFuture ?? Future.value(null),
       ),
       _requestContextService = AgentRequestContextService(
         appKitService: appKitService,
       );

  final LiteAgentSDK _sdk;
  final Future<KernelService?> _kernelFuture;
  final AgentOSServiceLocator _serviceLocator;
  final AgentKitService _agentKitService;
  final AgentRequestContextService _requestContextService;
  static const Duration _defaultFunctionCallTimeout = Duration(minutes: 5);
  static const Duration _callbackTombstoneTtl = Duration(minutes: 10);
  static const int _maxCallbackTombstones = 2048;
  final Map<String, Duration> _functionCallTimeoutsBySession = {};
  final Map<String, Completer<ToolReturn>> _pendingToolReturns = {};
  final Map<String, Completer<EventToolReturn>> _pendingStreamToolReturns = {};
  final Map<String, _CallbackTombstone> _callbackTombstones = {};
  final Map<String, Set<String>> _streamFunctionNamesBySession = {};

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
    router.get('/history/summary', guard(_handleHistorySummary));
    router.get('/history/process', guard(_handleHistoryProcess));
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
        return Response(
          400,
          body: jsonEncode({'error': 'agentId is required'}),
        );
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
        return Response(
          400,
          body: jsonEncode({'error': 'agentId is required'}),
        );
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
        return Response(
          400,
          body: jsonEncode({'error': 'agentId is required'}),
        );
      }
      final result = await _sdk.deleteAgent(agentId);
      return _jsonResponse(result.toJson());
    } catch (e) {
      return _errorResponse(e, 'deleteAgent');
    }
  }

  // POST /initSession
  Future<Response> _handleInitSession(Request request) async {
    Capability? capability;
    Map<String, dynamic>? liteAgentBody;
    Map<String, dynamic>? agentCapabilityBody;
    var callbackTimeout = _defaultFunctionCallTimeout;
    try {
      final agentId = request.url.queryParameters['agentId'];
      if (agentId == null || agentId.isEmpty) {
        final body = await _readJsonBody(request);
        liteAgentBody = await _buildLiteAgentCapabilityFromAgentKitBody(body);
        _sanitizeCallbackTimeout(liteAgentBody);
        capability = Capability.fromJson(liteAgentBody);
        callbackTimeout = _callbackTimeoutFromCapability(capability);
      } else {
        try {
          final agent = await _sdk.getAgent(agentId);
          agentCapabilityBody = agent.capability.toJson();
          callbackTimeout = _callbackTimeoutFromCapability(agent.capability);
        } catch (e) {
          requestLogger.warning(
            'AgentKit could not read capability for agentId=$agentId; '
            'using gateway callback timeout default '
            '${_defaultFunctionCallTimeout.inSeconds}s. Error: $e',
          );
        }
      }
      final session = await _sdk.initSession(
        capability: capability,
        agentId: agentId,
      );
      _functionCallTimeoutsBySession[session.sessionId] = callbackTimeout;
      final finalCapabilityBody = liteAgentBody ?? agentCapabilityBody;
      if (finalCapabilityBody != null) {
        _rememberSessionStreamFunctions(session.sessionId, finalCapabilityBody);
      }
      return _jsonResponse(session.toJson());
    } catch (e) {
      return _errorResponse(e, 'initSession', llmConfig: capability?.llmConfig);
    }
  }

  // POST /initSimple
  Future<Response> _handleInitSimple(Request request) async {
    SimpleCapability? simpleCapability;
    try {
      final body = await _readJsonBody(request);
      final liteAgentBody = await _buildLiteAgentCapabilityFromAgentKitBody(
        body,
      );
      simpleCapability = SimpleCapability.fromJson(liteAgentBody);
      final session = await _sdk.initSimple(simpleCapability);
      return _jsonResponse(session.toJson());
    } catch (e) {
      return _errorResponse(
        e,
        'initSimple',
        llmConfig: simpleCapability?.llmConfig,
      );
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
      requestLogger.info('AgentKit /chat request: ${_encodeForLog(body)}');
      requestLogger.info(
        'AgentKit /chat raw userTask.llmConfig: ${_encodeForLog(body['llmConfig'])}',
      );
      await _resolveAgentKitLlmConfigForLiteAgent(
        body,
        injectFallbackWhenEmptyCore: false,
        logContext: 'chat',
      );
      final userTask = UserTask.fromJson(body);
      requestLogger.info(
        'AgentKit /chat final resolved llmConfig: ${_encodeForLog(userTask.llmConfig?.toJson())}',
      );
      final session = Session(sessionId: sessionId);

      final requestContext = _requestContextService.resolve(request);

      final lifecycle = _ChatRequestLifecycle(
        rootSessionId: sessionId,
        rootCallbackTimeout: _functionCallTimeoutForSession(sessionId),
        failPendingCallbacks: _failPendingCallbacksForSessions,
        onClientCancel: () => _stopCancelledChat(session),
      );

      final handler = _GatewayAgentMessageHandler(
        onMessage: (agentMessage) {
          final json = jsonEncode(agentMessage.toJson());
          final wasForwarded = lifecycle.addSse('message', json);
          if (!wasForwarded) return;
          if (requestContext != null) {
            unawaited(
              _agentKitService.archiveAgentMessage(
                sessionId: agentMessage.sessionId,
                username: requestContext.username,
                bundleId: requestContext.bundleId,
                agentMessage: agentMessage,
              ),
            );
          }
        },
        onChunk: (chunk) {
          final json = jsonEncode(chunk.toJson());
          lifecycle.addSse('chunk', json);
        },
        onFunctionCall: (callbackSessionId, functionCall) async {
          lifecycle.trackCallbackSession(callbackSessionId);
          final eventPayload = jsonEncode({
            'sessionId': callbackSessionId,
            'functionCall': functionCall.toJson(),
          });
          if (!lifecycle.addSse('functionCall', eventPayload)) {
            return _closedToolReturn(functionCall);
          }
          return _waitExternalToolReturn(
            callbackSessionId,
            functionCall,
            timeout: _functionCallTimeoutForChat(
              callbackSessionId,
              rootTimeout: lifecycle.rootCallbackTimeout,
            ),
          );
        },
        onStreamFunctionCall:
            (callSessionId, functionCall, onToolReturn) async {
              lifecycle.trackCallbackSession(callSessionId);
              final eventPayload = jsonEncode({
                'sessionId': callSessionId,
                'functionCall': functionCall.toJson(),
                'stream': true,
              });
              if (!lifecycle.addSse('functionCall', eventPayload)) {
                onToolReturn(_closedStreamToolReturn(functionCall));
                return;
              }
              final terminal = _waitExternalStreamToolReturn(
                callSessionId,
                functionCall,
                timeout: _functionCallTimeoutForChat(
                  callSessionId,
                  rootTimeout: lifecycle.rootCallbackTimeout,
                ),
              );
              onToolReturn(await terminal);
            },
        onDone: lifecycle.finish,
        onError: lifecycle.fail,
      );

      // Don't await — sdk.chat completes when SSE stream ends. Stream callback
      // specs still need the capability-aware raw adapter because LiteAgent's
      // functionCall payload does not identify stream functions. Both paths
      // coalesce duplicate root/child events and prefer the child session.
      if (_hasKnownStreamFunctions(sessionId)) {
        _chatWithRawSse(
          session: session,
          userTask: userTask,
          lifecycle: lifecycle,
          requestContext: requestContext,
        );
      } else {
        unawaited(() async {
          try {
            await _sdk.chat(session, userTask, handler);
          } catch (error, stackTrace) {
            lifecycle.fail(error, stackTrace);
          }
        }());
      }

      return Response.ok(
        lifecycle.stream,
        headers: {
          'content-type': 'text/event-stream',
          'cache-control': 'no-cache, no-store, no-transform',
          'connection': 'keep-alive',
          'x-accel-buffering': 'no',
        },
        context: const {'shelf.io.buffer_output': false},
      );
    } catch (e) {
      return _errorResponse(e, 'chat');
    }
  }

  void _chatWithRawSse({
    required Session session,
    required UserTask userTask,
    required _ChatRequestLifecycle lifecycle,
    required AgentRequestContext? requestContext,
  }) {
    unawaited(() async {
      try {
        final functionCalls = _GatewayFunctionCallEventCoalescer(
          rootSessionId: session.sessionId,
          parse: (rawData) => _parseRawSseFunctionCall(
            rawData,
            fallbackSessionId: session.sessionId,
          ),
          dispatch: (rawData) => _handleRawSseFunctionCall(
            session: session,
            rawData: rawData,
            lifecycle: lifecycle,
          ),
          onError: (error) async {
            lifecycle.fail(error);
          },
        );
        final stream = await _sdk.sseService.chat(session.sessionId, userTask);
        final subscription = stream
            .asyncMap((event) async {
              final data = event.data;
              if (data == null) return;
              final eventName = event.event ?? SSEEventType.MESSAGE;
              if (eventName == SSEEventType.MESSAGE) {
                final agentMessage = AgentMessage.fromJson(jsonDecode(data));
                final json = jsonEncode(agentMessage.toJson());
                final wasForwarded = lifecycle.addSse('message', json);
                if (!wasForwarded) return;
                if (requestContext != null) {
                  unawaited(
                    _agentKitService.archiveAgentMessage(
                      sessionId: agentMessage.sessionId,
                      username: requestContext.username,
                      bundleId: requestContext.bundleId,
                      agentMessage: agentMessage,
                    ),
                  );
                }
                return;
              }
              if (eventName == SSEEventType.CHUNK) {
                final chunk = AgentMessageChunk.fromJson(jsonDecode(data));
                final json = jsonEncode(chunk.toJson());
                lifecycle.addSse('chunk', json);
                return;
              }
              if (eventName == SSEEventType.FUNCTION_CALL) {
                functionCalls.add(data);
              }
            })
            .listen(
              (_) {},
              onDone: () async {
                functionCalls.beginClose();
                lifecycle.finish();
                await functionCalls.waitForInFlight();
              },
              onError: (Object e) async {
                functionCalls.beginClose();
                lifecycle.fail(e);
                await functionCalls.waitForInFlight();
              },
            );
        lifecycle.setUpstreamCancellation(subscription.cancel);
      } catch (e) {
        lifecycle.fail(e);
      }
    }());
  }

  Future<void> _handleRawSseFunctionCall({
    required Session session,
    required String rawData,
    required _ChatRequestLifecycle lifecycle,
  }) async {
    final parsed = _parseRawSseFunctionCall(
      rawData,
      fallbackSessionId: session.sessionId,
    );
    final isStream =
        _isKnownStreamFunction(parsed.callbackSessionId, parsed.functionCall) ||
        (parsed.callbackSessionId != session.sessionId &&
            _isKnownStreamFunction(session.sessionId, parsed.functionCall));
    final eventPayload = jsonEncode({
      'sessionId': parsed.callbackSessionId,
      'functionCall': parsed.functionCall.toJson(),
      if (isStream) 'stream': true,
    });
    lifecycle.trackCallbackSession(parsed.callbackSessionId);
    if (!lifecycle.addSse('functionCall', eventPayload)) {
      if (isStream) {
        await _sdk.streamCallback(
          Session(sessionId: parsed.callbackSessionId),
          _closedStreamToolReturn(parsed.functionCall),
        );
      } else {
        await _sdk.callback(
          Session(sessionId: parsed.callbackSessionId),
          _closedToolReturn(parsed.functionCall),
        );
      }
      return;
    }

    if (isStream) {
      final terminal = await _waitExternalStreamToolReturn(
        parsed.callbackSessionId,
        parsed.functionCall,
        timeout: _functionCallTimeoutForChat(
          parsed.callbackSessionId,
          rootTimeout: lifecycle.rootCallbackTimeout,
        ),
      );
      await _sdk.streamCallback(
        Session(sessionId: parsed.callbackSessionId),
        terminal,
      );
      return;
    }

    final toolReturn = await _waitExternalToolReturn(
      parsed.callbackSessionId,
      parsed.functionCall,
      timeout: _functionCallTimeoutForChat(
        parsed.callbackSessionId,
        rootTimeout: lifecycle.rootCallbackTimeout,
      ),
    );
    await _sdk.callback(
      Session(sessionId: parsed.callbackSessionId),
      toolReturn,
    );
  }

  _ParsedGatewayFunctionCall _parseRawSseFunctionCall(
    String rawData, {
    required String fallbackSessionId,
  }) {
    final payload = _decodeJsonMap(rawData);
    final functionCall = FunctionCall.fromJson(
      _extractFunctionCallJson(payload),
    );
    final rawSessionId = payload['sessionId'];
    final callbackSessionId = rawSessionId is String && rawSessionId.isNotEmpty
        ? rawSessionId
        : fallbackSessionId;
    return (callbackSessionId: callbackSessionId, functionCall: functionCall);
  }

  Map<String, dynamic> _decodeJsonMap(String data) {
    final decoded = jsonDecode(data);
    if (decoded is! Map) {
      throw const FormatException('SSE event payload must be a JSON object.');
    }
    return Map<String, dynamic>.from(decoded);
  }

  Map<String, dynamic> _extractFunctionCallJson(Map<String, dynamic> payload) {
    if (payload['functionCall'] is Map) {
      return Map<String, dynamic>.from(payload['functionCall'] as Map);
    }
    final agentMessage = AgentMessage.fromJson(payload);
    if (agentMessage.content is! Map) {
      throw const FormatException(
        'functionCall event payload missing function call content.',
      );
    }
    return Map<String, dynamic>.from(agentMessage.content as Map);
  }

  bool _hasKnownStreamFunctions(String sessionId) {
    return _streamFunctionNamesBySession[sessionId]?.isNotEmpty ?? false;
  }

  bool _isKnownStreamFunction(String sessionId, FunctionCall functionCall) {
    final names = _streamFunctionNamesBySession[sessionId];
    if (names == null || names.isEmpty) return false;
    return names.contains(functionCall.name);
  }

  void _rememberSessionStreamFunctions(
    String sessionId,
    Map<String, dynamic> capabilityBody,
  ) {
    final names = _extractStreamFunctionNames(capabilityBody);
    if (names.isEmpty) {
      _streamFunctionNamesBySession.remove(sessionId);
      return;
    }
    _streamFunctionNamesBySession[sessionId] = names;
  }

  void _sanitizeCallbackTimeout(Map<String, dynamic> capabilityBody) {
    final rawCallbackOpenTool = capabilityBody['callbackOpenTool'];
    if (rawCallbackOpenTool is! Map ||
        !rawCallbackOpenTool.containsKey('timeout')) {
      return;
    }
    final rawTimeout = rawCallbackOpenTool['timeout'];
    if (rawTimeout == null ||
        _validCallbackTimeoutSeconds(rawTimeout) != null) {
      return;
    }
    final callbackOpenTool = Map<String, dynamic>.from(rawCallbackOpenTool);
    callbackOpenTool.remove('timeout');
    capabilityBody['callbackOpenTool'] = callbackOpenTool;
    requestLogger.warning(
      'AgentKit ignored invalid callbackOpenTool.timeout; using gateway '
      'callback timeout default ${_defaultFunctionCallTimeout.inSeconds}s.',
    );
  }

  Duration _callbackTimeoutFromCapability(Capability capability) {
    final rawTimeout = capability.callbackOpenTool?.timeout;
    if (rawTimeout == null) return _defaultFunctionCallTimeout;
    final timeoutSeconds = _validCallbackTimeoutSeconds(rawTimeout);
    if (timeoutSeconds == null) {
      requestLogger.warning(
        'AgentKit ignored invalid callbackOpenTool.timeout from agent '
        'capability; using gateway callback timeout default '
        '${_defaultFunctionCallTimeout.inSeconds}s.',
      );
      return _defaultFunctionCallTimeout;
    }
    return Duration(seconds: timeoutSeconds);
  }

  int? _validCallbackTimeoutSeconds(Object? value) {
    // Duration stores microseconds in a signed 64-bit value on the Dart VM.
    const maxSafeSeconds = 9223372036854;
    if (value is! int || value <= 0 || value > maxSafeSeconds) return null;
    return value;
  }

  Duration _functionCallTimeoutForSession(String sessionId) {
    return _functionCallTimeoutsBySession[sessionId] ??
        _defaultFunctionCallTimeout;
  }

  Duration _functionCallTimeoutForChat(
    String callbackSessionId, {
    required Duration rootTimeout,
  }) {
    return _functionCallTimeoutsBySession[callbackSessionId] ?? rootTimeout;
  }

  Set<String> _extractStreamFunctionNames(Map<String, dynamic> capabilityBody) {
    final names = <String>{};
    final callbackOpenTool = capabilityBody['callbackOpenTool'];
    if (callbackOpenTool is Map) {
      final opentool = callbackOpenTool['opentool'];
      if (opentool is String && opentool.trim().isNotEmpty) {
        names.addAll(_extractStreamFunctionNamesFromOpenToolText(opentool));
      }
    }

    final openSpecList = capabilityBody['openSpecList'];
    if (openSpecList is List) {
      for (final item in openSpecList) {
        if (item is Map) {
          names.addAll(_extractStreamFunctionNamesFromOpenToolJson(item));
        }
      }
    }
    return names;
  }

  Set<String> _extractStreamFunctionNamesFromOpenToolText(String text) {
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map) {
        return _extractStreamFunctionNamesFromOpenToolJson(decoded);
      }
    } catch (_) {
      return const {};
    }
    return const {};
  }

  Set<String> _extractStreamFunctionNamesFromOpenToolJson(Map openTool) {
    final names = <String>{};
    final functions = openTool['functions'];
    if (functions is! List) return names;
    for (final function in functions) {
      if (function is! Map || function['stream'] == null) continue;
      final name = function['name'];
      if (name is String && name.trim().isNotEmpty) {
        names.add(name.trim());
      }
    }
    return names;
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
      requestLogger.info(
        'AgentKit /chat/simple request: ${_encodeForLog(body)}',
      );
      requestLogger.info(
        'AgentKit /chat/simple raw userTask.llmConfig: ${_encodeForLog(body['llmConfig'])}',
      );
      await _resolveAgentKitLlmConfigForLiteAgent(
        body,
        injectFallbackWhenEmptyCore: false,
        logContext: 'chat/simple',
      );
      final userTask = UserTask.fromJson(body);
      requestLogger.info(
        'AgentKit /chat/simple final resolved llmConfig: ${_encodeForLog(userTask.llmConfig?.toJson())}',
      );
      final session = Session(sessionId: sessionId);
      final message = await _sdk.chatSimple(session, userTask);

      final requestContext = _requestContextService.resolve(request);
      if (requestContext != null) {
        unawaited(
          _agentKitService.archiveAgentMessage(
            sessionId: sessionId,
            username: requestContext.username,
            bundleId: requestContext.bundleId,
            agentMessage: message,
          ),
        );
      }

      return _jsonResponse(message.toJson());
    } catch (e) {
      return _errorResponse(e, 'chatSimple');
    }
  }

  // GET /history?sessionId=xxx&page=1&pageSize=50
  Future<Response> _handleHistory(Request request) async {
    try {
      final sessionId = request.url.queryParameters['sessionId'];
      if (sessionId == null || sessionId.isEmpty) {
        return Response(
          400,
          body: jsonEncode({'error': 'sessionId is required'}),
        );
      }
      final rawPage = request.url.queryParameters['page'];
      final rawPageSize = request.url.queryParameters['pageSize'];
      if ((rawPage == null) != (rawPageSize == null)) {
        return Response(
          400,
          body: jsonEncode({
            'error': 'page and pageSize must be provided together',
          }),
        );
      }

      int? page;
      int? pageSize;
      if (rawPage != null && rawPageSize != null) {
        page = int.tryParse(rawPage);
        pageSize = int.tryParse(rawPageSize);
        if (page == null || page <= 0 || pageSize == null || pageSize <= 0) {
          return Response(
            400,
            body: jsonEncode({
              'error': 'page and pageSize must be positive integers',
            }),
          );
        }
      }

      final session = Session(sessionId: sessionId);
      final messages = await _sdk.getHistory(
        session,
        page: page,
        pageSize: pageSize,
      );
      return _jsonResponse(messages.map((m) => m.toJson()).toList());
    } catch (e) {
      return _errorResponse(e, 'history');
    }
  }

  // GET /history/summary?sessionId=xxx&page=1&pageSize=30
  Future<Response> _handleHistorySummary(Request request) async {
    try {
      final sessionId = request.url.queryParameters['sessionId'];
      if (sessionId == null || sessionId.isEmpty) {
        return Response(
          400,
          body: jsonEncode({'error': 'sessionId is required'}),
        );
      }
      final pagination = _parseHistoryPagination(request, defaultPageSize: 30);
      if (pagination == null) {
        return Response(
          400,
          body: jsonEncode({
            'error': 'page must be positive and pageSize must be 1-200',
          }),
        );
      }
      final summaries = await _sdk.getHistorySummary(
        sessionId,
        page: pagination.page,
        pageSize: pagination.pageSize,
      );
      return _jsonResponse(summaries.map((item) => item.toJson()).toList());
    } catch (e) {
      return _errorResponse(e, 'historySummary');
    }
  }

  // GET /history/process?sessionId=xxx&originalTaskId=xxx&page=1&pageSize=50
  Future<Response> _handleHistoryProcess(Request request) async {
    try {
      final sessionId = request.url.queryParameters['sessionId'];
      if (sessionId == null || sessionId.isEmpty) {
        return Response(
          400,
          body: jsonEncode({'error': 'sessionId is required'}),
        );
      }
      final originalTaskId = request.url.queryParameters['originalTaskId'];
      if (originalTaskId == null || originalTaskId.trim().isEmpty) {
        return Response(
          400,
          body: jsonEncode({'error': 'originalTaskId is required'}),
        );
      }
      final pagination = _parseHistoryPagination(request, defaultPageSize: 50);
      if (pagination == null) {
        return Response(
          400,
          body: jsonEncode({
            'error': 'page must be positive and pageSize must be 1-200',
          }),
        );
      }
      final messages = await _sdk.getHistoryProcess(
        sessionId,
        originalTaskId,
        page: pagination.page,
        pageSize: pagination.pageSize,
      );
      return _jsonResponse(
        messages.map((message) => message.toJson()).toList(),
      );
    } catch (e) {
      return _errorResponse(e, 'historyProcess');
    }
  }

  ({int page, int pageSize})? _parseHistoryPagination(
    Request request, {
    required int defaultPageSize,
  }) {
    final rawPage = request.url.queryParameters['page'];
    final rawPageSize = request.url.queryParameters['pageSize'];
    final page = rawPage == null ? 1 : int.tryParse(rawPage);
    final pageSize = rawPageSize == null
        ? defaultPageSize
        : int.tryParse(rawPageSize);
    if (page == null || page <= 0 || pageSize == null || pageSize <= 0) {
      return null;
    }
    if (pageSize > 200) return null;
    return (page: page, pageSize: pageSize);
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
      _streamFunctionNamesBySession.remove(sessionId);
      _functionCallTimeoutsBySession.remove(sessionId);
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
      final completedPending = _completePendingToolReturn(
        sessionId,
        toolReturn,
      );
      if (completedPending) {
        return _jsonResponse({'status': 'ok'});
      }
      final tombstone = _callbackTombstoneFor(
        _toolReturnKey(sessionId, toolReturn.id),
      );
      if (tombstone != null) {
        return _ignoredCallbackResponse(
          sessionId: sessionId,
          functionCallId: toolReturn.id,
          tombstone: tombstone,
          callbackType: 'callback',
        );
      }
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
      final completedPending = _completePendingStreamToolReturn(
        sessionId,
        streamToolReturn,
      );
      if (completedPending) {
        return _jsonResponse({'status': 'ok'});
      }
      final tombstone = _callbackTombstoneFor(
        _toolReturnKey(sessionId, streamToolReturn.toolReturn.id),
      );
      if (tombstone != null) {
        return _ignoredCallbackResponse(
          sessionId: sessionId,
          functionCallId: streamToolReturn.toolReturn.id,
          tombstone: tombstone,
          callbackType: 'streamCallback',
        );
      }
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
      // liteagent using `lite_oneapi`，real upstream provider is differentiated by `adapter`.
      // kernel build LLMConfig `provider=lite_oneapi` `adapter=model.provider`,
      'provider': 'lite_oneapi',
      'adapter': (config.adapter == null || config.adapter!.trim().isEmpty)
          ? 'openai'
          : config.adapter,
      'baseUrl': config.baseUrl,
      'apiKey': config.apiKey,
      'model': config.model,
      'temperature': config.temperature,
      'maxTokens': config.maxTokens,
      'contextWindowSize': config.contextWindowSize,
      'topP': config.topP,
      'supportsToolCall': config.supportsToolCall,
      'supportsReasoning': config.supportsReasoning,
    };
    result.removeWhere((_, value) => value == null);
    return result;
  }

  Future<Map<String, dynamic>> _buildLiteAgentCapabilityFromAgentKitBody(
    Map<String, dynamic> body,
  ) async {
    final capabilityBody = Map<String, dynamic>.from(body);
    await _resolveAgentKitLlmConfigForLiteAgent(
      capabilityBody,
      injectFallbackWhenMissing: true,
    );
    _normalizeSystemPromptForLiteAgent(capabilityBody);
    return capabilityBody;
  }

  Future<void> _resolveAgentKitLlmConfigForLiteAgent(
    Map<String, dynamic> body, {
    bool injectFallbackWhenMissing = false,
    bool injectFallbackWhenEmptyCore = true,
    String? logContext,
  }) async {
    final llmConfig = _readLlmConfig(body);
    final rawLlmConfig = llmConfig == null
        ? null
        : Map<String, dynamic>.from(llmConfig);
    if (llmConfig == null) {
      if (!injectFallbackWhenMissing) return;
      final fallbackLlmConfig = await _getAvailableLlmConfigJson();
      if (fallbackLlmConfig == null || fallbackLlmConfig.isEmpty) return;
      body['llmConfig'] = fallbackLlmConfig;
      _logLlmConfigResolution(
        context: logContext,
        source: 'server default (kernel available llmConfig)',
        raw: rawLlmConfig,
        merged: fallbackLlmConfig,
        resolved: fallbackLlmConfig,
      );
      return;
    }

    final nonNullConfig = <String, dynamic>{
      for (final entry in llmConfig.entries)
        if (entry.value != null) entry.key: entry.value,
    };

    final rawModelId = llmConfig['modelId'];
    final hasModelId = rawModelId is String && rawModelId.trim().isNotEmpty;
    final hasBaseUrl = nonNullConfig['baseUrl'] is String;
    final hasModel = nonNullConfig['model'] is String;
    final hasApiKey = nonNullConfig.containsKey('apiKey');
    final hasAnyDirectCore = hasBaseUrl || hasModel || hasApiKey;

    Map<String, dynamic>? resolvedCore;
    String? resolvedSource;
    if (hasModelId) {
      resolvedCore = await _resolveLlmConfigById(rawModelId.trim());
      if (resolvedCore == null) {
        requestLogger.warning(
          'AgentKit failed to resolve llmConfig modelId: ${rawModelId.trim()}',
        );
        _logLlmConfigResolution(
          context: logContext,
          source: 'unresolved userTask.llmConfig.modelId',
          raw: rawLlmConfig,
          merged: null,
          resolved: null,
        );
        body.remove('llmConfig');
        return;
      }
      resolvedSource = 'userTask.llmConfig.modelId';
    } else if (hasAnyDirectCore) {
      final baseUrl = nonNullConfig['baseUrl'];
      final model = nonNullConfig['model'];
      if (baseUrl is String &&
          baseUrl.trim().isNotEmpty &&
          model is String &&
          model.trim().isNotEmpty) {
        resolvedCore = <String, dynamic>{
          'baseUrl': baseUrl,
          'model': model,
          if (nonNullConfig.containsKey('apiKey'))
            'apiKey': nonNullConfig['apiKey'],
        };
        resolvedSource = 'userTask.llmConfig direct baseUrl/model';
      } else {
        _logLlmConfigResolution(
          context: logContext,
          source: 'invalid direct userTask.llmConfig',
          raw: rawLlmConfig,
          merged: null,
          resolved: null,
        );
        body.remove('llmConfig');
        return;
      }
    } else {
      if (!injectFallbackWhenEmptyCore) {
        _logLlmConfigResolution(
          context: logContext,
          source:
              'preserve session/agent default because userTask.llmConfig has no core fields',
          raw: rawLlmConfig,
          merged: null,
          resolved: null,
        );
        body.remove('llmConfig');
        return;
      }
      final fallbackLlmConfig = await _getAvailableLlmConfigJson();
      if (fallbackLlmConfig == null || fallbackLlmConfig.isEmpty) {
        _logLlmConfigResolution(
          context: logContext,
          source:
              'missing userTask.llmConfig core and no server default available',
          raw: rawLlmConfig,
          merged: null,
          resolved: null,
        );
        body.remove('llmConfig');
        return;
      }
      resolvedCore = <String, dynamic>{
        if (fallbackLlmConfig['baseUrl'] != null)
          'baseUrl': fallbackLlmConfig['baseUrl'],
        if (fallbackLlmConfig.containsKey('apiKey'))
          'apiKey': fallbackLlmConfig['apiKey'],
        if (fallbackLlmConfig['model'] != null)
          'model': fallbackLlmConfig['model'],
      };
      final baseUrl = resolvedCore['baseUrl'];
      final model = resolvedCore['model'];
      if (baseUrl is! String ||
          baseUrl.trim().isEmpty ||
          model is! String ||
          model.trim().isEmpty) {
        _logLlmConfigResolution(
          context: logContext,
          source: 'server default (kernel available llmConfig)',
          raw: rawLlmConfig,
          merged: null,
          resolved: null,
        );
        body.remove('llmConfig');
        return;
      }
      resolvedSource = 'server default (kernel available llmConfig)';
    }

    final extras = <String, dynamic>{
      for (final entry in nonNullConfig.entries)
        if (!_isCoreLlmField(entry.key)) entry.key: entry.value,
    };
    final merged = <String, dynamic>{...resolvedCore, ...extras};
    merged.removeWhere((_, value) => value == null);
    if (merged['baseUrl'] is! String || merged['model'] is! String) {
      _logLlmConfigResolution(
        context: logContext,
        source: resolvedSource,
        raw: rawLlmConfig,
        merged: merged,
        resolved: null,
      );
      body.remove('llmConfig');
      return;
    }
    body['llmConfig'] = merged;
    _logLlmConfigResolution(
      context: logContext,
      source: resolvedSource,
      raw: rawLlmConfig,
      merged: merged,
      resolved: Map<String, dynamic>.from(merged),
    );
  }

  bool _isCoreLlmField(String key) {
    return key == 'modelId' ||
        key == 'baseUrl' ||
        key == 'apiKey' ||
        key == 'model';
  }

  void _normalizeSystemPromptForLiteAgent(Map<String, dynamic> body) {
    final systemPrompt = body['systemPrompt'];
    if (systemPrompt is String) {
      body['systemPrompt'] = systemPrompt;
      return;
    }
    body['systemPrompt'] = '';
  }

  /// Injects llmConfig fallback into agent body
  /// (for /agent/create, /agent/update).
  ///
  /// Only injects when capability.llmConfig is not present.
  Future<void> _injectLlmConfigForAgentBody(Map<String, dynamic> body) async {
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

  Map<String, dynamic>? _readLlmConfig(Map<String, dynamic> body) {
    final llmConfig = body['llmConfig'];
    if (llmConfig is Map<String, dynamic>) {
      return llmConfig;
    }
    if (llmConfig is Map) {
      return Map<String, dynamic>.from(llmConfig);
    }
    return null;
  }

  void _logLlmConfigResolution({
    required String? context,
    required String? source,
    required Object? raw,
    required Object? merged,
    required Object? resolved,
  }) {
    final label = context == null
        ? 'AgentKit llmConfig resolution'
        : 'AgentKit $context llmConfig resolution';
    requestLogger.info(
      '$label: '
      'source=${source ?? 'none'}, '
      'raw=${_encodeForLog(raw)}, '
      'merged=${_encodeForLog(merged)}, '
      'resolved=${_encodeForLog(resolved)}',
    );
  }

  String _encodeForLog(Object? value) {
    return jsonEncode(_sanitizeForLog(value));
  }

  Object? _sanitizeForLog(Object? value) {
    if (value is Map) {
      return <String, dynamic>{
        for (final entry in value.entries)
          entry.key.toString(): entry.key.toString() == 'apiKey'
              ? _maskSecret(entry.value)
              : _sanitizeForLog(entry.value),
      };
    }
    if (value is Iterable) {
      return value.map(_sanitizeForLog).toList(growable: false);
    }
    return value;
  }

  Object? _maskSecret(Object? value) {
    if (value == null) return null;
    if (value is! String) return '***';
    if (value.trim().isEmpty) return value;
    if (value.length <= 4) return '***';
    return '${value.substring(0, 2)}***${value.substring(value.length - 2)}';
  }

  Future<Map<String, dynamic>?> _resolveLlmConfigById(String id) async {
    final models = await _serviceLocator.getLlmModelList();
    LlmModelInfo? matched;
    for (final model in models) {
      if (model.id == id) {
        matched = model;
        break;
      }
    }
    if (matched == null) {
      return null;
    }

    final baseUrl = await _resolveModelBaseUrl(matched);
    if (baseUrl == null || baseUrl.isEmpty) {
      return null;
    }

    final adapter = matched.provider.trim().isEmpty
        ? 'openai'
        : matched.provider;
    final result = <String, dynamic>{
      // liteagent using `lite_oneapi`，real upstream provider is differentiated by `adapter`.
      // kernel build LLMConfig `provider=lite_oneapi` `adapter=model.provider`,
      'provider': 'lite_oneapi',
      'adapter': adapter,
      'baseUrl': baseUrl,
      'apiKey': matched.apiKey ?? '',
      'model': matched.name,
      'contextWindowSize': matched.contextWindowSize,
    };
    result.removeWhere((_, value) => value == null);
    return result;
  }

  Future<String?> _resolveModelBaseUrl(LlmModelInfo model) async {
    if (model.isRemote) {
      return model.baseUrl;
    }
    final specificPort = await _serviceLocator.getServicePort(
      ApiConfig.serviceLlmChat,
      modelId: model.id,
    );
    final fallbackPort =
        specificPort ??
        await _serviceLocator.getServicePort(ApiConfig.serviceLlmChat);
    if (fallbackPort == null) {
      return null;
    }
    return ApiConfig.getInternalUrl(fallbackPort);
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

  Response _errorResponse(
    dynamic error,
    String operation, {
    LLMConfig? llmConfig,
  }) {
    requestLogger.severe('AgentKit $operation error: $error');
    final message = _buildErrorMessage(error, operation, llmConfig: llmConfig);
    return Response(
      502,
      body: jsonEncode({'error': message}),
      headers: {'content-type': 'application/json'},
    );
  }

  String _buildErrorMessage(
    dynamic error,
    String operation, {
    LLMConfig? llmConfig,
  }) {
    final message = error.toString();
    final baseUrl = llmConfig?.baseUrl.trim();
    final model = llmConfig?.model.trim();
    if (!_looksLikeConnectionRefused(error, message) ||
        baseUrl == null ||
        baseUrl.isEmpty) {
      return message;
    }

    final details = <String>[
      'Unable to connect to resolved LLM endpoint $baseUrl',
      if (model != null && model.isNotEmpty) 'for model $model',
      'during $operation',
    ].join(' ');
    return '$details. Original error: $message';
  }

  bool _looksLikeConnectionRefused(dynamic error, String message) {
    final normalized = message.toLowerCase();
    if (normalized.contains('connection refused')) {
      return true;
    }
    if (error is SocketException) {
      return error.message.toLowerCase().contains('connection refused');
    }
    return false;
  }

  Future<ToolReturn> _waitExternalToolReturn(
    String sessionId,
    FunctionCall functionCall, {
    required Duration timeout,
  }) {
    final key = _toolReturnKey(sessionId, functionCall.id);
    final completer = Completer<ToolReturn>();
    final existing = _pendingToolReturns.putIfAbsent(key, () => completer);
    if (!identical(existing, completer)) {
      return Future.value(
        ToolReturn(
          id: functionCall.id,
          result: _toolErrorResult(
            code: 'duplicate_function_call',
            message: 'A callback is already pending for this function call id.',
          ),
        ),
      );
    }
    _callbackTombstones.remove(key);

    Timer? timeoutTimer;
    timeoutTimer = Timer(timeout, () {
      if (!completer.isCompleted) {
        _rememberCallbackTombstone(key, _CallbackTerminalState.expired);
        completer.complete(
          ToolReturn(
            id: functionCall.id,
            result: _toolErrorResult(
              code: 'callback_timeout',
              message:
                  'External callback timed out after ${timeout.inSeconds}s.',
            ),
          ),
        );
      }
    });

    return completer.future.whenComplete(() {
      timeoutTimer?.cancel();
      if (identical(_pendingToolReturns[key], completer)) {
        _pendingToolReturns.remove(key);
      }
    });
  }

  ToolReturn _closedToolReturn(FunctionCall functionCall) {
    return ToolReturn(
      id: functionCall.id,
      result: _toolErrorResult(
        code: 'stream_closed',
        message: 'Chat stream closed before external callback.',
      ),
    );
  }

  EventToolReturn _closedStreamToolReturn(FunctionCall functionCall) {
    return EventToolReturn(
      eventType: EventType.ERROR,
      toolReturn: ToolReturn(
        id: functionCall.id,
        result: _toolErrorResult(
          code: 'stream_closed',
          message: 'Chat stream closed before external callback.',
        ),
      ),
    );
  }

  bool _completePendingToolReturn(String sessionId, ToolReturn toolReturn) {
    final key = _toolReturnKey(sessionId, toolReturn.id);
    final completer = _pendingToolReturns[key];
    if (completer == null || completer.isCompleted) {
      return false;
    }
    _rememberCallbackTombstone(key, _CallbackTerminalState.completed);
    completer.complete(toolReturn);
    return true;
  }

  Future<EventToolReturn> _waitExternalStreamToolReturn(
    String sessionId,
    FunctionCall functionCall, {
    required Duration timeout,
  }) {
    final key = _toolReturnKey(sessionId, functionCall.id);
    final completer = Completer<EventToolReturn>();
    final existing = _pendingStreamToolReturns.putIfAbsent(
      key,
      () => completer,
    );
    if (!identical(existing, completer)) {
      return Future.value(
        EventToolReturn(
          eventType: EventType.ERROR,
          toolReturn: ToolReturn(
            id: functionCall.id,
            result: _toolErrorResult(
              code: 'duplicate_stream_function_call',
              message:
                  'A streamCallback is already pending for this function '
                  'call id.',
            ),
          ),
        ),
      );
    }
    _callbackTombstones.remove(key);

    Timer? timeoutTimer;
    timeoutTimer = Timer(timeout, () {
      if (!completer.isCompleted) {
        _rememberCallbackTombstone(key, _CallbackTerminalState.expired);
        completer.complete(
          EventToolReturn(
            eventType: EventType.ERROR,
            toolReturn: ToolReturn(
              id: functionCall.id,
              result: _toolErrorResult(
                code: 'stream_callback_timeout',
                message:
                    'External streamCallback timed out after '
                    '${timeout.inSeconds}s.',
              ),
            ),
          ),
        );
      }
    });

    return completer.future.whenComplete(() {
      timeoutTimer?.cancel();
      if (identical(_pendingStreamToolReturns[key], completer)) {
        _pendingStreamToolReturns.remove(key);
      }
    });
  }

  bool _completePendingStreamToolReturn(
    String sessionId,
    EventToolReturn streamToolReturn,
  ) {
    if (!_isTerminalStreamEvent(streamToolReturn.eventType)) {
      return false;
    }
    final key = _toolReturnKey(sessionId, streamToolReturn.toolReturn.id);
    final completer = _pendingStreamToolReturns[key];
    if (completer == null || completer.isCompleted) {
      return false;
    }
    _rememberCallbackTombstone(key, _CallbackTerminalState.completed);
    completer.complete(streamToolReturn);
    return true;
  }

  void _failPendingToolReturnsForSession(
    String sessionId, {
    required String code,
    required String message,
  }) {
    final prefix = '$sessionId:';
    final targets = _pendingToolReturns.entries
        .where((entry) => entry.key.startsWith(prefix))
        .toList();
    for (final entry in targets) {
      final id = entry.key.substring(prefix.length);
      final completer = entry.value;
      if (!completer.isCompleted) {
        _rememberCallbackTombstone(entry.key, _CallbackTerminalState.completed);
        completer.complete(
          ToolReturn(
            id: id,
            result: _toolErrorResult(code: code, message: message),
          ),
        );
      }
    }
  }

  void _failPendingStreamToolReturnsForSession(
    String sessionId, {
    required String code,
    required String message,
  }) {
    final prefix = '$sessionId:';
    final targets = _pendingStreamToolReturns.entries
        .where((entry) => entry.key.startsWith(prefix))
        .toList();
    for (final entry in targets) {
      final id = entry.key.substring(prefix.length);
      final completer = entry.value;
      if (!completer.isCompleted) {
        _rememberCallbackTombstone(entry.key, _CallbackTerminalState.completed);
        completer.complete(
          EventToolReturn(
            eventType: EventType.ERROR,
            toolReturn: ToolReturn(
              id: id,
              result: _toolErrorResult(code: code, message: message),
            ),
          ),
        );
      }
    }
  }

  void _failPendingCallbacksForSessions(
    Set<String> sessionIds, {
    required String code,
    required String message,
  }) {
    for (final sessionId in sessionIds) {
      _failPendingToolReturnsForSession(
        sessionId,
        code: code,
        message: message,
      );
      _failPendingStreamToolReturnsForSession(
        sessionId,
        code: code,
        message: message,
      );
    }
  }

  Future<void> _stopCancelledChat(Session session) async {
    try {
      await _sdk.stop(session);
    } catch (error) {
      requestLogger.warning(
        'AgentKit could not stop cancelled chat for '
        'sessionId=${session.sessionId}: $error',
      );
    }
  }

  bool _isTerminalStreamEvent(String eventType) {
    final normalized = eventType.trim().toLowerCase();
    return normalized == EventType.DONE || normalized == EventType.ERROR;
  }

  String _toolReturnKey(String sessionId, String id) => '$sessionId:$id';

  void _rememberCallbackTombstone(String key, _CallbackTerminalState state) {
    final now = DateTime.now();
    _pruneCallbackTombstones(now);
    _callbackTombstones.remove(key);
    while (_callbackTombstones.length >= _maxCallbackTombstones) {
      _callbackTombstones.remove(_callbackTombstones.keys.first);
    }
    _callbackTombstones[key] = _CallbackTombstone(
      state: state,
      expiresAt: now.add(_callbackTombstoneTtl),
    );
  }

  _CallbackTombstone? _callbackTombstoneFor(String key) {
    _pruneCallbackTombstones(DateTime.now());
    return _callbackTombstones[key];
  }

  void _pruneCallbackTombstones(DateTime now) {
    final expiredKeys = _callbackTombstones.entries
        .where((entry) => !entry.value.expiresAt.isAfter(now))
        .map((entry) => entry.key)
        .toList(growable: false);
    for (final key in expiredKeys) {
      _callbackTombstones.remove(key);
    }
  }

  Response _ignoredCallbackResponse({
    required String sessionId,
    required String functionCallId,
    required _CallbackTombstone tombstone,
    required String callbackType,
  }) {
    final reason = tombstone.state == _CallbackTerminalState.expired
        ? 'callback_expired'
        : 'callback_completed';
    requestLogger.warning(
      'AgentKit ignored late $callbackType for sessionId=$sessionId, '
      'functionCallId=$functionCallId: $reason.',
    );
    return _jsonResponse({'status': 'ignored', 'reason': reason});
  }

  Map<String, dynamic> _toolErrorResult({
    required String code,
    required String message,
  }) {
    return {
      'error': {'code': code, 'message': message},
    };
  }
}

typedef _FailPendingCallbacks =
    void Function(
      Set<String> sessionIds, {
      required String code,
      required String message,
    });

class _ChatRequestLifecycle {
  _ChatRequestLifecycle({
    required String rootSessionId,
    required this.rootCallbackTimeout,
    required _FailPendingCallbacks failPendingCallbacks,
    required Future<void> Function() onClientCancel,
  }) : _callbackSessionIds = {rootSessionId},
       _failPendingCallbacks = failPendingCallbacks,
       _onClientCancel = onClientCancel {
    _controller = StreamController<List<int>>(onCancel: _handleClientCancel);
  }

  late final StreamController<List<int>> _controller;
  final Duration rootCallbackTimeout;
  final Set<String> _callbackSessionIds;
  final _FailPendingCallbacks _failPendingCallbacks;
  final Future<void> Function() _onClientCancel;
  Future<void> Function()? _cancelUpstream;
  bool _terminal = false;
  bool _clientCancelled = false;

  Stream<List<int>> get stream => _controller.stream;

  void trackCallbackSession(String sessionId) {
    if (sessionId.isNotEmpty) _callbackSessionIds.add(sessionId);
  }

  bool addSse(String event, String json) {
    if (_terminal) return false;
    try {
      _controller.add(utf8.encode('event:$event\ndata:$json\n\n'));
      return true;
    } catch (error, stackTrace) {
      fail(error, stackTrace);
      return false;
    }
  }

  void finish() {
    _terminate(
      code: 'stream_closed',
      message: 'Chat stream closed before external callback.',
    );
  }

  void fail(Object error, [StackTrace? stackTrace]) {
    if (_terminal) {
      requestLogger.warning(
        'AgentKit ignored an error after the chat stream was terminal: $error',
      );
      return;
    }
    _terminate(
      code: 'stream_error',
      message: error.toString(),
      error: error,
      stackTrace: stackTrace,
    );
  }

  void setUpstreamCancellation(Future<void> Function() cancelUpstream) {
    _cancelUpstream = cancelUpstream;
    if (_clientCancelled) _runAsync(cancelUpstream);
  }

  void _handleClientCancel() {
    if (_terminal) return;
    _clientCancelled = true;
    _terminate(
      code: 'stream_closed',
      message: 'Chat stream closed before external callback.',
    );
    final cancelUpstream = _cancelUpstream;
    if (cancelUpstream != null) _runAsync(cancelUpstream);
    _runAsync(_onClientCancel);
  }

  void _terminate({
    required String code,
    required String message,
    Object? error,
    StackTrace? stackTrace,
  }) {
    if (_terminal) return;
    _terminal = true;
    _failPendingCallbacks(
      Set<String>.unmodifiable(_callbackSessionIds),
      code: code,
      message: message,
    );
    if (error != null && !_clientCancelled) {
      _controller.addError(error, stackTrace);
    }
    unawaited(
      _controller.close().catchError((Object closeError) {
        requestLogger.warning(
          'AgentKit could not close a terminal chat stream: $closeError',
        );
      }),
    );
  }

  void _runAsync(Future<void> Function() operation) {
    unawaited(() async {
      try {
        await operation();
      } catch (error) {
        requestLogger.warning(
          'AgentKit chat cancellation cleanup failed: $error',
        );
      }
    }());
  }
}

enum _CallbackTerminalState { completed, expired }

class _CallbackTombstone {
  const _CallbackTombstone({required this.state, required this.expiresAt});

  final _CallbackTerminalState state;
  final DateTime expiresAt;
}

/// AgentMessageHandler for gateway SSE streaming
class _GatewayAgentMessageHandler extends AgentMessageHandler {
  final void Function(AgentMessage) _onMessage;
  final void Function(AgentMessageChunk) _onChunk;
  final Future<ToolReturn> Function(String, FunctionCall) _onFunctionCall;
  final Future<void> Function(
    String,
    FunctionCall,
    void Function(EventToolReturn),
  )
  _onStreamFunctionCall;
  final void Function() _onDone;
  final void Function(Exception) _onError;

  _GatewayAgentMessageHandler({
    required void Function(AgentMessage) onMessage,
    required void Function(AgentMessageChunk) onChunk,
    required Future<ToolReturn> Function(String, FunctionCall) onFunctionCall,
    required Future<void> Function(
      String,
      FunctionCall,
      void Function(EventToolReturn),
    )
    onStreamFunctionCall,
    required void Function() onDone,
    required void Function(Exception) onError,
  }) : _onMessage = onMessage,
       _onChunk = onChunk,
       _onFunctionCall = onFunctionCall,
       _onStreamFunctionCall = onStreamFunctionCall,
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
  Future<ToolReturn> onFunctionCall(
    String sessionId,
    FunctionCall functionCall,
  ) async {
    return _onFunctionCall(sessionId, functionCall);
  }

  @override
  Future<void> onStreamFunctionCall(
    String sessionId,
    FunctionCall functionCall,
    void Function(EventToolReturn) onToolReturn,
  ) async {
    await _onStreamFunctionCall(sessionId, functionCall, onToolReturn);
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

typedef _ParsedGatewayFunctionCall = ({
  String callbackSessionId,
  FunctionCall functionCall,
});

class _GatewayFunctionCallEventCoalescer {
  static const _coalesceWindow = Duration(milliseconds: 25);

  _GatewayFunctionCallEventCoalescer({
    required this.rootSessionId,
    required this.parse,
    required this.dispatch,
    required this.onError,
  });

  final String rootSessionId;
  final _ParsedGatewayFunctionCall Function(String rawData) parse;
  final Future<void> Function(String rawData) dispatch;
  final Future<void> Function(Object error) onError;
  final Map<String, _PendingGatewayFunctionCallEvent> _pending = {};
  final Set<String> _dispatchedCallIds = {};
  final Set<Future<void>> _inFlight = {};
  bool _closed = false;

  void add(String rawData) {
    if (_closed) return;
    final parsed = parse(rawData);
    final callId = parsed.functionCall.id;
    if (_dispatchedCallIds.contains(callId)) return;

    final existing = _pending[callId];
    if (existing != null) {
      final existingIsRoot = existing.callbackSessionId == rootSessionId;
      final incomingIsChild = parsed.callbackSessionId != rootSessionId;
      if (existingIsRoot && incomingIsChild) {
        existing
          ..rawData = rawData
          ..callbackSessionId = parsed.callbackSessionId;
      }
      return;
    }

    late final _PendingGatewayFunctionCallEvent pending;
    pending = _PendingGatewayFunctionCallEvent(
      rawData: rawData,
      callbackSessionId: parsed.callbackSessionId,
      timer: Timer(_coalesceWindow, () => _dispatch(callId)),
    );
    _pending[callId] = pending;
  }

  void _dispatch(String callId) {
    final pending = _pending.remove(callId);
    if (pending == null || !_dispatchedCallIds.add(callId)) return;
    pending.timer.cancel();

    late final Future<void> future;
    future = Future<void>.sync(() => dispatch(pending.rawData))
        .catchError((Object error) => onError(error))
        .whenComplete(() => _inFlight.remove(future));
    _inFlight.add(future);
  }

  void beginClose() {
    if (_closed) return;
    _closed = true;
    for (final callId in _pending.keys.toList(growable: false)) {
      _dispatch(callId);
    }
  }

  Future<void> waitForInFlight() async {
    if (_inFlight.isNotEmpty) {
      await Future.wait(_inFlight.toList(growable: false));
    }
  }

  Future<void> close() async {
    beginClose();
    await waitForInFlight();
  }
}

class _PendingGatewayFunctionCallEvent {
  _PendingGatewayFunctionCallEvent({
    required this.rawData,
    required this.callbackSessionId,
    required this.timer,
  });

  String rawData;
  String callbackSessionId;
  final Timer timer;
}
