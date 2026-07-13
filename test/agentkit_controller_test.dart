import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:agentos_api/src/controllers/agentkit/agentkit_controller.dart';
import 'package:agentos_api/src/config.dart';
import 'package:agentos_api/src/locator.dart';
import 'package:agentos_kernel/agentos_kernel.dart';
import 'package:liteagent_sdk_dart/liteagent_sdk_dart.dart';
import 'package:opentool_dart/opentool_client.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

/// A minimal fake SDK that captures [initSimple] calls for verification.
class _FakeLiteAgentSDK extends LiteAgentSDK {
  _FakeLiteAgentSDK() : super(baseUrl: 'http://127.0.0.1:9527/api/v1');

  SimpleCapability? capturedSimpleCapability;
  Capability? capturedCapability;
  Agent? capturedAgent;
  String? capturedUpdatedAgentId;
  String? capturedInitSessionAgentId;
  Session? capturedHistorySession;
  int? capturedHistoryPage;
  int? capturedHistoryPageSize;
  String? capturedHistorySummarySessionId;
  int? capturedHistorySummaryPage;
  int? capturedHistorySummaryPageSize;
  String? capturedHistoryProcessSessionId;
  String? capturedHistoryProcessOriginalTaskId;
  int? capturedHistoryProcessPage;
  int? capturedHistoryProcessPageSize;

  @override
  Future<Session> initSimple(SimpleCapability simpleCapability) async {
    capturedSimpleCapability = simpleCapability;
    return Session(sessionId: 'test-session');
  }

  @override
  Future<Session> initSession({Capability? capability, String? agentId}) async {
    capturedCapability = capability;
    capturedInitSessionAgentId = agentId;
    return Session(sessionId: 'test-session');
  }

  @override
  Future<AgentId> createAgent(Agent agent) async {
    capturedAgent = agent;
    return AgentId(agentId: 'agent-1');
  }

  @override
  Future<AgentId> updateAgent(String agentId, Agent agent) async {
    capturedUpdatedAgentId = agentId;
    capturedAgent = agent;
    return AgentId(agentId: agentId);
  }

  @override
  Future<List<AgentMessage>> getHistory(
    Session session, {
    int? page,
    int? pageSize,
  }) async {
    capturedHistorySession = session;
    capturedHistoryPage = page;
    capturedHistoryPageSize = pageSize;
    return [
      AgentMessage(
        sessionId: session.sessionId,
        originalTaskId: 'root-task',
        taskId: 'child-task',
        role: AgentRoleType.AGENT,
        to: AgentRoleType.USER,
        type: AgentMessageType.TEXT,
        content: 'done',
        createTime: DateTime.utc(2026, 7, 10),
      ),
    ];
  }

  @override
  Future<List<HistoryTurnSummaryDto>> getHistorySummary(
    String sessionId, {
    int page = 1,
    int pageSize = 30,
  }) async {
    capturedHistorySummarySessionId = sessionId;
    capturedHistorySummaryPage = page;
    capturedHistorySummaryPageSize = pageSize;
    return [
      HistoryTurnSummaryDto(
        originalTaskId: 'root-task',
        sessionId: sessionId,
        userMessage: null,
        finalMessage: null,
        status: HistoryTurnStatus.done,
        error: null,
        createdAt: DateTime.utc(2026, 7, 12, 10),
        completedAt: DateTime.utc(2026, 7, 12, 10, 0, 5),
        durationMs: 5000,
        usage: null,
        processMessageCount: 4,
      ),
    ];
  }

  @override
  Future<List<AgentMessage>> getHistoryProcess(
    String sessionId,
    String originalTaskId, {
    int page = 1,
    int pageSize = 50,
  }) async {
    capturedHistoryProcessSessionId = sessionId;
    capturedHistoryProcessOriginalTaskId = originalTaskId;
    capturedHistoryProcessPage = page;
    capturedHistoryProcessPageSize = pageSize;
    return [
      AgentMessage(
        sessionId: 'child-session',
        originalTaskId: originalTaskId,
        taskId: 'child-task',
        role: AgentRoleType.AGENT,
        to: AgentRoleType.CLIENT,
        type: AgentMessageType.REASONING,
        content: 'working',
        createTime: DateTime.utc(2026, 7, 12, 10, 0, 1),
      ),
    ];
  }
}

class _ThrowingLiteAgentSDK extends LiteAgentSDK {
  _ThrowingLiteAgentSDK() : super(baseUrl: 'http://127.0.0.1:9527/api/v1');

  @override
  Future<Session> initSession({Capability? capability, String? agentId}) async {
    throw const SocketException('Connection refused');
  }

  @override
  Future<Session> initSimple(SimpleCapability simpleCapability) async {
    throw const SocketException('Connection refused');
  }
}

class _FunctionCallLiteAgentSDK extends LiteAgentSDK {
  _FunctionCallLiteAgentSDK({
    this.callbackSessionId,
    this.functionName = 'external_tool',
    this.initSessionId = 'test-session',
    this.agent,
    this.failAgentLookup = false,
  }) : super(baseUrl: 'http://127.0.0.1:9527/api/v1');

  final String? callbackSessionId;
  final String functionName;
  final String initSessionId;
  final Agent? agent;
  final bool failAgentLookup;

  ToolReturn? forwardedCallback;
  UserTask? capturedUserTask;
  Capability? capturedCapability;
  int clearCalls = 0;
  final Completer<ToolReturn> functionReturnCompleter = Completer<ToolReturn>();

  @override
  Future<Agent> getAgent(String agentId) async {
    if (failAgentLookup) throw Exception('agent lookup unavailable');
    return agent ??
        Agent(
          name: 'test-agent',
          capability: Capability(systemPrompt: 'test'),
        );
  }

  @override
  Future<Session> initSession({Capability? capability, String? agentId}) async {
    capturedCapability = capability;
    return Session(sessionId: initSessionId);
  }

  @override
  Future<void> chat(
    Session session,
    UserTask userTask,
    AgentMessageHandler agentMessageHandler,
  ) async {
    capturedUserTask = userTask;
    unawaited(() async {
      final toolReturn = await agentMessageHandler.onFunctionCall(
        callbackSessionId ?? session.sessionId,
        FunctionCall(
          id: 'fn-1',
          name: functionName,
          arguments: {'query': 'hello'},
        ),
      );
      if (!functionReturnCompleter.isCompleted) {
        functionReturnCompleter.complete(toolReturn);
      }
      await agentMessageHandler.onDone();
    }());
  }

  @override
  Future<void> callback(Session session, ToolReturn toolReturn) async {
    forwardedCallback = toolReturn;
  }

  @override
  Future<void> clear(Session session) async {
    clearCalls++;
  }
}

class _StreamFunctionCallLiteAgentSDK extends LiteAgentSDK {
  _StreamFunctionCallLiteAgentSDK({this.callbackSessionId})
    : super(baseUrl: 'http://127.0.0.1:9527/api/v1');

  final String? callbackSessionId;

  EventToolReturn? terminalStreamReturn;
  final List<EventToolReturn> forwardedStreamCallbacks = [];
  final List<String> forwardedStreamCallbackSessionIds = [];
  final Completer<EventToolReturn> streamReturnCompleter =
      Completer<EventToolReturn>();

  @override
  Future<Session> initSession({Capability? capability, String? agentId}) async {
    return Session(sessionId: 'test-session');
  }

  @override
  Future<void> chat(
    Session session,
    UserTask userTask,
    AgentMessageHandler agentMessageHandler,
  ) async {
    unawaited(() async {
      await agentMessageHandler.onStreamFunctionCall(
        callbackSessionId ?? session.sessionId,
        FunctionCall(
          id: 'stream-fn-1',
          name: 'sequentiallyRead',
          arguments: const {},
        ),
        (eventToolReturn) {
          terminalStreamReturn = eventToolReturn;
          if (!streamReturnCompleter.isCompleted) {
            streamReturnCompleter.complete(eventToolReturn);
          }
        },
      );
      await agentMessageHandler.onDone();
    }());
  }

  @override
  Future<void> streamCallback(
    Session session,
    EventToolReturn streamToolReturn,
  ) async {
    forwardedStreamCallbackSessionIds.add(session.sessionId);
    forwardedStreamCallbacks.add(streamToolReturn);
  }
}

class _RawSseLiteAgentSDK extends LiteAgentSDK {
  _RawSseLiteAgentSDK(String baseUrl) : super(baseUrl: baseUrl);

  @override
  Future<Session> initSession({Capability? capability, String? agentId}) async {
    return Session(sessionId: 'root-session');
  }
}

class _ReasoningLiteAgentSDK extends LiteAgentSDK {
  _ReasoningLiteAgentSDK() : super(baseUrl: 'http://127.0.0.1:9527/api/v1');

  @override
  Future<void> chat(
    Session session,
    UserTask userTask,
    AgentMessageHandler agentMessageHandler,
  ) async {
    unawaited(() async {
      await agentMessageHandler.onMessage(
        session.sessionId,
        AgentMessage(
          sessionId: 'child-message-session',
          taskId: 'task-reasoning',
          role: AgentRoleType.LLM,
          to: AgentRoleType.CLIENT,
          type: AgentMessageType.REASONING,
          content: 'step-by-step reasoning',
          createTime: DateTime.now(),
        ),
      );
      await agentMessageHandler.onMessage(
        session.sessionId,
        AgentMessage(
          sessionId: session.sessionId,
          taskId: 'task-dispatch',
          role: AgentRoleType.AGENT,
          to: AgentRoleType.CLIENT,
          type: AgentMessageType.DISPATCH,
          content: <Map<String, dynamic>>[
            <String, dynamic>{'sessionId': 's-sub', 'taskId': 't-sub'},
          ],
          createTime: DateTime.now(),
        ),
      );
      await agentMessageHandler.onChunk(
        session.sessionId,
        AgentMessageChunk(
          sessionId: 'child-chunk-session',
          taskId: 'task-reasoning',
          role: AgentRoleType.LLM,
          to: AgentRoleType.CLIENT,
          type: AgentMessageType.REASONING,
          part: 'partial reasoning',
          createTime: DateTime.now(),
        ),
      );
      await agentMessageHandler.onChunk(
        session.sessionId,
        AgentMessageChunk(
          sessionId: session.sessionId,
          taskId: 'task-planning',
          role: AgentRoleType.AGENT,
          to: AgentRoleType.CLIENT,
          type: AgentMessageType.PLANNING,
          part: <String, dynamic>{
            'planId': 'p-1',
            'plans': <Map<String, dynamic>>[
              <String, dynamic>{'id': 'step-1', 'description': 'analyze'},
            ],
          },
          createTime: DateTime.now(),
        ),
      );
      await agentMessageHandler.onDone();
    }());
  }
}

class _FakeServiceLocator implements AgentOSServiceLocator {
  _FakeServiceLocator({
    this.models = const [],
    this.textPortByModelId = const {},
  });

  final List<LlmModelInfo> models;
  final Map<String, int> textPortByModelId;

  @override
  String get liteagentBaseUrl => 'http://127.0.0.1:9527/api/v1';

  @override
  Future<List<AppInfo>> getAppInfoList() async => const [];

  @override
  Future<List<LlmModelInfo>> getLlmModelList() async => models;

  @override
  Future<int?> getServicePort(String serviceKey, {String? modelId}) async {
    if (serviceKey != ApiConfig.serviceLlmChat) {
      return null;
    }
    if (modelId != null) {
      return textPortByModelId[modelId];
    }
    return 52010;
  }

  @override
  Stream<ServiceStatusEvent> get serviceStatusStream => const Stream.empty();
}

/// A minimal fake KernelService that provides a configurable LLMConfig.
class _FakeKernelService implements KernelService {
  _FakeKernelService({this.availableLlmConfig});

  final LLMConfig? availableLlmConfig;

  @override
  LLMConfig? getAvailableLlmConfig({String purpose = 'general'}) =>
      availableLlmConfig;

  // --- Unimplemented members (not needed for these tests) ---

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not mocked');
}

void main() {
  const plannerSkill = '''
---
name: planner
description: Plan before acting.
---

Always produce a short plan before tool use.
''';

  test('maps llmConfig.modelId to model for /initSession', () async {
    final fakeSdk = _FakeLiteAgentSDK();
    final controller = AgentKitController(
      sdk: fakeSdk,
      kernelFuture: Future.value(null),
      serviceLocator: _FakeServiceLocator(
        textPortByModelId: const {'qwen3-8b': 52010},
        models: const [
          LlmModelInfo(
            id: 'qwen3-8b',
            name: 'Qwen 3 8B',
            alias: 'qwen3-8b',
            description: 'text model',
            parameters: '8B',
            paramsB: 8,
            quantization: 'q4',
            sizeGB: 0,
            minRAMGB: 0,
            downloadUrl: '',
            tags: ['chat'],
            repoId: 'repo',
            type: 'textGeneration',
            contextWindowSize: 8192,
          ),
        ],
      ),
    );

    final response = await controller.router.call(
      Request(
        'POST',
        Uri.parse('http://localhost/initSession'),
        headers: <String, String>{
          'authorization': 'Bearer user-token',
          'content-type': 'application/json',
        },
        body: jsonEncode(<String, dynamic>{
          'systemPrompt': 'hello',
          'llmConfig': <String, dynamic>{'modelId': 'qwen3-8b'},
        }),
      ),
    );

    expect(response.statusCode, 200);
    expect(fakeSdk.capturedCapability, isNotNull);
    expect(fakeSdk.capturedCapability!.llmConfig?.model, 'Qwen 3 8B');
    expect(
      fakeSdk.capturedCapability!.llmConfig?.baseUrl,
      'http://127.0.0.1:52010',
    );
  });

  test(
    'injects kernel llmConfig for /initSession when request omits it',
    () async {
      final fakeSdk = _FakeLiteAgentSDK();
      final fakeKernel = _FakeKernelService(
        availableLlmConfig: LLMConfig(
          baseUrl: 'http://127.0.0.1:52010',
          apiKey: '',
          model: 'qwen',
        ),
      );
      final controller = AgentKitController(
        sdk: fakeSdk,
        kernelFuture: Future.value(fakeKernel),
      );

      final response = await controller.router.call(
        Request(
          'POST',
          Uri.parse('http://localhost/initSession'),
          headers: <String, String>{
            'authorization': 'Bearer user-token',
            'content-type': 'application/json',
          },
          body: jsonEncode(<String, dynamic>{'systemPrompt': 'hello'}),
        ),
      );

      expect(response.statusCode, 200);
      expect(fakeSdk.capturedCapability, isNotNull);
      expect(
        fakeSdk.capturedCapability!.llmConfig?.baseUrl,
        'http://127.0.0.1:52010',
      );
      expect(fakeSdk.capturedCapability!.llmConfig?.apiKey, '');
      expect(fakeSdk.capturedCapability!.llmConfig?.model, 'qwen');
    },
  );

  test('forwards skills for /initSession', () async {
    final fakeSdk = _FakeLiteAgentSDK();
    final controller = AgentKitController(
      sdk: fakeSdk,
      kernelFuture: Future.value(null),
    );

    final response = await controller.router.call(
      Request(
        'POST',
        Uri.parse('http://localhost/initSession'),
        headers: <String, String>{
          'authorization': 'Bearer user-token',
          'content-type': 'application/json',
        },
        body: jsonEncode(<String, dynamic>{
          'systemPrompt': 'hello',
          'skills': const [plannerSkill],
          'llmConfig': <String, dynamic>{
            'baseUrl': 'http://127.0.0.1:52010',
            'model': 'qwen3-8b',
          },
        }),
      ),
    );

    expect(response.statusCode, 200);
    expect(fakeSdk.capturedCapability, isNotNull);
    expect(fakeSdk.capturedCapability!.skills, const [plannerSkill]);
  });

  test('forwards history pagination and preserves originalTaskId', () async {
    final fakeSdk = _FakeLiteAgentSDK();
    final controller = AgentKitController(
      sdk: fakeSdk,
      kernelFuture: Future.value(null),
    );

    final response = await controller.router.call(
      Request(
        'GET',
        Uri.parse(
          'http://localhost/history?sessionId=session-1&page=2&pageSize=50',
        ),
        headers: const <String, String>{'authorization': 'Bearer user-token'},
      ),
    );

    expect(response.statusCode, 200);
    expect(fakeSdk.capturedHistorySession?.sessionId, 'session-1');
    expect(fakeSdk.capturedHistoryPage, 2);
    expect(fakeSdk.capturedHistoryPageSize, 50);
    final payload = jsonDecode(await response.readAsString()) as List<dynamic>;
    expect(payload.single['originalTaskId'], 'root-task');
    expect(payload.single['taskId'], 'child-task');
  });

  test('rejects incomplete or invalid history pagination', () async {
    final controller = AgentKitController(
      sdk: _FakeLiteAgentSDK(),
      kernelFuture: Future.value(null),
    );

    for (final query in <String>[
      'sessionId=session-1&page=1',
      'sessionId=session-1&page=0&pageSize=50',
      'sessionId=session-1&page=1&pageSize=invalid',
    ]) {
      final response = await controller.router.call(
        Request(
          'GET',
          Uri.parse('http://localhost/history?$query'),
          headers: const <String, String>{'authorization': 'Bearer user-token'},
        ),
      );

      expect(response.statusCode, 400, reason: query);
    }
  });

  test('forwards summary-first history with SDK defaults', () async {
    final fakeSdk = _FakeLiteAgentSDK();
    final controller = AgentKitController(
      sdk: fakeSdk,
      kernelFuture: Future.value(null),
    );

    final response = await controller.router.call(
      Request(
        'GET',
        Uri.parse('http://localhost/history/summary?sessionId=root-session'),
        headers: const <String, String>{'authorization': 'Bearer user-token'},
      ),
    );

    expect(response.statusCode, 200);
    expect(fakeSdk.capturedHistorySummarySessionId, 'root-session');
    expect(fakeSdk.capturedHistorySummaryPage, 1);
    expect(fakeSdk.capturedHistorySummaryPageSize, 30);
    final payload = jsonDecode(await response.readAsString()) as List<dynamic>;
    expect(payload.single['originalTaskId'], 'root-task');
    expect(payload.single['status'], HistoryTurnStatus.done);
    expect(payload.single['processMessageCount'], 4);
  });

  test('forwards lazy history process pagination and child messages', () async {
    final fakeSdk = _FakeLiteAgentSDK();
    final controller = AgentKitController(
      sdk: fakeSdk,
      kernelFuture: Future.value(null),
    );

    final response = await controller.router.call(
      Request(
        'GET',
        Uri.parse(
          'http://localhost/history/process?sessionId=root-session&'
          'originalTaskId=root-task&page=2&pageSize=25',
        ),
        headers: const <String, String>{'authorization': 'Bearer user-token'},
      ),
    );

    expect(response.statusCode, 200);
    expect(fakeSdk.capturedHistoryProcessSessionId, 'root-session');
    expect(fakeSdk.capturedHistoryProcessOriginalTaskId, 'root-task');
    expect(fakeSdk.capturedHistoryProcessPage, 2);
    expect(fakeSdk.capturedHistoryProcessPageSize, 25);
    final payload = jsonDecode(await response.readAsString()) as List<dynamic>;
    expect(payload.single['sessionId'], 'child-session');
    expect(payload.single['originalTaskId'], 'root-task');
    expect(payload.single['type'], AgentMessageType.REASONING);
  });

  test('validates summary and process history query parameters', () async {
    final controller = AgentKitController(
      sdk: _FakeLiteAgentSDK(),
      kernelFuture: Future.value(null),
    );

    for (final path in <String>[
      '/history/summary',
      '/history/summary?sessionId=root&page=0',
      '/history/summary?sessionId=root&pageSize=201',
      '/history/process?sessionId=root',
      '/history/process?sessionId=root&originalTaskId=task&page=invalid',
    ]) {
      final response = await controller.router.call(
        Request(
          'GET',
          Uri.parse('http://localhost$path'),
          headers: const <String, String>{'authorization': 'Bearer user-token'},
        ),
      );
      expect(response.statusCode, 400, reason: path);
    }
  });

  test('maps llmConfig.modelId to model for /initSimple', () async {
    final fakeSdk = _FakeLiteAgentSDK();
    final controller = AgentKitController(
      sdk: fakeSdk,
      kernelFuture: Future.value(null),
      serviceLocator: _FakeServiceLocator(
        textPortByModelId: const {'qwen3-8b': 52010},
        models: const [
          LlmModelInfo(
            id: 'qwen3-8b',
            name: 'Qwen 3 8B',
            alias: 'qwen3-8b',
            description: 'text model',
            parameters: '8B',
            paramsB: 8,
            quantization: 'q4',
            sizeGB: 0,
            minRAMGB: 0,
            downloadUrl: '',
            tags: ['chat'],
            repoId: 'repo',
            type: 'textGeneration',
            contextWindowSize: 8192,
          ),
        ],
      ),
    );

    final response = await controller.router.call(
      Request(
        'POST',
        Uri.parse('http://localhost/initSimple'),
        headers: <String, String>{
          'authorization': 'Bearer user-token',
          'content-type': 'application/json',
        },
        body: jsonEncode(<String, dynamic>{
          'systemPrompt': 'hello',
          'llmConfig': <String, dynamic>{'modelId': 'qwen3-8b'},
        }),
      ),
    );

    expect(response.statusCode, 200);
    expect(fakeSdk.capturedSimpleCapability, isNotNull);
    expect(fakeSdk.capturedSimpleCapability!.llmConfig?.model, 'Qwen 3 8B');
    expect(
      fakeSdk.capturedSimpleCapability!.llmConfig?.baseUrl,
      'http://127.0.0.1:52010',
    );
  });

  test('keeps provided llmConfig for /initSimple without overriding', () async {
    final fakeSdk = _FakeLiteAgentSDK();
    final fakeKernel = _FakeKernelService(
      availableLlmConfig: LLMConfig(
        baseUrl: 'http://127.0.0.1:52010',
        apiKey: '',
        model: 'fallback-model',
      ),
    );
    final controller = AgentKitController(
      sdk: fakeSdk,
      kernelFuture: Future.value(fakeKernel),
    );

    final response = await controller.router.call(
      Request(
        'POST',
        Uri.parse('http://localhost/initSimple'),
        headers: <String, String>{
          'authorization': 'Bearer user-token',
          'content-type': 'application/json',
        },
        body: jsonEncode(<String, dynamic>{
          'systemPrompt': 'hello',
          'llmConfig': <String, dynamic>{
            'baseUrl': 'http://127.0.0.1:60000',
            'apiKey': 'k',
            'model': 'explicit-model',
          },
        }),
      ),
    );

    expect(response.statusCode, 200);
    expect(
      fakeSdk.capturedSimpleCapability!.llmConfig?.baseUrl,
      'http://127.0.0.1:60000',
    );
    expect(
      fakeSdk.capturedSimpleCapability!.llmConfig?.model,
      'explicit-model',
    );
  });

  test('forwards skills for /initSimple', () async {
    final fakeSdk = _FakeLiteAgentSDK();
    final controller = AgentKitController(
      sdk: fakeSdk,
      kernelFuture: Future.value(null),
    );

    final response = await controller.router.call(
      Request(
        'POST',
        Uri.parse('http://localhost/initSimple'),
        headers: <String, String>{
          'authorization': 'Bearer user-token',
          'content-type': 'application/json',
        },
        body: jsonEncode(<String, dynamic>{
          'systemPrompt': 'hello',
          'skills': const [plannerSkill],
          'llmConfig': <String, dynamic>{
            'baseUrl': 'http://127.0.0.1:52010',
            'model': 'qwen3-8b',
          },
        }),
      ),
    );

    expect(response.statusCode, 200);
    expect(fakeSdk.capturedSimpleCapability, isNotNull);
    expect(fakeSdk.capturedSimpleCapability!.skills, const [plannerSkill]);
  });

  test('forwards skills for /agent/create', () async {
    final fakeSdk = _FakeLiteAgentSDK();
    final controller = AgentKitController(
      sdk: fakeSdk,
      kernelFuture: Future.value(null),
    );

    final response = await controller.router.call(
      Request(
        'POST',
        Uri.parse('http://localhost/agent/create'),
        headers: <String, String>{
          'authorization': 'Bearer user-token',
          'content-type': 'application/json',
        },
        body: jsonEncode(<String, dynamic>{
          'name': 'planner-agent',
          'capability': <String, dynamic>{
            'systemPrompt': 'hello',
            'skills': const [plannerSkill],
            'llmConfig': <String, dynamic>{
              'baseUrl': 'http://127.0.0.1:52010',
              'model': 'qwen3-8b',
            },
          },
        }),
      ),
    );

    expect(response.statusCode, 200);
    expect(fakeSdk.capturedAgent, isNotNull);
    expect(fakeSdk.capturedAgent!.capability.skills, const [plannerSkill]);
  });

  test('forwards skills for /agent/update', () async {
    final fakeSdk = _FakeLiteAgentSDK();
    final controller = AgentKitController(
      sdk: fakeSdk,
      kernelFuture: Future.value(null),
    );

    final response = await controller.router.call(
      Request(
        'POST',
        Uri.parse('http://localhost/agent/update?agentId=agent-1'),
        headers: <String, String>{
          'authorization': 'Bearer user-token',
          'content-type': 'application/json',
        },
        body: jsonEncode(<String, dynamic>{
          'name': 'planner-agent',
          'capability': <String, dynamic>{
            'systemPrompt': 'hello',
            'skills': const [plannerSkill],
            'llmConfig': <String, dynamic>{
              'baseUrl': 'http://127.0.0.1:52010',
              'model': 'qwen3-8b',
            },
          },
        }),
      ),
    );

    expect(response.statusCode, 200);
    expect(fakeSdk.capturedUpdatedAgentId, 'agent-1');
    expect(fakeSdk.capturedAgent, isNotNull);
    expect(fakeSdk.capturedAgent!.capability.skills, const [plannerSkill]);
  });

  test('fills empty systemPrompt when missing for /initSession', () async {
    final fakeSdk = _FakeLiteAgentSDK();
    final controller = AgentKitController(
      sdk: fakeSdk,
      kernelFuture: Future.value(null),
    );

    final response = await controller.router.call(
      Request(
        'POST',
        Uri.parse('http://localhost/initSession'),
        headers: <String, String>{
          'authorization': 'Bearer user-token',
          'content-type': 'application/json',
        },
        body: jsonEncode(<String, dynamic>{
          'llmConfig': <String, dynamic>{
            'baseUrl': 'http://127.0.0.1:52010',
            'model': 'qwen3-8b',
          },
        }),
      ),
    );

    expect(response.statusCode, 200);
    expect(fakeSdk.capturedCapability, isNotNull);
    expect(fakeSdk.capturedCapability!.systemPrompt, '');
  });

  test(
    'initSession surfaces resolved llm endpoint on connection refusal',
    () async {
      final controller = AgentKitController(
        sdk: _ThrowingLiteAgentSDK(),
        kernelFuture: Future.value(null),
      );

      final response = await controller.router.call(
        Request(
          'POST',
          Uri.parse('http://localhost/initSession'),
          headers: <String, String>{
            'authorization': 'Bearer user-token',
            'content-type': 'application/json',
          },
          body: jsonEncode(<String, dynamic>{
            'systemPrompt': 'hello',
            'llmConfig': <String, dynamic>{
              'baseUrl': 'http://127.0.0.1:52200',
              'model': 'qwen3.5-9b',
            },
          }),
        ),
      );

      expect(response.statusCode, 502);
      final payload =
          jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      final error = payload['error'] as String;
      expect(error, contains('http://127.0.0.1:52200'));
      expect(error, contains('qwen3.5-9b'));
      expect(error, contains('initSession'));
      expect(error, contains('Connection refused'));
    },
  );

  test(
    'initSimple surfaces resolved llm endpoint on connection refusal',
    () async {
      final controller = AgentKitController(
        sdk: _ThrowingLiteAgentSDK(),
        kernelFuture: Future.value(null),
      );

      final response = await controller.router.call(
        Request(
          'POST',
          Uri.parse('http://localhost/initSimple'),
          headers: <String, String>{
            'authorization': 'Bearer user-token',
            'content-type': 'application/json',
          },
          body: jsonEncode(<String, dynamic>{
            'systemPrompt': 'hello',
            'llmConfig': <String, dynamic>{
              'baseUrl': 'http://127.0.0.1:52200',
              'model': 'qwen3.5-9b',
            },
          }),
        ),
      );

      expect(response.statusCode, 502);
      final payload =
          jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      final error = payload['error'] as String;
      expect(error, contains('http://127.0.0.1:52200'));
      expect(error, contains('qwen3.5-9b'));
      expect(error, contains('initSimple'));
      expect(error, contains('Connection refused'));
    },
  );

  test(
    'avoids null cast for /initSession when llmConfig.modelId has null fields',
    () async {
      final fakeSdk = _FakeLiteAgentSDK();
      final controller = AgentKitController(
        sdk: fakeSdk,
        kernelFuture: Future.value(null),
        serviceLocator: _FakeServiceLocator(
          textPortByModelId: const {'qwen3-8b': 52010},
          models: const [
            LlmModelInfo(
              id: 'qwen3-8b',
              name: 'Qwen 3 8B',
              alias: 'qwen3-8b',
              description: 'text model',
              parameters: '8B',
              paramsB: 8,
              quantization: 'q4',
              sizeGB: 0,
              minRAMGB: 0,
              downloadUrl: '',
              tags: ['chat'],
              repoId: 'repo',
              type: 'textGeneration',
              contextWindowSize: 8192,
            ),
          ],
        ),
      );

      final response = await controller.router.call(
        Request(
          'POST',
          Uri.parse('http://localhost/initSession'),
          headers: <String, String>{
            'authorization': 'Bearer user-token',
            'content-type': 'application/json',
          },
          body: jsonEncode(<String, dynamic>{
            'systemPrompt': 'hello',
            'llmConfig': <String, dynamic>{
              'modelId': 'qwen3-8b',
              'apiKey': null,
            },
          }),
        ),
      );

      expect(response.statusCode, 200);
      expect(fakeSdk.capturedCapability, isNotNull);
      expect(fakeSdk.capturedCapability!.llmConfig?.apiKey, isNotNull);
      expect(
        fakeSdk.capturedCapability!.llmConfig?.baseUrl,
        'http://127.0.0.1:52010',
      );
    },
  );

  test(
    'uses supervision llmConfig when modelId and direct core are all null',
    () async {
      final fakeSdk = _FakeLiteAgentSDK();
      final fakeKernel = _FakeKernelService(
        availableLlmConfig: LLMConfig(
          baseUrl: 'http://127.0.0.1:52010',
          apiKey: '',
          model: 'qwen',
        ),
      );

      final controller = AgentKitController(
        sdk: fakeSdk,
        kernelFuture: Future.value(fakeKernel),
      );

      final response = await controller.router.call(
        Request(
          'POST',
          Uri.parse('http://localhost/initSimple'),
          headers: <String, String>{
            'authorization': 'Bearer user-token',
            'content-type': 'application/json',
          },
          body: jsonEncode(<String, dynamic>{
            'systemPrompt': 'hello',
            'llmConfig': <String, dynamic>{
              'modelId': null,
              'baseUrl': null,
              'apiKey': null,
              'model': null,
            },
          }),
        ),
      );

      expect(response.statusCode, 200);
      expect(fakeSdk.capturedSimpleCapability, isNotNull);
      expect(
        fakeSdk.capturedSimpleCapability!.llmConfig?.baseUrl,
        'http://127.0.0.1:52010',
      );
      expect(fakeSdk.capturedSimpleCapability!.llmConfig?.model, 'qwen');
    },
  );

  test('keeps provided null llmConfig.apiKey for /initSimple', () async {
    final fakeSdk = _FakeLiteAgentSDK();
    final controller = AgentKitController(
      sdk: fakeSdk,
      kernelFuture: Future.value(null),
    );

    final response = await controller.router.call(
      Request(
        'POST',
        Uri.parse('http://localhost/initSimple'),
        headers: <String, String>{
          'authorization': 'Bearer user-token',
          'content-type': 'application/json',
        },
        body: jsonEncode(<String, dynamic>{
          'systemPrompt': 'hello',
          'llmConfig': <String, dynamic>{
            'baseUrl': 'http://127.0.0.1:60000',
            'apiKey': null,
            'model': 'explicit-model',
          },
        }),
      ),
    );

    expect(response.statusCode, 200);
    expect(fakeSdk.capturedSimpleCapability, isNotNull);
    expect(fakeSdk.capturedSimpleCapability!.llmConfig?.apiKey, isNull);
  });

  test('resolves llmConfig by modelId for /initSimple', () async {
    final fakeSdk = _FakeLiteAgentSDK();
    final controller = AgentKitController(
      sdk: fakeSdk,
      kernelFuture: Future.value(null),
      serviceLocator: _FakeServiceLocator(
        textPortByModelId: const {'qwen3-8b': 52010},
        models: const [
          LlmModelInfo(
            id: 'qwen3-8b',
            name: 'Qwen 3 8B',
            alias: 'qwen3-8b',
            description: 'text model',
            parameters: '8B',
            paramsB: 8,
            quantization: 'q4',
            sizeGB: 0,
            minRAMGB: 0,
            downloadUrl: '',
            tags: ['chat'],
            repoId: 'repo',
            type: 'textGeneration',
            contextWindowSize: 8192,
          ),
        ],
      ),
    );

    final response = await controller.router.call(
      Request(
        'POST',
        Uri.parse('http://localhost/initSimple'),
        headers: <String, String>{
          'authorization': 'Bearer user-token',
          'content-type': 'application/json',
        },
        body: jsonEncode(<String, dynamic>{
          'systemPrompt': 'hello',
          'llmConfig': <String, dynamic>{'modelId': 'qwen3-8b'},
        }),
      ),
    );

    expect(response.statusCode, 200);
    expect(fakeSdk.capturedSimpleCapability, isNotNull);
    expect(
      fakeSdk.capturedSimpleCapability!.llmConfig?.baseUrl,
      'http://127.0.0.1:52010',
    );
    expect(fakeSdk.capturedSimpleCapability!.llmConfig?.model, 'Qwen 3 8B');
    expect(
      fakeSdk.capturedSimpleCapability!.llmConfig?.contextWindowSize,
      8192,
    );
  });

  test(
    'ignores null overrides when resolving llmConfig by modelId for /initSimple',
    () async {
      final fakeSdk = _FakeLiteAgentSDK();
      final controller = AgentKitController(
        sdk: fakeSdk,
        kernelFuture: Future.value(null),
        serviceLocator: _FakeServiceLocator(
          textPortByModelId: const {'qwen3-8b': 52010},
          models: const [
            LlmModelInfo(
              id: 'qwen3-8b',
              name: 'Qwen 3 8B',
              alias: 'qwen3-8b',
              description: 'text model',
              parameters: '8B',
              paramsB: 8,
              quantization: 'q4',
              sizeGB: 0,
              minRAMGB: 0,
              downloadUrl: '',
              tags: ['chat'],
              repoId: 'repo',
              type: 'textGeneration',
              contextWindowSize: 8192,
            ),
          ],
        ),
      );

      final response = await controller.router.call(
        Request(
          'POST',
          Uri.parse('http://localhost/initSimple'),
          headers: <String, String>{
            'authorization': 'Bearer user-token',
            'content-type': 'application/json',
          },
          body: jsonEncode(<String, dynamic>{
            'systemPrompt': 'hello',
            'llmConfig': <String, dynamic>{
              'modelId': 'qwen3-8b',
              'apiKey': null,
            },
          }),
        ),
      );

      expect(response.statusCode, 200);
      expect(fakeSdk.capturedSimpleCapability, isNotNull);
      expect(fakeSdk.capturedSimpleCapability!.llmConfig?.apiKey, isNotNull);
      expect(
        fakeSdk.capturedSimpleCapability!.llmConfig?.baseUrl,
        'http://127.0.0.1:52010',
      );
    },
  );

  test(
    'allows non-null extra field override when resolving llmConfig by modelId',
    () async {
      final fakeSdk = _FakeLiteAgentSDK();
      final controller = AgentKitController(
        sdk: fakeSdk,
        kernelFuture: Future.value(null),
        serviceLocator: _FakeServiceLocator(
          textPortByModelId: const {'qwen3-8b': 52010},
          models: const [
            LlmModelInfo(
              id: 'qwen3-8b',
              name: 'Qwen 3 8B',
              alias: 'qwen3-8b',
              description: 'text model',
              parameters: '8B',
              paramsB: 8,
              quantization: 'q4',
              sizeGB: 0,
              minRAMGB: 0,
              downloadUrl: '',
              tags: ['chat'],
              repoId: 'repo',
              type: 'textGeneration',
              contextWindowSize: 8192,
            ),
          ],
        ),
      );

      final response = await controller.router.call(
        Request(
          'POST',
          Uri.parse('http://localhost/initSimple'),
          headers: <String, String>{
            'authorization': 'Bearer user-token',
            'content-type': 'application/json',
          },
          body: jsonEncode(<String, dynamic>{
            'systemPrompt': 'hello',
            'llmConfig': <String, dynamic>{
              'modelId': 'qwen3-8b',
              'temperature': 0.66,
            },
          }),
        ),
      );

      expect(response.statusCode, 200);
      expect(fakeSdk.capturedSimpleCapability, isNotNull);
      expect(fakeSdk.capturedSimpleCapability!.llmConfig?.temperature, 0.66);
      expect(
        fakeSdk.capturedSimpleCapability!.llmConfig?.baseUrl,
        'http://127.0.0.1:52010',
      );
    },
  );

  test('drops llmConfig when modelId cannot be resolved', () async {
    final fakeSdk = _FakeLiteAgentSDK();
    final controller = AgentKitController(
      sdk: fakeSdk,
      kernelFuture: Future.value(null),
      serviceLocator: _FakeServiceLocator(
        textPortByModelId: const {'qwen3-8b': 52010},
        models: const [],
      ),
    );

    final response = await controller.router.call(
      Request(
        'POST',
        Uri.parse('http://localhost/initSimple'),
        headers: <String, String>{
          'authorization': 'Bearer user-token',
          'content-type': 'application/json',
        },
        body: jsonEncode(<String, dynamic>{
          'systemPrompt': 'hello',
          'llmConfig': <String, dynamic>{'modelId': 'unknown-model'},
        }),
      ),
    );

    expect(response.statusCode, 200);
    expect(fakeSdk.capturedSimpleCapability, isNotNull);
    expect(fakeSdk.capturedSimpleCapability!.llmConfig, isNull);
  });

  test('no injection when kernel is null', () async {
    final fakeSdk = _FakeLiteAgentSDK();

    final controller = AgentKitController(
      sdk: fakeSdk,
      kernelFuture: Future.value(null),
    );

    final response = await controller.router.call(
      Request(
        'POST',
        Uri.parse('http://localhost/initSimple'),
        headers: <String, String>{
          'authorization': 'Bearer user-token',
          'content-type': 'application/json',
        },
        body: jsonEncode(<String, dynamic>{
          'systemPrompt': 'hello',
          'llmConfig': <String, dynamic>{
            'baseUrl': 'http://localhost:1234',
            'apiKey': 'x',
            'model': 'my-model',
          },
        }),
      ),
    );

    expect(response.statusCode, 200);
    expect(
      fakeSdk.capturedSimpleCapability!.llmConfig?.baseUrl,
      'http://localhost:1234',
    );
    expect(fakeSdk.capturedSimpleCapability!.llmConfig?.model, 'my-model');
  });

  test(
    'routes multi-agent function callbacks by child session without role guessing',
    () async {
      const scenarios = [
        (
          callbackSessionId: 'project-planner-session',
          functionName: 'read_brief',
        ),
        (
          callbackSessionId: 'presentation-builder-session',
          functionName: 'read_presentation_html',
        ),
      ];

      for (final scenario in scenarios) {
        final fakeSdk = _FunctionCallLiteAgentSDK(
          callbackSessionId: scenario.callbackSessionId,
          functionName: scenario.functionName,
        );
        final controller = AgentKitController(
          sdk: fakeSdk,
          kernelFuture: Future.value(null),
        );

        final chatResponse = await controller.router.call(
          Request(
            'POST',
            Uri.parse('http://localhost/chat?sessionId=root-session'),
            headers: <String, String>{
              'authorization': 'Bearer user-token',
              'content-type': 'application/json',
            },
            body: jsonEncode(<String, dynamic>{
              'content': <Map<String, dynamic>>[
                <String, dynamic>{'type': 'text', 'message': 'hi'},
              ],
            }),
          ),
        );

        expect(chatResponse.statusCode, 200);
        final firstChunkCompleter = Completer<String>();
        late final StreamSubscription<List<int>> subscription;
        subscription = chatResponse.read().listen((bytes) {
          if (!firstChunkCompleter.isCompleted) {
            firstChunkCompleter.complete(utf8.decode(bytes));
          }
        });
        final sseChunk = await firstChunkCompleter.future.timeout(
          const Duration(seconds: 2),
        );
        expect(sseChunk, contains('event:functionCall'));
        expect(
          sseChunk,
          contains('"sessionId":"${scenario.callbackSessionId}"'),
        );
        expect(sseChunk, isNot(contains('"sessionId":"root-session"')));
        expect(sseChunk, contains('"name":"${scenario.functionName}"'));

        final callbackResponse = await controller.router.call(
          Request(
            'POST',
            Uri.parse(
              'http://localhost/callback?sessionId='
              '${scenario.callbackSessionId}',
            ),
            headers: <String, String>{
              'authorization': 'Bearer user-token',
              'content-type': 'application/json',
            },
            body: jsonEncode(<String, dynamic>{
              'id': 'fn-1',
              'result': <String, dynamic>{
                'handledBy': scenario.callbackSessionId,
              },
            }),
          ),
        );

        expect(callbackResponse.statusCode, 200);
        final resolved = await fakeSdk.functionReturnCompleter.future.timeout(
          const Duration(seconds: 2),
        );
        expect(resolved.result['handledBy'], scenario.callbackSessionId);
        expect(fakeSdk.forwardedCallback, isNull);
        await subscription.cancel();
      }
    },
  );

  test(
    'raw stream adapter coalesces duplicate root and child function calls',
    () async {
      final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final upstreamDone = upstream.listen((request) async {
        await request.drain<void>();
        if (request.uri.path != '/chat') {
          request.response.statusCode = HttpStatus.ok;
          await request.response.close();
          return;
        }
        request.response.headers.set(
          HttpHeaders.contentTypeHeader,
          'text/event-stream; charset=utf-8',
        );
        Map<String, dynamic> functionCallEvent(String sessionId) => {
          'sessionId': sessionId,
          'originalTaskId': 'root-task',
          'taskId': sessionId == 'root-session' ? 'root-task' : 'child-task',
          'role': AgentRoleType.AGENT,
          'to': AgentRoleType.CLIENT,
          'type': AgentMessageType.FUNCTION_CALL,
          'content': <String, dynamic>{
            'id': 'duplicate-call',
            'name': 'sequentiallyRead',
            'arguments': <String, dynamic>{},
          },
          'createTime': DateTime.utc(2026, 7, 12).toIso8601String(),
        };
        for (final sessionId in <String>['root-session', 'child-session']) {
          request.response.write(
            'event:functionCall\n'
            'data:${jsonEncode(functionCallEvent(sessionId))}\n\n',
          );
        }
        await request.response.close();
      });

      try {
        final controller = AgentKitController(
          sdk: _RawSseLiteAgentSDK(
            'http://${upstream.address.host}:${upstream.port}',
          ),
          kernelFuture: Future.value(null),
        );
        final initResponse = await controller.router.call(
          Request(
            'POST',
            Uri.parse('http://localhost/initSession'),
            headers: <String, String>{
              'authorization': 'Bearer user-token',
              'content-type': 'application/json',
            },
            body: jsonEncode(<String, dynamic>{
              'systemPrompt': 'Use the stream callback.',
              'callbackOpenTool': <String, dynamic>{
                'opentool': jsonEncode(<String, dynamic>{
                  'functions': <Map<String, dynamic>>[
                    <String, dynamic>{
                      'name': 'sequentiallyRead',
                      'stream': true,
                    },
                  ],
                }),
              },
            }),
          ),
        );
        expect(initResponse.statusCode, 200);

        final chatResponse = await controller.router.call(
          Request(
            'POST',
            Uri.parse('http://localhost/chat?sessionId=root-session'),
            headers: <String, String>{
              'authorization': 'Bearer user-token',
              'content-type': 'application/json',
            },
            body: jsonEncode(<String, dynamic>{
              'content': <Map<String, dynamic>>[
                <String, dynamic>{'type': 'text', 'message': 'read'},
              ],
            }),
          ),
        );

        final chunks = <String>[];
        final firstChunk = Completer<void>();
        final subscription = chatResponse.read().listen((bytes) {
          chunks.add(utf8.decode(bytes));
          if (!firstChunk.isCompleted) firstChunk.complete();
        });
        await firstChunk.future.timeout(const Duration(seconds: 2));
        await Future<void>.delayed(const Duration(milliseconds: 100));
        final sseText = chunks.join();
        expect(RegExp('event:functionCall').allMatches(sseText), hasLength(1));
        expect(sseText, contains('"sessionId":"child-session"'));
        expect(sseText, isNot(contains('"sessionId":"root-session"')));
        expect(sseText, contains('"stream":true'));
        await controller.router.call(
          Request(
            'POST',
            Uri.parse(
              'http://localhost/streamCallback?sessionId=child-session',
            ),
            headers: <String, String>{
              'authorization': 'Bearer user-token',
              'content-type': 'application/json',
            },
            body: jsonEncode(<String, dynamic>{
              'event': EventType.DONE,
              'toolReturn': <String, dynamic>{
                'id': 'duplicate-call',
                'result': <String, dynamic>{},
              },
            }),
          ),
        );
        await subscription.cancel();
      } finally {
        await upstream.close(force: true);
        await upstreamDone.cancel();
      }
    },
  );

  test(
    'forwards functionCall by SSE and resolves via /callback without sdk.callback forwarding',
    () async {
      final fakeSdk = _FunctionCallLiteAgentSDK();
      final fakeKernel = _FakeKernelService(
        availableLlmConfig: LLMConfig(
          baseUrl: 'http://127.0.0.1:52010',
          apiKey: '',
          model: 'qwen',
        ),
      );
      final controller = AgentKitController(
        sdk: fakeSdk,
        kernelFuture: Future.value(fakeKernel),
      );

      final chatResponse = await controller.router.call(
        Request(
          'POST',
          Uri.parse('http://localhost/chat?sessionId=s1'),
          headers: <String, String>{
            'authorization': 'Bearer user-token',
            'content-type': 'application/json',
          },
          body: jsonEncode(<String, dynamic>{
            'content': <Map<String, dynamic>>[
              <String, dynamic>{'type': 'text', 'message': 'hi'},
            ],
          }),
        ),
      );

      expect(chatResponse.statusCode, 200);
      final firstChunkCompleter = Completer<String>();
      late final StreamSubscription<List<int>> subscription;
      subscription = chatResponse.read().listen(
        (bytes) {
          if (!firstChunkCompleter.isCompleted) {
            firstChunkCompleter.complete(utf8.decode(bytes));
          }
        },
        onError: (Object e, StackTrace s) {
          if (!firstChunkCompleter.isCompleted) {
            firstChunkCompleter.completeError(e, s);
          }
        },
      );
      final sseChunk = await firstChunkCompleter.future.timeout(
        const Duration(seconds: 2),
      );
      expect(sseChunk, contains('event:functionCall'));
      expect(sseChunk, contains('"id":"fn-1"'));
      expect(sseChunk, contains('"name":"external_tool"'));

      final callbackResponse = await controller.router.call(
        Request(
          'POST',
          Uri.parse('http://localhost/callback?sessionId=s1'),
          headers: <String, String>{
            'authorization': 'Bearer user-token',
            'content-type': 'application/json',
          },
          body: jsonEncode(<String, dynamic>{
            'id': 'fn-1',
            'result': <String, dynamic>{'ok': true},
          }),
        ),
      );

      expect(callbackResponse.statusCode, 200);
      final resolved = await fakeSdk.functionReturnCompleter.future.timeout(
        const Duration(seconds: 2),
      );
      expect(resolved.id, 'fn-1');
      expect(resolved.result['ok'], true);
      expect(fakeSdk.forwardedCallback, isNull);

      final duplicateResponse = await controller.router.call(
        Request(
          'POST',
          Uri.parse('http://localhost/callback?sessionId=s1'),
          headers: <String, String>{
            'authorization': 'Bearer user-token',
            'content-type': 'application/json',
          },
          body: jsonEncode(<String, dynamic>{
            'id': 'fn-1',
            'result': <String, dynamic>{'ok': true},
          }),
        ),
      );
      expect(duplicateResponse.statusCode, 200);
      expect(
        jsonDecode(await duplicateResponse.readAsString()),
        <String, dynamic>{'status': 'ignored', 'reason': 'callback_completed'},
      );
      expect(fakeSdk.forwardedCallback, isNull);
      await subscription.cancel();
    },
  );

  test(
    'uses callbackOpenTool.timeout and ignores a late callback after timeout',
    () async {
      final fakeSdk = _FunctionCallLiteAgentSDK();
      final controller = AgentKitController(
        sdk: fakeSdk,
        kernelFuture: Future.value(null),
      );

      final initResponse = await controller.router.call(
        Request(
          'POST',
          Uri.parse('http://localhost/initSession'),
          headers: <String, String>{
            'authorization': 'Bearer user-token',
            'content-type': 'application/json',
          },
          body: jsonEncode(<String, dynamic>{
            'systemPrompt': 'hello',
            'callbackOpenTool': <String, dynamic>{
              'opentool': '{}',
              'timeout': 1,
            },
          }),
        ),
      );
      expect(initResponse.statusCode, 200);

      final chatResponse = await controller.router.call(
        Request(
          'POST',
          Uri.parse('http://localhost/chat?sessionId=test-session'),
          headers: <String, String>{
            'authorization': 'Bearer user-token',
            'content-type': 'application/json',
          },
          body: jsonEncode(<String, dynamic>{
            'content': <Map<String, dynamic>>[
              <String, dynamic>{'type': 'text', 'message': 'hi'},
            ],
          }),
        ),
      );
      final streamDone = chatResponse.read().toList();
      final timedOut = await fakeSdk.functionReturnCompleter.future.timeout(
        const Duration(seconds: 3),
      );
      expect(timedOut.result['error']['code'], 'callback_timeout');
      expect(timedOut.result['error']['message'], contains('1s'));
      await streamDone;

      final lateResponse = await controller.router.call(
        Request(
          'POST',
          Uri.parse('http://localhost/callback?sessionId=test-session'),
          headers: <String, String>{
            'authorization': 'Bearer user-token',
            'content-type': 'application/json',
          },
          body: jsonEncode(<String, dynamic>{
            'id': 'fn-1',
            'result': <String, dynamic>{'ok': true},
          }),
        ),
      );
      expect(lateResponse.statusCode, 200);
      expect(jsonDecode(await lateResponse.readAsString()), <String, dynamic>{
        'status': 'ignored',
        'reason': 'callback_expired',
      });
      expect(fakeSdk.forwardedCallback, isNull);
    },
  );

  test('uses the real child callback session timeout', () async {
    final fakeSdk = _FunctionCallLiteAgentSDK(
      callbackSessionId: 'child-session',
      initSessionId: 'child-session',
    );
    final controller = AgentKitController(
      sdk: fakeSdk,
      kernelFuture: Future.value(null),
    );

    final initResponse = await controller.router.call(
      Request(
        'POST',
        Uri.parse('http://localhost/initSession'),
        headers: <String, String>{
          'authorization': 'Bearer user-token',
          'content-type': 'application/json',
        },
        body: jsonEncode(<String, dynamic>{
          'systemPrompt': 'child',
          'callbackOpenTool': <String, dynamic>{'opentool': '{}', 'timeout': 1},
        }),
      ),
    );
    expect(initResponse.statusCode, 200);

    final chatResponse = await controller.router.call(
      Request(
        'POST',
        Uri.parse('http://localhost/chat?sessionId=root-session'),
        headers: <String, String>{
          'authorization': 'Bearer user-token',
          'content-type': 'application/json',
        },
        body: jsonEncode(<String, dynamic>{
          'content': <Map<String, dynamic>>[
            <String, dynamic>{'type': 'text', 'message': 'hi'},
          ],
        }),
      ),
    );
    final streamDone = chatResponse.read().toList();
    final timedOut = await fakeSdk.functionReturnCompleter.future.timeout(
      const Duration(seconds: 3),
    );
    expect(timedOut.result['error']['code'], 'callback_timeout');
    expect(timedOut.result['error']['message'], contains('1s'));
    await streamDone;
  });

  test(
    'reads callback timeout from agent capability when using agentId',
    () async {
      final fakeSdk = _FunctionCallLiteAgentSDK(
        agent: Agent(
          name: 'configured-agent',
          capability: Capability(
            systemPrompt: 'agent',
            callbackOpenTool: CallbackOpenTool(opentool: '{}', timeout: 1),
          ),
        ),
      );
      final controller = AgentKitController(
        sdk: fakeSdk,
        kernelFuture: Future.value(null),
      );

      final initResponse = await controller.router.call(
        Request(
          'POST',
          Uri.parse('http://localhost/initSession?agentId=agent-1'),
          headers: const <String, String>{'authorization': 'Bearer user-token'},
        ),
      );
      expect(initResponse.statusCode, 200);

      final chatResponse = await controller.router.call(
        Request(
          'POST',
          Uri.parse('http://localhost/chat?sessionId=test-session'),
          headers: <String, String>{
            'authorization': 'Bearer user-token',
            'content-type': 'application/json',
          },
          body: jsonEncode(<String, dynamic>{
            'content': <Map<String, dynamic>>[
              <String, dynamic>{'type': 'text', 'message': 'hi'},
            ],
          }),
        ),
      );
      final streamDone = chatResponse.read().toList();
      final timedOut = await fakeSdk.functionReturnCompleter.future.timeout(
        const Duration(seconds: 3),
      );
      expect(timedOut.result['error']['message'], contains('1s'));
      await streamDone;
    },
  );

  test('falls back when agent capability cannot be read', () async {
    final controller = AgentKitController(
      sdk: _FunctionCallLiteAgentSDK(failAgentLookup: true),
      kernelFuture: Future.value(null),
    );

    final response = await controller.router.call(
      Request(
        'POST',
        Uri.parse('http://localhost/initSession?agentId=agent-1'),
        headers: const <String, String>{'authorization': 'Bearer user-token'},
      ),
    );
    expect(response.statusCode, 200);
  });

  test('sanitizes invalid callbackOpenTool.timeout values', () async {
    for (final invalidTimeout in <Object>[0, -1, '600', 1.5]) {
      final fakeSdk = _FunctionCallLiteAgentSDK();
      final controller = AgentKitController(
        sdk: fakeSdk,
        kernelFuture: Future.value(null),
      );
      final response = await controller.router.call(
        Request(
          'POST',
          Uri.parse('http://localhost/initSession'),
          headers: <String, String>{
            'authorization': 'Bearer user-token',
            'content-type': 'application/json',
          },
          body: jsonEncode(<String, dynamic>{
            'systemPrompt': 'hello',
            'callbackOpenTool': <String, dynamic>{
              'opentool': '{}',
              'timeout': invalidTimeout,
            },
          }),
        ),
      );
      expect(response.statusCode, 200, reason: '$invalidTimeout');
      expect(
        fakeSdk.capturedCapability?.callbackOpenTool?.timeout,
        isNull,
        reason: '$invalidTimeout',
      );
    }
  });

  test('clear removes the configured session callback timeout', () async {
    final fakeSdk = _FunctionCallLiteAgentSDK();
    final controller = AgentKitController(
      sdk: fakeSdk,
      kernelFuture: Future.value(null),
    );
    final initResponse = await controller.router.call(
      Request(
        'POST',
        Uri.parse('http://localhost/initSession'),
        headers: <String, String>{
          'authorization': 'Bearer user-token',
          'content-type': 'application/json',
        },
        body: jsonEncode(<String, dynamic>{
          'systemPrompt': 'hello',
          'callbackOpenTool': <String, dynamic>{'opentool': '{}', 'timeout': 1},
        }),
      ),
    );
    expect(initResponse.statusCode, 200);
    final clearResponse = await controller.router.call(
      Request(
        'GET',
        Uri.parse('http://localhost/clear?sessionId=test-session'),
        headers: const <String, String>{'authorization': 'Bearer user-token'},
      ),
    );
    expect(clearResponse.statusCode, 200);
    expect(fakeSdk.clearCalls, 1);

    final chatResponse = await controller.router.call(
      Request(
        'POST',
        Uri.parse('http://localhost/chat?sessionId=test-session'),
        headers: <String, String>{
          'authorization': 'Bearer user-token',
          'content-type': 'application/json',
        },
        body: jsonEncode(<String, dynamic>{
          'content': <Map<String, dynamic>>[
            <String, dynamic>{'type': 'text', 'message': 'hi'},
          ],
        }),
      ),
    );
    final subscription = chatResponse.read().listen((_) {});
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    expect(fakeSdk.functionReturnCompleter.isCompleted, isFalse);

    final callbackResponse = await controller.router.call(
      Request(
        'POST',
        Uri.parse('http://localhost/callback?sessionId=test-session'),
        headers: <String, String>{
          'authorization': 'Bearer user-token',
          'content-type': 'application/json',
        },
        body: jsonEncode(<String, dynamic>{
          'id': 'fn-1',
          'result': <String, dynamic>{'ok': true},
        }),
      ),
    );
    expect(callbackResponse.statusCode, 200);
    final resolved = await fakeSdk.functionReturnCompleter.future.timeout(
      const Duration(seconds: 2),
    );
    expect(resolved.result['ok'], true);
    await subscription.cancel();
  });

  test(
    'keeps llmConfig unset for /chat when request omits llmConfig',
    () async {
      final fakeSdk = _FunctionCallLiteAgentSDK();
      final fakeKernel = _FakeKernelService(
        availableLlmConfig: LLMConfig(
          baseUrl: 'http://127.0.0.1:52010',
          apiKey: '',
          model: 'qwen',
        ),
      );
      final controller = AgentKitController(
        sdk: fakeSdk,
        kernelFuture: Future.value(fakeKernel),
      );

      final chatResponse = await controller.router.call(
        Request(
          'POST',
          Uri.parse('http://localhost/chat?sessionId=s1'),
          headers: <String, String>{
            'authorization': 'Bearer user-token',
            'content-type': 'application/json',
          },
          body: jsonEncode(<String, dynamic>{
            'content': <Map<String, dynamic>>[
              <String, dynamic>{'type': 'text', 'message': 'hi'},
            ],
            'isChunk': true,
          }),
        ),
      );

      expect(chatResponse.statusCode, 200);
      expect(fakeSdk.capturedUserTask, isNotNull);
      expect(fakeSdk.capturedUserTask!.llmConfig, isNull);
      final firstChunk = await chatResponse.read().first.timeout(
        const Duration(seconds: 2),
      );
      expect(utf8.decode(firstChunk), contains('event:functionCall'));
    },
  );

  test('keeps blank llmConfig.apiKey for /chat', () async {
    final fakeSdk = _FunctionCallLiteAgentSDK();
    final controller = AgentKitController(
      sdk: fakeSdk,
      kernelFuture: Future.value(null),
    );

    final chatResponse = await controller.router.call(
      Request(
        'POST',
        Uri.parse('http://localhost/chat?sessionId=s1'),
        headers: <String, String>{
          'authorization': 'Bearer user-token',
          'content-type': 'application/json',
        },
        body: jsonEncode(<String, dynamic>{
          'content': <Map<String, dynamic>>[
            <String, dynamic>{'type': 'text', 'message': 'hi'},
          ],
          'llmConfig': <String, dynamic>{
            'baseUrl': 'http://127.0.0.1:60000',
            'apiKey': '   ',
            'model': 'explicit-model',
          },
        }),
      ),
    );

    expect(chatResponse.statusCode, 200);
    expect(fakeSdk.capturedUserTask, isNotNull);
    expect(fakeSdk.capturedUserTask!.llmConfig?.apiKey, '   ');
    final firstChunk = await chatResponse.read().first.timeout(
      const Duration(seconds: 2),
    );
    expect(utf8.decode(firstChunk), contains('event:functionCall'));
  });

  test('resolves llmConfig by modelId for /chat', () async {
    final fakeSdk = _FunctionCallLiteAgentSDK();
    final controller = AgentKitController(
      sdk: fakeSdk,
      kernelFuture: Future.value(null),
      serviceLocator: _FakeServiceLocator(
        models: const [
          LlmModelInfo(
            id: 'remote-gpt',
            name: 'gpt-4.1',
            alias: 'gpt-4.1',
            description: 'remote model',
            parameters: 'remote',
            paramsB: 0,
            quantization: 'none',
            sizeGB: 0,
            minRAMGB: 0,
            downloadUrl: '',
            tags: ['chat'],
            repoId: 'remote',
            type: 'text',
            contextWindowSize: 128000,
            baseUrl: 'https://example.test/v1',
            apiKey: 'remote-key',
            isCustom: true,
          ),
        ],
      ),
    );

    final chatResponse = await controller.router.call(
      Request(
        'POST',
        Uri.parse('http://localhost/chat?sessionId=s1'),
        headers: <String, String>{
          'authorization': 'Bearer user-token',
          'content-type': 'application/json',
        },
        body: jsonEncode(<String, dynamic>{
          'content': <Map<String, dynamic>>[
            <String, dynamic>{'type': 'text', 'message': 'hi'},
          ],
          'llmConfig': <String, dynamic>{'modelId': 'remote-gpt'},
        }),
      ),
    );

    expect(chatResponse.statusCode, 200);
    expect(fakeSdk.capturedUserTask, isNotNull);
    expect(
      fakeSdk.capturedUserTask!.llmConfig?.baseUrl,
      'https://example.test/v1',
    );
    expect(fakeSdk.capturedUserTask!.llmConfig?.apiKey, 'remote-key');
    expect(fakeSdk.capturedUserTask!.llmConfig?.model, 'gpt-4.1');
    final firstChunk = await chatResponse.read().first.timeout(
      const Duration(seconds: 2),
    );
    expect(utf8.decode(firstChunk), contains('event:functionCall'));
  });

  test(
    'drops empty-core llmConfig for /chat instead of injecting fallback',
    () async {
      final fakeSdk = _FunctionCallLiteAgentSDK();
      final fakeKernel = _FakeKernelService(
        availableLlmConfig: LLMConfig(
          baseUrl: 'http://127.0.0.1:52010',
          apiKey: '',
          model: 'qwen',
        ),
      );
      final controller = AgentKitController(
        sdk: fakeSdk,
        kernelFuture: Future.value(fakeKernel),
      );

      final chatResponse = await controller.router.call(
        Request(
          'POST',
          Uri.parse('http://localhost/chat?sessionId=s1'),
          headers: <String, String>{
            'authorization': 'Bearer user-token',
            'content-type': 'application/json',
          },
          body: jsonEncode(<String, dynamic>{
            'content': <Map<String, dynamic>>[
              <String, dynamic>{'type': 'text', 'message': 'hi'},
            ],
            'llmConfig': <String, dynamic>{
              'modelId': null,
              'baseUrl': null,
              'apiKey': null,
              'model': null,
            },
          }),
        ),
      );

      expect(chatResponse.statusCode, 200);
      expect(fakeSdk.capturedUserTask, isNotNull);
      expect(fakeSdk.capturedUserTask!.llmConfig, isNull);
      final firstChunk = await chatResponse.read().first.timeout(
        const Duration(seconds: 2),
      );
      expect(utf8.decode(firstChunk), contains('event:functionCall'));
    },
  );

  test(
    'prefers modelId resolution over stale direct core fields for /chat',
    () async {
      final fakeSdk = _FunctionCallLiteAgentSDK();
      final controller = AgentKitController(
        sdk: fakeSdk,
        kernelFuture: Future.value(null),
        serviceLocator: _FakeServiceLocator(
          models: const [
            LlmModelInfo(
              id: 'remote-gpt',
              name: 'gpt-4.1',
              alias: 'gpt-4.1',
              description: 'remote model',
              parameters: 'remote',
              paramsB: 0,
              quantization: 'none',
              sizeGB: 0,
              minRAMGB: 0,
              downloadUrl: '',
              tags: ['chat'],
              repoId: 'remote',
              type: 'text',
              contextWindowSize: 128000,
              baseUrl: 'https://example.test/v1',
              apiKey: 'remote-key',
              isCustom: true,
            ),
          ],
        ),
      );

      final chatResponse = await controller.router.call(
        Request(
          'POST',
          Uri.parse('http://localhost/chat?sessionId=s1'),
          headers: <String, String>{
            'authorization': 'Bearer user-token',
            'content-type': 'application/json',
          },
          body: jsonEncode(<String, dynamic>{
            'content': <Map<String, dynamic>>[
              <String, dynamic>{'type': 'text', 'message': 'hi'},
            ],
            'llmConfig': <String, dynamic>{
              'modelId': 'remote-gpt',
              'baseUrl': 'http://localhost:52100',
              'apiKey': '',
              'model': 'Qwen3 8B Q8',
            },
          }),
        ),
      );

      expect(chatResponse.statusCode, 200);
      expect(fakeSdk.capturedUserTask, isNotNull);
      expect(
        fakeSdk.capturedUserTask!.llmConfig?.baseUrl,
        'https://example.test/v1',
      );
      expect(fakeSdk.capturedUserTask!.llmConfig?.model, 'gpt-4.1');
      expect(fakeSdk.capturedUserTask!.llmConfig?.apiKey, 'remote-key');
      final firstChunk = await chatResponse.read().first.timeout(
        const Duration(seconds: 2),
      );
      expect(utf8.decode(firstChunk), contains('event:functionCall'));
    },
  );

  test(
    'keeps legacy /callback forwarding when no pending functionCall exists',
    () async {
      final fakeSdk = _FunctionCallLiteAgentSDK();
      final controller = AgentKitController(
        sdk: fakeSdk,
        kernelFuture: Future.value(null),
      );

      final callbackResponse = await controller.router.call(
        Request(
          'POST',
          Uri.parse('http://localhost/callback?sessionId=s1'),
          headers: <String, String>{
            'authorization': 'Bearer user-token',
            'content-type': 'application/json',
          },
          body: jsonEncode(<String, dynamic>{
            'id': 'standalone-fn',
            'result': <String, dynamic>{'value': 1},
          }),
        ),
      );

      expect(callbackResponse.statusCode, 200);
      expect(fakeSdk.forwardedCallback, isNotNull);
      expect(fakeSdk.forwardedCallback!.id, 'standalone-fn');
      expect(fakeSdk.forwardedCallback!.result['value'], 1);
    },
  );

  test(
    'forwards stream functionCall by SSE and resolves terminal /streamCallback',
    () async {
      final fakeSdk = _StreamFunctionCallLiteAgentSDK();
      final controller = AgentKitController(
        sdk: fakeSdk,
        kernelFuture: Future.value(null),
      );

      final chatResponse = await controller.router.call(
        Request(
          'POST',
          Uri.parse('http://localhost/chat?sessionId=s1'),
          headers: <String, String>{
            'authorization': 'Bearer user-token',
            'content-type': 'application/json',
          },
          body: jsonEncode(<String, dynamic>{
            'content': <Map<String, dynamic>>[
              <String, dynamic>{'type': 'text', 'message': 'hi'},
            ],
          }),
        ),
      );

      expect(chatResponse.statusCode, 200);
      final firstChunkCompleter = Completer<String>();
      late final StreamSubscription<List<int>> subscription;
      subscription = chatResponse.read().listen(
        (bytes) {
          if (!firstChunkCompleter.isCompleted) {
            firstChunkCompleter.complete(utf8.decode(bytes));
          }
        },
        onError: (Object e, StackTrace s) {
          if (!firstChunkCompleter.isCompleted) {
            firstChunkCompleter.completeError(e, s);
          }
        },
      );
      final sseChunk = await firstChunkCompleter.future.timeout(
        const Duration(seconds: 2),
      );
      expect(sseChunk, contains('event:functionCall'));
      expect(sseChunk, contains('"id":"stream-fn-1"'));
      expect(sseChunk, contains('"name":"sequentiallyRead"'));
      expect(sseChunk, contains('"stream":true'));

      final dataResponse = await controller.router.call(
        Request(
          'POST',
          Uri.parse('http://localhost/streamCallback?sessionId=s1'),
          headers: <String, String>{
            'authorization': 'Bearer user-token',
            'content-type': 'application/json',
          },
          body: jsonEncode(<String, dynamic>{
            'event': EventType.DATA,
            'toolReturn': <String, dynamic>{
              'id': 'stream-fn-1',
              'result': <String, dynamic>{'data': 'Hello'},
            },
          }),
        ),
      );
      expect(dataResponse.statusCode, 200);
      expect(fakeSdk.forwardedStreamCallbacks, hasLength(1));
      expect(fakeSdk.forwardedStreamCallbacks.single.eventType, EventType.DATA);

      final doneResponse = await controller.router.call(
        Request(
          'POST',
          Uri.parse('http://localhost/streamCallback?sessionId=s1'),
          headers: <String, String>{
            'authorization': 'Bearer user-token',
            'content-type': 'application/json',
          },
          body: jsonEncode(<String, dynamic>{
            'event': EventType.DONE,
            'toolReturn': <String, dynamic>{
              'id': 'stream-fn-1',
              'result': <String, dynamic>{},
            },
          }),
        ),
      );
      expect(doneResponse.statusCode, 200);

      final terminal = await fakeSdk.streamReturnCompleter.future.timeout(
        const Duration(seconds: 2),
      );
      expect(terminal.eventType, EventType.DONE);
      expect(terminal.toolReturn.id, 'stream-fn-1');
      expect(fakeSdk.forwardedStreamCallbacks, hasLength(1));
      await subscription.cancel();
    },
  );

  test(
    'routes and cleans stream callbacks by child session for DONE and ERROR',
    () async {
      for (final terminalEvent in <String>[EventType.DONE, EventType.ERROR]) {
        final fakeSdk = _StreamFunctionCallLiteAgentSDK(
          callbackSessionId: 'child-session',
        );
        final controller = AgentKitController(
          sdk: fakeSdk,
          kernelFuture: Future.value(null),
        );

        final chatResponse = await controller.router.call(
          Request(
            'POST',
            Uri.parse('http://localhost/chat?sessionId=root-session'),
            headers: <String, String>{
              'authorization': 'Bearer user-token',
              'content-type': 'application/json',
            },
            body: jsonEncode(<String, dynamic>{
              'content': <Map<String, dynamic>>[
                <String, dynamic>{'type': 'text', 'message': 'hi'},
              ],
            }),
          ),
        );

        expect(chatResponse.statusCode, 200);
        final firstChunkCompleter = Completer<String>();
        late final StreamSubscription<List<int>> subscription;
        subscription = chatResponse.read().listen((bytes) {
          if (!firstChunkCompleter.isCompleted) {
            firstChunkCompleter.complete(utf8.decode(bytes));
          }
        });
        final sseChunk = await firstChunkCompleter.future.timeout(
          const Duration(seconds: 2),
        );
        expect(sseChunk, contains('event:functionCall'));
        expect(sseChunk, contains('"sessionId":"child-session"'));
        expect(sseChunk, isNot(contains('"sessionId":"root-session"')));
        expect(sseChunk, contains('"stream":true'));

        final dataResponse = await controller.router.call(
          Request(
            'POST',
            Uri.parse(
              'http://localhost/streamCallback?sessionId=child-session',
            ),
            headers: <String, String>{
              'authorization': 'Bearer user-token',
              'content-type': 'application/json',
            },
            body: jsonEncode(<String, dynamic>{
              'event': EventType.DATA,
              'toolReturn': <String, dynamic>{
                'id': 'stream-fn-1',
                'result': <String, dynamic>{'data': 'chunk'},
              },
            }),
          ),
        );
        expect(dataResponse.statusCode, 200);
        expect(fakeSdk.forwardedStreamCallbackSessionIds, ['child-session']);

        final terminalBody = <String, dynamic>{
          'event': terminalEvent,
          'toolReturn': <String, dynamic>{
            'id': 'stream-fn-1',
            'result': <String, dynamic>{},
          },
        };
        final terminalResponse = await controller.router.call(
          Request(
            'POST',
            Uri.parse(
              'http://localhost/streamCallback?sessionId=child-session',
            ),
            headers: <String, String>{
              'authorization': 'Bearer user-token',
              'content-type': 'application/json',
            },
            body: jsonEncode(terminalBody),
          ),
        );
        expect(terminalResponse.statusCode, 200);
        final terminal = await fakeSdk.streamReturnCompleter.future.timeout(
          const Duration(seconds: 2),
        );
        expect(terminal.eventType, terminalEvent);
        expect(fakeSdk.forwardedStreamCallbacks, hasLength(1));

        await Future<void>.delayed(Duration.zero);
        final afterCleanupResponse = await controller.router.call(
          Request(
            'POST',
            Uri.parse(
              'http://localhost/streamCallback?sessionId=child-session',
            ),
            headers: <String, String>{
              'authorization': 'Bearer user-token',
              'content-type': 'application/json',
            },
            body: jsonEncode(terminalBody),
          ),
        );
        expect(afterCleanupResponse.statusCode, 200);
        expect(
          jsonDecode(await afterCleanupResponse.readAsString()),
          <String, dynamic>{
            'status': 'ignored',
            'reason': 'callback_completed',
          },
        );
        expect(fakeSdk.forwardedStreamCallbacks, hasLength(1));
        expect(fakeSdk.forwardedStreamCallbackSessionIds, ['child-session']);
        await subscription.cancel();
      }
    },
  );

  test(
    'uses session timeout for stream callbacks and ignores late events',
    () async {
      final fakeSdk = _StreamFunctionCallLiteAgentSDK();
      final controller = AgentKitController(
        sdk: fakeSdk,
        kernelFuture: Future.value(null),
      );
      final initResponse = await controller.router.call(
        Request(
          'POST',
          Uri.parse('http://localhost/initSession'),
          headers: <String, String>{
            'authorization': 'Bearer user-token',
            'content-type': 'application/json',
          },
          body: jsonEncode(<String, dynamic>{
            'systemPrompt': 'hello',
            'callbackOpenTool': <String, dynamic>{
              'opentool': '{}',
              'timeout': 1,
            },
          }),
        ),
      );
      expect(initResponse.statusCode, 200);

      final chatResponse = await controller.router.call(
        Request(
          'POST',
          Uri.parse('http://localhost/chat?sessionId=test-session'),
          headers: <String, String>{
            'authorization': 'Bearer user-token',
            'content-type': 'application/json',
          },
          body: jsonEncode(<String, dynamic>{
            'content': <Map<String, dynamic>>[
              <String, dynamic>{'type': 'text', 'message': 'hi'},
            ],
          }),
        ),
      );
      final streamDone = chatResponse.read().toList();
      final terminal = await fakeSdk.streamReturnCompleter.future.timeout(
        const Duration(seconds: 3),
      );
      expect(terminal.eventType, EventType.ERROR);
      expect(
        terminal.toolReturn.result['error']['code'],
        'stream_callback_timeout',
      );
      expect(terminal.toolReturn.result['error']['message'], contains('1s'));
      await streamDone;

      for (final eventType in <String>[EventType.DATA, EventType.DONE]) {
        final lateResponse = await controller.router.call(
          Request(
            'POST',
            Uri.parse('http://localhost/streamCallback?sessionId=test-session'),
            headers: <String, String>{
              'authorization': 'Bearer user-token',
              'content-type': 'application/json',
            },
            body: jsonEncode(<String, dynamic>{
              'event': eventType,
              'toolReturn': <String, dynamic>{
                'id': 'stream-fn-1',
                'result': <String, dynamic>{'late': true},
              },
            }),
          ),
        );
        expect(lateResponse.statusCode, 200);
        expect(jsonDecode(await lateResponse.readAsString()), <String, dynamic>{
          'status': 'ignored',
          'reason': 'callback_expired',
        });
      }
      expect(fakeSdk.forwardedStreamCallbacks, isEmpty);
    },
  );

  test(
    'forwards reasoning/dispatch/planning message chunk types via SSE',
    () async {
      final fakeSdk = _ReasoningLiteAgentSDK();
      final controller = AgentKitController(
        sdk: fakeSdk,
        kernelFuture: Future.value(null),
      );

      final chatResponse = await controller.router.call(
        Request(
          'POST',
          Uri.parse('http://localhost/chat?sessionId=s-reasoning'),
          headers: <String, String>{
            'authorization': 'Bearer user-token',
            'content-type': 'application/json',
          },
          body: jsonEncode(<String, dynamic>{
            'content': <Map<String, dynamic>>[
              <String, dynamic>{'type': 'text', 'message': 'hi'},
            ],
          }),
        ),
      );

      expect(chatResponse.statusCode, 200);
      final sseText = await chatResponse
          .read()
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 2));
      expect(sseText, contains('event:message'));
      expect(sseText, contains('event:chunk'));
      expect(sseText, contains('"type":"reasoning"'));
      expect(sseText, contains('"type":"dispatch"'));
      expect(sseText, contains('"type":"planning"'));
      expect(sseText, contains('"sessionId":"child-message-session"'));
      expect(sseText, contains('"sessionId":"child-chunk-session"'));
    },
  );
}
