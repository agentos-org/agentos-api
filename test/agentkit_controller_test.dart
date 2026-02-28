import 'dart:async';
import 'dart:convert';

import 'package:agentos_api/src/controllers/agentkit/agentkit_controller.dart';
import 'package:agentos_kernel/agentos_kernel.dart';
import 'package:liteagent_sdk_dart/liteagent_sdk_dart.dart';
import 'package:opentool_dart/opentool_client.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

/// A minimal fake SDK that captures [initSimple] calls for verification.
class _FakeLiteAgentSDK extends LiteAgentSDK {
  _FakeLiteAgentSDK() : super(baseUrl: 'http://127.0.0.1:9527/api/v1');

  SimpleCapability? capturedSimpleCapability;

  @override
  Future<Session> initSimple(SimpleCapability simpleCapability) async {
    capturedSimpleCapability = simpleCapability;
    return Session(sessionId: 'test-session');
  }
}

class _FunctionCallLiteAgentSDK extends LiteAgentSDK {
  _FunctionCallLiteAgentSDK() : super(baseUrl: 'http://127.0.0.1:9527/api/v1');

  ToolReturn? forwardedCallback;
  UserTask? capturedUserTask;
  final Completer<ToolReturn> functionReturnCompleter = Completer<ToolReturn>();

  @override
  Future<void> chat(
    Session session,
    UserTask userTask,
    AgentMessageHandler agentMessageHandler,
  ) async {
    capturedUserTask = userTask;
    unawaited(() async {
      final toolReturn = await agentMessageHandler.onFunctionCall(
        session.sessionId,
        FunctionCall(
          id: 'fn-1',
          name: 'external_tool',
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
          sessionId: session.sessionId,
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
          sessionId: session.sessionId,
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

/// A minimal fake KernelService that provides a configurable LLMConfig.
class _FakeKernelService implements KernelService {
  _FakeKernelService({this.availableLlmConfig});

  final LLMConfig? availableLlmConfig;

  @override
  LLMConfig? getAvailableLlmConfig() => availableLlmConfig;

  // --- Unimplemented members (not needed for these tests) ---

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not mocked');
}

void main() {
  test(
    'injects llmConfig fallback for /initSimple when llmConfig is absent',
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
          body: jsonEncode(<String, dynamic>{'systemPrompt': 'hello'}),
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
    'forwards functionCall by SSE and resolves via /callback without sdk.callback forwarding',
    () async {
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
      await subscription.cancel();
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
    },
  );
}
