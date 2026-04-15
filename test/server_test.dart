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
  _FakeServiceLocator({required this.models, required this.runningModelIds});

  final List<LlmModelInfo> models;
  final Set<String> runningModelIds;

  @override
  String get liteagentBaseUrl => 'http://127.0.0.1:9527/api/v1';

  @override
  Future<List<AppInfo>> getAppInfoList() async => const [];

  @override
  Future<List<LlmModelInfo>> getLlmModelList() async => models;

  @override
  Future<int?> getServicePort(String serviceKey, {String? modelId}) async {
    if (serviceKey == ApiConfig.serviceLlmText && modelId != null) {
      return runningModelIds.contains(modelId) ? 52010 : null;
    }
    return switch (serviceKey) {
      ApiConfig.serviceLiteagent => 9527,
      ApiConfig.serviceOpentool => 19627,
      ApiConfig.serviceEmbeddings => 9537,
      ApiConfig.serviceLlmText => 52010,
      ApiConfig.serviceLlmVision => 52020,
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

  test('Toolkit no auth required', () async {
    // ToolKit no longer requires authentication, direct access allowed
    final response = await get(Uri.parse('$host/toolkit/tools'));
    // Should not return 401 (would return 401 when auth was required)
    // May return 404 (path not found), 502 (proxy error), 503 (service unavailable) or 200 (ok)
    expect(response.statusCode, isNot(401));
  });

  test('LLMKit no auth required', () async {
    // LLMKit no longer requires authentication, direct access allowed
    final response = await post(
      Uri.parse('$host/llmkit/text/v1/chat/completions'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({'messages': []}),
    );
    // Should not return 401 (would return 401 when auth was required)
    // May return 502 (proxy error), 503 (service unavailable) or 200 (ok)
    expect(response.statusCode, isNot(401));
  });

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

  test(
    '/llmkit/models returns available text generation models only',
    () async {
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
      final liteAgentSdk = LiteAgentSDK(
        baseUrl: 'http://127.0.0.1:9527/api/v1',
      );
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
      final localHost =
          'http://${localServer.address.host}:${localServer.port}';

      try {
        final response = await get(Uri.parse('$localHost/llmkit/models'));
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
        expect(qwen['type'], 'textGeneration');
        expect(qwen['contextWindowSize'], 8192);
        expect(qwen['isRemote'], isFalse);
        expect(qwen['isCustom'], isFalse);

        final remote = byId['remote-gpt']!;
        expect(remote['name'], 'gpt-4.1');
        expect(remote['alias'], 'gpt-4.1');
        expect(remote['isRemote'], isTrue);
        expect(remote['isCustom'], isTrue);
        expect(remote['baseUrl'], 'https://example.test/v1');
      } finally {
        await localServer.close(force: true);
      }
    },
  );

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
    final client = LLMClient(
      serviceLocator: serviceLocator,
      kernelFuture: Future<KernelService?>.value(null),
    );

    try {
      final response = await client.send(
        serviceType: LLMServiceType.text,
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
            record.message.contains('LLM proxy upstream error'),
      );
      expect(warning.message, contains('status=504'));
      expect(warning.message, contains('service=llm_text'));
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
    final client = LLMClient(
      serviceLocator: serviceLocator,
      kernelFuture: Future<KernelService?>.value(null),
    );

    try {
      final response = await client.send(
        serviceType: LLMServiceType.text,
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
