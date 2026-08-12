import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:agentos_api/agentos_api.dart';
import 'package:agentos_kernel/agentos_kernel.dart' show KernelService;
import 'package:http/http.dart';
import 'package:logging/logging.dart';
import 'package:liteagent_sdk_dart/liteagent_sdk_dart.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:test/test.dart';

class _FakeServiceLocator implements AgentOSServiceLocator {
  _FakeServiceLocator({
    required this.models,
    required this.runningModelIds,
    this.openToolPort = 19627,
  });

  final List<LlmModelInfo> models;
  final Set<String> runningModelIds;
  final int openToolPort;

  @override
  String get liteagentBaseUrl => 'http://127.0.0.1:9527/api/v1';

  @override
  Future<List<AppInfo>> getAppInfoList() async => const [];

  @override
  Future<List<LlmModelInfo>> getLlmModelList() async => models;

  @override
  Future<int?> getServicePort(String serviceKey, {String? modelId}) async {
    if (serviceKey == ApiConfig.serviceLlmChat && modelId != null) {
      return runningModelIds.contains(modelId) ? 52010 : null;
    }
    return switch (serviceKey) {
      ApiConfig.serviceLiteagent => 9527,
      ApiConfig.serviceOpentool => openToolPort,
      ApiConfig.serviceEmbeddings => 9537,
      ApiConfig.serviceLlmChat => 52010,
      ApiConfig.serviceLlmEmbedding => 52030,
      ApiConfig.serviceLlmTts => 52040,
      ApiConfig.serviceLlmAsr => 52050,
      _ => null,
    };
  }

  @override
  Stream<ServiceStatusEvent> get serviceStatusStream => const Stream.empty();
}

void main() {
  late HttpServer server;
  late String host;

  setUp(() async {
    // Use new Gateway API
    final serviceLocator = DefaultServiceLocator();
    // Create a Future that resolves to null (no kernel in tests)
    final kernelFuture = Future<KernelService?>.value(null);
    // Create SDK with dummy baseUrl (no real backend in tests)
    final liteAgentSdk = LiteAgentSDK(baseUrl: 'http://127.0.0.1:9527/api/v1');
    final handler = createGatewayHandler(
      serviceLocator: serviceLocator,
      kernelFuture: kernelFuture,
      liteAgentSdk: liteAgentSdk,
      enableLogging: false,
    );
    server = await shelf_io.serve(handler, InternetAddress.loopbackIPv4, 0);
    host = 'http://${server.address.host}:${server.port}';
  });

  tearDown(() => server.close(force: true));

  test('404', () async {
    final response = await get(Uri.parse('$host/foobar'));
    expect(response.statusCode, 404);
  });

  test('Root endpoint', () async {
    final response = await get(Uri.parse('$host/'));
    expect(response.statusCode, 200);
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    expect(payload['name'], 'AgentOS API Gateway');
    expect(payload['endpoints'], isNotEmpty);
    final endpoints = Map<String, dynamic>.from(payload['endpoints'] as Map);
    expect(endpoints.containsKey('/cronkit/*'), isTrue);
  });

  test('Root version', () async {
    final response = await get(Uri.parse('$host/version'));
    expect(response.statusCode, 200);
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    expect(payload['version'], _readPubspecVersion());
  });

  test('Ready endpoint without kernel', () async {
    final response = await get(Uri.parse('$host/ready'));
    expect(response.statusCode, 503);
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    expect(payload['ready'], isFalse);
    expect(payload['reasons'], isNotEmpty);
  });

  test('AgentKit create agent requires bearer', () async {
    final unauthorized = await post(
      Uri.parse('$host/agentkit/agent/create'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode(<String, dynamic>{'name': 'demo-agent'}),
    );
    expect(unauthorized.statusCode, 401);
  });

  test('AgentKit endpoints require bearer', () async {
    final initRes = await post(Uri.parse('$host/agentkit/initSession'));
    expect(initRes.statusCode, 401);

    final chatRes = await post(
      Uri.parse('$host/agentkit/chat'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode(<String, dynamic>{'content': []}),
    );
    expect(chatRes.statusCode, 401);
  });

  test('CronKit endpoints require bearer', () async {
    final response = await get(Uri.parse('$host/cronkit/task/list'));
    expect(response.statusCode, 401);
  });

  test('Toolkit endpoints require registered app bearer token', () async {
    final missingToken = await get(Uri.parse('$host/toolkit/list'));
    expect(missingToken.statusCode, 401);

    final invalidToken = await get(
      Uri.parse('$host/toolkit/list'),
      headers: {'authorization': 'Bearer sk-invalid'},
    );
    expect(invalidToken.statusCode, 401);

    final registerRes = await post(
      Uri.parse('$host/appkit/register'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode(<String, String>{'bundleId': 'com.demo.toolkit'}),
    );
    expect(registerRes.statusCode, 200);
    final registerPayload =
        jsonDecode(registerRes.body) as Map<String, dynamic>;
    final token = registerPayload['token'] as String;

    final authorized = await get(
      Uri.parse('$host/toolkit/list'),
      headers: {'authorization': 'Bearer $token'},
    );
    // The OpenTool service may be unavailable in tests, but auth should pass.
    expect(authorized.statusCode, isNot(401));
  });

  test(
    'Toolkit forwards public tool paths to internal OpenTool prefix',
    () async {
      final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      late HttpServer gateway;
      final requestedPaths = <String>[];

      upstream.listen((request) async {
        requestedPaths.add(request.uri.path);
        request.response.statusCode = 200;
        request.response.headers.set(
          HttpHeaders.contentTypeHeader,
          'application/json',
        );
        if (request.uri.path == '/opentool-daemon/tools/list') {
          expect(request.method, 'GET');
          expect(request.uri.queryParameters['all'], '1');
          request.response.write(
            jsonEncode(<Map<String, dynamic>>[
              <String, dynamic>{
                'id': 'tool-1',
                'alias': 'websearch',
                'host': '127.0.0.1',
                'port': 9001,
                'status': 'running',
                'serverId': 'server-1',
                'server': <String, dynamic>{
                  'namespace': 'local',
                  'name': 'opentool-server-websearch',
                  'version': '0.1.0',
                },
              },
            ]),
          );
        } else if (request.uri.path == '/opentool-daemon/tools/tool-1/load') {
          expect(request.method, 'GET');
          request.response.write(
            jsonEncode(<String, dynamic>{
              'info': <String, dynamic>{
                'title': 'Demo Tool',
                'version': '1.0.0',
              },
              'functions': <Map<String, dynamic>>[],
            }),
          );
        } else {
          request.response.statusCode = 404;
          request.response.write('unexpected path');
        }
        await request.response.close();
      });

      final serviceLocator = _FakeServiceLocator(
        runningModelIds: const {},
        models: const [],
        openToolPort: upstream.port,
      );
      final handler = createGatewayHandler(
        serviceLocator: serviceLocator,
        kernelFuture: Future<KernelService?>.value(null),
        liteAgentSdk: LiteAgentSDK(baseUrl: 'http://127.0.0.1:9527/api/v1'),
        enableLogging: false,
      );
      gateway = await shelf_io.serve(handler, InternetAddress.loopbackIPv4, 0);

      try {
        final registerRes = await post(
          Uri.parse(
            'http://${gateway.address.host}:${gateway.port}/appkit/register',
          ),
          headers: {'content-type': 'application/json'},
          body: jsonEncode(<String, String>{'bundleId': 'com.demo.toolkit'}),
        );
        final token =
            (jsonDecode(registerRes.body) as Map<String, dynamic>)['token']
                as String;

        final response = await get(
          Uri.parse(
            'http://${gateway.address.host}:${gateway.port}/toolkit/list?all=1',
          ),
          headers: {'authorization': 'Bearer $token'},
        );

        expect(response.statusCode, 200);
        final tool =
            (jsonDecode(response.body) as List<dynamic>).single
                as Map<String, dynamic>;
        expect(tool['serverId'], 'server-1');
        expect(tool['server'], <String, dynamic>{
          'namespace': 'local',
          'name': 'opentool-server-websearch',
          'version': '0.1.0',
        });
        expect(
          requestedPaths,
          isNot(contains('/opentool-daemon/servers/list')),
        );

        final loadResponse = await get(
          Uri.parse(
            'http://${gateway.address.host}:${gateway.port}/toolkit/tool-1/load',
          ),
          headers: {'authorization': 'Bearer $token'},
        );
        expect(loadResponse.statusCode, 200);
        expect(loadResponse.body, contains('Demo Tool'));

        final managementResponse = await post(
          Uri.parse(
            'http://${gateway.address.host}:${gateway.port}/toolkit/tool-1/stop',
          ),
          headers: {'authorization': 'Bearer $token'},
        );
        expect(managementResponse.statusCode, 404);
        expect(
          requestedPaths,
          isNot(contains('/opentool-daemon/tools/tool-1/stop')),
        );
      } finally {
        await gateway.close(force: true);
        await upstream.close(force: true);
      }
    },
  );

  test('ModelKit no auth required', () async {
    // ModelKit does not require authentication, direct access allowed
    final response = await post(
      Uri.parse('$host/modelkit/chat/v1/chat/completions'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({'messages': []}),
    );
    // Should not return 401 (would return 401 when auth was required)
    // May return 502 (proxy error), 503 (service unavailable) or 200 (ok)
    expect(response.statusCode, isNot(401));
  });

  test(
    'ModelKit bare chat route defaults to chat completions for versioned baseUrl',
    () async {
      final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      late HttpServer gateway;

      upstream.listen((request) async {
        expect(request.uri.path, '/v7/chat/completions');

        request.response.statusCode = 200;
        request.response.headers.set(
          HttpHeaders.contentTypeHeader,
          'application/json',
        );
        request.response.write(
          jsonEncode(<String, dynamic>{
            'id': 'chatcmpl-route-default',
            'object': 'chat.completion',
            'choices': <Map<String, dynamic>>[],
          }),
        );
        await request.response.close();
      });

      final serviceLocator = _FakeServiceLocator(
        runningModelIds: const {},
        models: <LlmModelInfo>[
          LlmModelInfo(
            id: 'remote-gpt',
            name: 'gpt-4.1',
            alias: 'gpt-4.1',
            description: 'remote custom model',
            parameters: 'remote',
            paramsB: 0,
            quantization: 'none',
            sizeGB: 0,
            minRAMGB: 0,
            downloadUrl: '',
            tags: const ['chat'],
            repoId: 'remote',
            type: 'text',
            contextWindowSize: 128000,
            baseUrl: 'http://${upstream.address.host}:${upstream.port}/v7',
            isCustom: true,
          ),
        ],
      );
      final handler = createGatewayHandler(
        serviceLocator: serviceLocator,
        kernelFuture: Future<KernelService?>.value(null),
        liteAgentSdk: LiteAgentSDK(baseUrl: 'http://127.0.0.1:9527/api/v1'),
        enableLogging: false,
      );
      gateway = await shelf_io.serve(handler, InternetAddress.loopbackIPv4, 0);

      try {
        final response = await post(
          Uri.parse(
            'http://${gateway.address.host}:${gateway.port}/modelkit/chat',
          ),
          headers: {'content-type': 'application/json'},
          body: jsonEncode(<String, dynamic>{
            'model': 'remote-gpt',
            'messages': <Map<String, String>>[
              <String, String>{'role': 'user', 'content': 'hello'},
            ],
          }),
        );

        expect(response.statusCode, 200);
        expect(response.body, contains('chatcmpl-route-default'));
      } finally {
        await gateway.close(force: true);
        await upstream.close(force: true);
      }
    },
  );

  test('AppKit register bundle', () async {
    final registerRes = await post(
      Uri.parse('$host/appkit/register'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode(<String, String>{
        'bundleId': 'com.demo.app',
        'appGroupId': 'com.demo',
      }),
    );
    expect(registerRes.statusCode, 200);
    final registerPayload =
        jsonDecode(registerRes.body) as Map<String, dynamic>;
    final token = registerPayload['token'] as String;
    expect(token, startsWith('sk-'));
    expect(registerPayload['bundleId'], 'com.demo.app');
    expect(registerPayload['appGroupId'], 'com.demo');
  });

  test('/modelkit/models returns available models with task schema', () async {
    final serviceLocator = _FakeServiceLocator(
      runningModelIds: const {'qwen3-8b'},
      models: const [
        LlmModelInfo(
          id: 'qwen3-8b',
          name: 'qwen3-8b',
          alias: 'qwen3-8b',
          description: 'text model',
          parameters: '8B',
          paramsB: 8,
          quantization: 'q4',
          sizeGB: 4,
          minRAMGB: 8,
          downloadUrl: '',
          tags: ['chat'],
          repoId: 'repo',
          type: 'textGeneration',
          contextWindowSize: 8192,
        ),
        LlmModelInfo(
          id: 'bge-large-zh-v1.5-q8_0',
          name: 'bge-large-zh-v1.5-q8_0',
          alias: 'bge-large-zh-v1.5-q8_0',
          description: 'embedding model',
          parameters: 'embedding',
          paramsB: 0,
          quantization: 'q8_0',
          sizeGB: 0,
          minRAMGB: 0,
          downloadUrl: '',
          tags: ['embedding'],
          repoId: 'repo',
          type: 'llm_embedding',
          contextWindowSize: 4096,
        ),
        LlmModelInfo(
          id: 'stopped-local-model',
          name: 'stopped-local-model',
          alias: 'stopped-local-model',
          description: 'text model but not running',
          parameters: '7B',
          paramsB: 7,
          quantization: 'q4',
          sizeGB: 4,
          minRAMGB: 8,
          downloadUrl: '',
          tags: ['chat'],
          repoId: 'repo',
          type: 'text',
          contextWindowSize: 4096,
        ),
        LlmModelInfo(
          id: 'remote-gpt',
          name: 'gpt-4.1',
          alias: 'gpt-4.1',
          description: 'remote custom model',
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
          isCustom: true,
        ),
      ],
    );
    final kernelFuture = Future<KernelService?>.value(null);
    final liteAgentSdk = LiteAgentSDK(baseUrl: 'http://127.0.0.1:9527/api/v1');
    final handler = createGatewayHandler(
      serviceLocator: serviceLocator,
      kernelFuture: kernelFuture,
      liteAgentSdk: liteAgentSdk,
      enableLogging: false,
    );
    final localServer = await shelf_io.serve(
      handler,
      InternetAddress.loopbackIPv4,
      0,
    );
    final localHost = 'http://${localServer.address.host}:${localServer.port}';

    try {
      final response = await get(Uri.parse('$localHost/modelkit/models'));
      expect(response.statusCode, 200);

      final payload = jsonDecode(response.body) as List<dynamic>;
      final byId = {
        for (final e in payload.cast<Map<String, dynamic>>())
          e['id'] as String: e,
      };

      final qwen = byId['qwen3-8b']!;
      expect(qwen['name'], 'qwen3-8b');
      expect(qwen['alias'], 'qwen3-8b');
      expect(qwen['description'], 'text model');
      expect(qwen['task'], 'chat');
      expect(qwen['contextWindowSize'], 8192);
      expect(qwen['isRemote'], isFalse);
      expect(qwen['isCustom'], isFalse);

      // Stopped local chat model must not be listed.
      expect(byId.containsKey('stopped-local-model'), isFalse);

      final embedding = byId['bge-large-zh-v1.5-q8_0']!;
      expect(embedding['task'], 'embedding');

      final remote = byId['remote-gpt']!;
      expect(remote['name'], 'gpt-4.1');
      expect(remote['alias'], 'gpt-4.1');
      expect(remote['isRemote'], isTrue);
      expect(remote['isCustom'], isTrue);
      expect(remote.containsKey('baseUrl'), isFalse);
    } finally {
      await localServer.close(force: true);
    }
  });

  test('LLM upstream 504 is logged with target context', () async {
    final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final records = <LogRecord>[];
    late StreamSubscription<LogRecord> subscription;
    subscription = requestLogger.onRecord.listen(records.add);

    upstream.listen((request) async {
      expect(request.uri.path, '/v1/chat/completions');
      request.response.statusCode = 504;
      request.response.headers.set(
        HttpHeaders.contentTypeHeader,
        'application/json',
      );
      request.response.write(
        jsonEncode(<String, dynamic>{
          'error': 'upstream timeout',
          'provider': 'mock-remote',
        }),
      );
      await request.response.close();
    });

    final serviceLocator = _FakeServiceLocator(
      runningModelIds: const {},
      models: <LlmModelInfo>[
        LlmModelInfo(
          id: 'remote-gpt',
          name: 'gpt-4.1',
          alias: 'gpt-4.1',
          description: 'remote custom model',
          parameters: 'remote',
          paramsB: 0,
          quantization: 'none',
          sizeGB: 0,
          minRAMGB: 0,
          downloadUrl: '',
          tags: const ['chat'],
          repoId: 'remote',
          type: 'text',
          contextWindowSize: 128000,
          baseUrl: 'http://${upstream.address.host}:${upstream.port}',
          isCustom: true,
        ),
      ],
    );
    final client = ModelClient(
      serviceLocator: serviceLocator,
      kernelFuture: Future<KernelService?>.value(null),
    );

    try {
      final response = await client.send(
        task: ModelTask.chat,
        method: 'POST',
        path: '/v1/chat/completions',
        queryParameters: const {'source': 'test'},
        body: utf8.encode(jsonEncode(<String, dynamic>{'model': 'remote-gpt'})),
      );

      expect(response.statusCode, 504);
      expect(utf8.decode(response.bodyBytes!), contains('upstream timeout'));

      final warning = records.lastWhere(
        (record) =>
            record.level == Level.WARNING &&
            record.message.contains('Model proxy upstream error'),
      );
      expect(warning.message, contains('status=504'));
      expect(warning.message, contains('task=chat'));
      expect(warning.message, contains('/v1/chat/completions?source=test'));
      expect(warning.message, contains('upstream timeout'));
    } finally {
      await subscription.cancel();
      await upstream.close(force: true);
    }
  });

  test('LLM remote model id is rewritten to upstream model name', () async {
    final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);

    upstream.listen((request) async {
      expect(request.uri.path, '/v1/chat/completions');
      final body =
          jsonDecode(await utf8.decoder.bind(request).join())
              as Map<String, dynamic>;
      expect(body['model'], 'gpt-4.1');

      request.response.statusCode = 200;
      request.response.headers.set(
        HttpHeaders.contentTypeHeader,
        'application/json',
      );
      request.response.write(
        jsonEncode(<String, dynamic>{
          'id': 'chatcmpl-test',
          'object': 'chat.completion',
          'choices': <Map<String, dynamic>>[],
        }),
      );
      await request.response.close();
    });

    final serviceLocator = _FakeServiceLocator(
      runningModelIds: const {},
      models: <LlmModelInfo>[
        LlmModelInfo(
          id: 'remote-gpt',
          name: 'gpt-4.1',
          alias: 'gpt-4.1',
          description: 'remote custom model',
          parameters: 'remote',
          paramsB: 0,
          quantization: 'none',
          sizeGB: 0,
          minRAMGB: 0,
          downloadUrl: '',
          tags: const ['chat'],
          repoId: 'remote',
          type: 'text',
          contextWindowSize: 128000,
          baseUrl: 'http://${upstream.address.host}:${upstream.port}',
          isCustom: true,
        ),
      ],
    );
    final client = ModelClient(
      serviceLocator: serviceLocator,
      kernelFuture: Future<KernelService?>.value(null),
    );

    try {
      final response = await client.send(
        task: ModelTask.chat,
        method: 'POST',
        path: '/v1/chat/completions',
        body: utf8.encode(
          jsonEncode(<String, dynamic>{
            'model': 'remote-gpt',
            'messages': <Map<String, String>>[
              <String, String>{'role': 'user', 'content': 'hello'},
            ],
          }),
        ),
      );

      expect(response.statusCode, 200);
      expect(utf8.decode(response.bodyBytes!), contains('chatcmpl-test'));
    } finally {
      await upstream.close(force: true);
    }
  });

  test(
    'LLM request deduplicates /v1 when upstream baseUrl already includes it',
    () async {
      final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);

      upstream.listen((request) async {
        expect(request.uri.path, '/v1/chat/completions');

        request.response.statusCode = 200;
        request.response.headers.set(
          HttpHeaders.contentTypeHeader,
          'application/json',
        );
        request.response.write(
          jsonEncode(<String, dynamic>{
            'id': 'chatcmpl-deduped',
            'object': 'chat.completion',
            'choices': <Map<String, dynamic>>[],
          }),
        );
        await request.response.close();
      });

      final serviceLocator = _FakeServiceLocator(
        runningModelIds: const {},
        models: <LlmModelInfo>[
          LlmModelInfo(
            id: 'remote-gpt',
            name: 'gpt-4.1',
            alias: 'gpt-4.1',
            description: 'remote custom model',
            parameters: 'remote',
            paramsB: 0,
            quantization: 'none',
            sizeGB: 0,
            minRAMGB: 0,
            downloadUrl: '',
            tags: const ['chat'],
            repoId: 'remote',
            type: 'text',
            contextWindowSize: 128000,
            baseUrl: 'http://${upstream.address.host}:${upstream.port}/v1',
            isCustom: true,
          ),
        ],
      );
      final client = ModelClient(
        serviceLocator: serviceLocator,
        kernelFuture: Future<KernelService?>.value(null),
      );

      try {
        final response = await client.send(
          task: ModelTask.chat,
          method: 'POST',
          path: '/v1/chat/completions',
          body: utf8.encode(
            jsonEncode(<String, dynamic>{
              'model': 'remote-gpt',
              'messages': <Map<String, String>>[
                <String, String>{'role': 'user', 'content': 'hello'},
              ],
            }),
          ),
        );

        expect(response.statusCode, 200);
        expect(utf8.decode(response.bodyBytes!), contains('chatcmpl-deduped'));
      } finally {
        await upstream.close(force: true);
      }
    },
  );

  test(
    'LLM request reuses any upstream version prefix for default text endpoint',
    () async {
      final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);

      upstream.listen((request) async {
        expect(request.uri.path, '/v42/chat/completions');

        request.response.statusCode = 200;
        request.response.headers.set(
          HttpHeaders.contentTypeHeader,
          'application/json',
        );
        request.response.write(
          jsonEncode(<String, dynamic>{
            'id': 'chatcmpl-v42-default',
            'object': 'chat.completion',
            'choices': <Map<String, dynamic>>[],
          }),
        );
        await request.response.close();
      });

      final serviceLocator = _FakeServiceLocator(
        runningModelIds: const {},
        models: <LlmModelInfo>[
          LlmModelInfo(
            id: 'remote-gpt',
            name: 'gpt-4.1',
            alias: 'gpt-4.1',
            description: 'remote custom model',
            parameters: 'remote',
            paramsB: 0,
            quantization: 'none',
            sizeGB: 0,
            minRAMGB: 0,
            downloadUrl: '',
            tags: const ['chat'],
            repoId: 'remote',
            type: 'text',
            contextWindowSize: 128000,
            baseUrl: 'http://${upstream.address.host}:${upstream.port}/v42',
            isCustom: true,
          ),
        ],
      );
      final client = ModelClient(
        serviceLocator: serviceLocator,
        kernelFuture: Future<KernelService?>.value(null),
      );

      try {
        final response = await client.send(
          task: ModelTask.chat,
          method: 'POST',
          path: '/',
          body: utf8.encode(
            jsonEncode(<String, dynamic>{
              'model': 'remote-gpt',
              'messages': <Map<String, String>>[
                <String, String>{'role': 'user', 'content': 'hello'},
              ],
            }),
          ),
        );

        expect(response.statusCode, 200);
        expect(
          utf8.decode(response.bodyBytes!),
          contains('chatcmpl-v42-default'),
        );
      } finally {
        await upstream.close(force: true);
      }
    },
  );

  test(
    'LLM request replaces incoming version prefix with upstream version prefix',
    () async {
      final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);

      upstream.listen((request) async {
        expect(request.uri.path, '/v42/chat/completions');

        request.response.statusCode = 200;
        request.response.headers.set(
          HttpHeaders.contentTypeHeader,
          'application/json',
        );
        request.response.write(
          jsonEncode(<String, dynamic>{
            'id': 'chatcmpl-v42-rewrite',
            'object': 'chat.completion',
            'choices': <Map<String, dynamic>>[],
          }),
        );
        await request.response.close();
      });

      final serviceLocator = _FakeServiceLocator(
        runningModelIds: const {},
        models: <LlmModelInfo>[
          LlmModelInfo(
            id: 'remote-gpt',
            name: 'gpt-4.1',
            alias: 'gpt-4.1',
            description: 'remote custom model',
            parameters: 'remote',
            paramsB: 0,
            quantization: 'none',
            sizeGB: 0,
            minRAMGB: 0,
            downloadUrl: '',
            tags: const ['chat'],
            repoId: 'remote',
            type: 'text',
            contextWindowSize: 128000,
            baseUrl: 'http://${upstream.address.host}:${upstream.port}/v42',
            isCustom: true,
          ),
        ],
      );
      final client = ModelClient(
        serviceLocator: serviceLocator,
        kernelFuture: Future<KernelService?>.value(null),
      );

      try {
        final response = await client.send(
          task: ModelTask.chat,
          method: 'POST',
          path: '/v1/chat/completions',
          body: utf8.encode(
            jsonEncode(<String, dynamic>{
              'model': 'remote-gpt',
              'messages': <Map<String, String>>[
                <String, String>{'role': 'user', 'content': 'hello'},
              ],
            }),
          ),
        );

        expect(response.statusCode, 200);
        expect(
          utf8.decode(response.bodyBytes!),
          contains('chatcmpl-v42-rewrite'),
        );
      } finally {
        await upstream.close(force: true);
      }
    },
  );

  test(
    'LLM request keeps complete upstream endpoint without auto-filling path',
    () async {
      final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);

      upstream.listen((request) async {
        expect(request.uri.path, '/v42/chat/completions');

        request.response.statusCode = 200;
        request.response.headers.set(
          HttpHeaders.contentTypeHeader,
          'application/json',
        );
        request.response.write(
          jsonEncode(<String, dynamic>{
            'id': 'chatcmpl-complete-endpoint',
            'object': 'chat.completion',
            'choices': <Map<String, dynamic>>[],
          }),
        );
        await request.response.close();
      });

      final serviceLocator = _FakeServiceLocator(
        runningModelIds: const {},
        models: <LlmModelInfo>[
          LlmModelInfo(
            id: 'remote-gpt',
            name: 'gpt-4.1',
            alias: 'gpt-4.1',
            description: 'remote custom model',
            parameters: 'remote',
            paramsB: 0,
            quantization: 'none',
            sizeGB: 0,
            minRAMGB: 0,
            downloadUrl: '',
            tags: const ['chat'],
            repoId: 'remote',
            type: 'text',
            contextWindowSize: 128000,
            baseUrl:
                'http://${upstream.address.host}:${upstream.port}/v42/chat/completions',
            isCustom: true,
          ),
        ],
      );
      final client = ModelClient(
        serviceLocator: serviceLocator,
        kernelFuture: Future<KernelService?>.value(null),
      );

      try {
        final response = await client.send(
          task: ModelTask.chat,
          method: 'POST',
          path: '/',
          body: utf8.encode(
            jsonEncode(<String, dynamic>{
              'model': 'remote-gpt',
              'messages': <Map<String, String>>[
                <String, String>{'role': 'user', 'content': 'hello'},
              ],
            }),
          ),
        );

        expect(response.statusCode, 200);
        expect(
          utf8.decode(response.bodyBytes!),
          contains('chatcmpl-complete-endpoint'),
        );
      } finally {
        await upstream.close(force: true);
      }
    },
  );

  test('LLM request keeps non-/v1 upstream prefixes intact', () async {
    final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);

    upstream.listen((request) async {
      expect(request.uri.path, '/openai/v1/chat/completions');

      request.response.statusCode = 200;
      request.response.headers.set(
        HttpHeaders.contentTypeHeader,
        'application/json',
      );
      request.response.write(
        jsonEncode(<String, dynamic>{
          'id': 'chatcmpl-prefix',
          'object': 'chat.completion',
          'choices': <Map<String, dynamic>>[],
        }),
      );
      await request.response.close();
    });

    final serviceLocator = _FakeServiceLocator(
      runningModelIds: const {},
      models: <LlmModelInfo>[
        LlmModelInfo(
          id: 'remote-gpt',
          name: 'gpt-4.1',
          alias: 'gpt-4.1',
          description: 'remote custom model',
          parameters: 'remote',
          paramsB: 0,
          quantization: 'none',
          sizeGB: 0,
          minRAMGB: 0,
          downloadUrl: '',
          tags: const ['chat'],
          repoId: 'remote',
          type: 'text',
          contextWindowSize: 128000,
          baseUrl: 'http://${upstream.address.host}:${upstream.port}/openai',
          isCustom: true,
        ),
      ],
    );
    final client = ModelClient(
      serviceLocator: serviceLocator,
      kernelFuture: Future<KernelService?>.value(null),
    );

    try {
      final response = await client.send(
        task: ModelTask.chat,
        method: 'POST',
        path: '/v1/chat/completions',
        body: utf8.encode(
          jsonEncode(<String, dynamic>{
            'model': 'remote-gpt',
            'messages': <Map<String, String>>[
              <String, String>{'role': 'user', 'content': 'hello'},
            ],
          }),
        ),
      );

      expect(response.statusCode, 200);
      expect(utf8.decode(response.bodyBytes!), contains('chatcmpl-prefix'));
    } finally {
      await upstream.close(force: true);
    }
  });

  test('LLM streaming passthrough preserves final usage chunk', () async {
    final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);

    upstream.listen((request) async {
      expect(request.uri.path, '/v1/chat/completions');

      request.response.statusCode = 200;
      request.response.headers.set(
        HttpHeaders.contentTypeHeader,
        'text/event-stream; charset=utf-8',
      );

      request.response.write(
        'data: {"id":"chatcmpl-stream","created":1776733130,"choices":[{"index":0,"delta":{"content":"hello"},"finish_reason":null}]}\n\n',
      );
      await request.response.flush();

      request.response.write(
        'data: {"id":"chatcmpl-stream","created":1776733130,"choices":[{"index":0,"delta":{},"finish_reason":"stop"}],"usage":{"prompt_tokens":5,"completion_tokens":2,"total_tokens":7}}\n\n',
      );
      await request.response.flush();

      request.response.write('data: [DONE]\n\n');
      await request.response.close();
    });

    final serviceLocator = _FakeServiceLocator(
      runningModelIds: const {},
      models: <LlmModelInfo>[
        LlmModelInfo(
          id: 'remote-gpt',
          name: 'gpt-4.1',
          alias: 'gpt-4.1',
          description: 'remote custom model',
          parameters: 'remote',
          paramsB: 0,
          quantization: 'none',
          sizeGB: 0,
          minRAMGB: 0,
          downloadUrl: '',
          tags: const ['chat'],
          repoId: 'remote',
          type: 'text',
          contextWindowSize: 128000,
          baseUrl: 'http://${upstream.address.host}:${upstream.port}',
          isCustom: true,
        ),
      ],
    );
    final client = ModelClient(
      serviceLocator: serviceLocator,
      kernelFuture: Future<KernelService?>.value(null),
    );

    try {
      final response = await client.send(
        task: ModelTask.chat,
        method: 'POST',
        path: '/v1/chat/completions',
        headers: const {'accept': 'text/event-stream'},
        body: utf8.encode(
          jsonEncode(<String, dynamic>{
            'model': 'remote-gpt',
            'stream': true,
            'stream_options': <String, dynamic>{'include_usage': true},
            'messages': <Map<String, String>>[
              <String, String>{'role': 'user', 'content': 'hello'},
            ],
          }),
        ),
        streamResponse: true,
      );

      expect(response.statusCode, 200);
      expect(response.bodyStream, isNotNull);
      final streamedBody = await utf8.decoder.bind(response.bodyStream!).join();
      expect(streamedBody, contains('"usage"'));
      expect(streamedBody, contains('"completion_tokens":2'));
      expect(streamedBody, contains('data: [DONE]'));
    } finally {
      await upstream.close(force: true);
    }
  });
}

String _readPubspecVersion() {
  final pubspec = File('pubspec.yaml').readAsStringSync();
  final match = RegExp(
    r'^version:\s*([^\s#]+)',
    multiLine: true,
  ).firstMatch(pubspec);
  if (match == null) {
    throw StateError('version not found in pubspec.yaml');
  }
  return match.group(1)!;
}
