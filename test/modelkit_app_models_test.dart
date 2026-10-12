import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:agentos_api/agentos_api.dart';
import 'package:agentos_kernel/agentos_kernel.dart' show KernelService;
import 'package:http/http.dart';
import 'package:liteagent_sdk_dart/liteagent_sdk_dart.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:test/test.dart';

/// 内存版 locator：同时实现 [AgentOSServiceLocator] 与 [AppModelStore]，
/// 并把 app model 暴露成远程 [LlmModelInfo]，用来验证 `/modelkit/*` 的完整链路。
///
/// `addAppModel` 故意先让出事件循环再写入，模拟真实存储“读-改-写不原子”的
/// 窗口，用于验证 controller 对并发同 id 写入的串行化。
class _FakeAppModelLocator implements AgentOSServiceLocator, AppModelStore {
  final List<AppModelData> _models = [];

  @override
  String get liteagentBaseUrl => 'http://127.0.0.1:9527/api/v1';

  @override
  Stream<ServiceStatusEvent> get serviceStatusStream => const Stream.empty();

  @override
  Future<int?> getServicePort(String serviceKey, {String? modelId}) async =>
      null;

  @override
  Future<List<AppInfo>> getAppInfoList() async => const [];

  @override
  Future<List<LlmModelInfo>> getLlmModelList() async => _models
      .where((m) => !m.isDisabled)
      .map(
        (m) => LlmModelInfo(
          id: m.id,
          name: m.name,
          alias: m.alias,
          description: m.description,
          parameters: '',
          paramsB: 0,
          quantization: '',
          sizeGB: 0,
          minRAMGB: 0,
          downloadUrl: '',
          tags: const [],
          repoId: '',
          type: m.task,
          contextWindowSize: m.contextSize,
          baseUrl: m.baseUrl,
          apiKey: m.apiKey,
          isAppModel: true,
          appBundleId: m.appBundleId,
          task: m.task,
          inputModalities: m.inputModalities,
          outputModalities: m.outputModalities,
          vision: m.inputModalities.contains('image'),
          toolCall: m.toolCall,
          stream: m.stream,
          reasoning: m.reasoning,
        ),
      )
      .toList();

  @override
  List<AppModelData> get appModels => List.unmodifiable(_models);

  AppModelData? byId(String id) {
    for (final m in _models) {
      if (m.id == id) return m;
    }
    return null;
  }

  @override
  Future<void> addAppModel(AppModelData model) async {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    _models.add(model);
  }

  @override
  Future<bool> updateAppModel(String id, AppModelData model) async {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    final index = _models.indexWhere((m) => m.id == id);
    if (index < 0) return false;
    _models[index] = model;
    return true;
  }

  @override
  Future<bool> deleteAppModel(String id) async {
    final before = _models.length;
    _models.removeWhere((m) => m.id == id);
    return _models.length != before;
  }

  @override
  Future<bool> toggleAppModelDisabled(String id) async {
    final index = _models.indexWhere((m) => m.id == id);
    if (index < 0) return false;
    final m = _models[index];
    _models[index] = AppModelData(
      id: m.id,
      name: m.name,
      alias: m.alias,
      description: m.description,
      task: m.task,
      provider: m.provider,
      inputModalities: m.inputModalities,
      outputModalities: m.outputModalities,
      stream: m.stream,
      toolCall: m.toolCall,
      reasoning: m.reasoning,
      baseUrl: m.baseUrl,
      apiKey: m.apiKey,
      contextSize: m.contextSize,
      isDisabled: !m.isDisabled,
      appBundleId: m.appBundleId,
      appName: m.appName,
    );
    return true;
  }

  @override
  Future<int> removeAppModelsByBundleId(String bundleId) async {
    final before = _models.length;
    _models.removeWhere((m) => m.appBundleId == bundleId);
    return before - _models.length;
  }
}

/// 记录收到的请求并返回固定 decision 响应的本地 upstream。
class _RecordedRequest {
  _RecordedRequest(this.method, this.path, this.authorization, this.body);

  final String method;
  final String path;
  final String? authorization;
  final Map<String, dynamic> body;
}

Future<HttpServer> _serveGateway(AgentOSServiceLocator locator) {
  final handler = createGatewayHandler(
    serviceLocator: locator,
    kernelFuture: Future<KernelService?>.value(null),
    liteAgentSdk: LiteAgentSDK(baseUrl: 'http://127.0.0.1:9527/api/v1'),
    enableLogging: false,
  );
  return shelf_io.serve(handler, InternetAddress.loopbackIPv4, 0);
}

String _hostOf(HttpServer server) =>
    'http://${server.address.host}:${server.port}';

/// 响应没有 charset 时 `Response.body` 会按 latin1 解码，这里统一按 UTF-8 解。
Object? _decode(Response response) =>
    jsonDecode(utf8.decode(response.bodyBytes));

Map<String, dynamic> _asMap(Response response) =>
    _decode(response) as Map<String, dynamic>;

void main() {
  late _FakeAppModelLocator locator;
  late HttpServer gateway;
  late String host;

  setUp(() async {
    locator = _FakeAppModelLocator();
    gateway = await _serveGateway(locator);
    host = _hostOf(gateway);
  });

  tearDown(() => gateway.close(force: true));

  Future<String> registerBundle(String bundleId, {String? base}) async {
    final response = await post(
      Uri.parse('${base ?? host}/appkit/register'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({'bundleId': bundleId}),
    );
    expect(response.statusCode, 200, reason: response.body);
    return _asMap(response)['token'] as String;
  }

  Map<String, String> authHeaders(String token) => {
    'content-type': 'application/json',
    'authorization': 'Bearer $token',
  };

  Future<Response> register(String token, Map<String, dynamic> body) => post(
    Uri.parse('$host/modelkit/app-models'),
    headers: authHeaders(token),
    body: utf8.encode(jsonEncode(body)),
  );

  Future<Response> update(String token, String id, Map<String, dynamic> body) =>
      put(
        Uri.parse('$host/modelkit/app-models/$id'),
        headers: authHeaders(token),
        body: utf8.encode(jsonEncode(body)),
      );

  Future<Response> unregister(String token, String id) => delete(
    Uri.parse('$host/modelkit/app-models/$id'),
    headers: authHeaders(token),
  );

  Future<Response> toggle(String token, String id) => post(
    Uri.parse('$host/modelkit/app-models/$id/toggle'),
    headers: authHeaders(token),
  );

  Map<String, dynamic> decisionBody({String id = 'dec-1'}) => {
    'id': id,
    'name': 'qwen-decision',
    'task': 'decision',
    'baseUrl': 'http://127.0.0.1:1',
  };

  group('认证', () {
    test('写接口缺少或使用无效 token 时返回 401，且不会写入任何数据', () async {
      final bogus = <String, String>{
        'content-type': 'application/json',
        'authorization': 'Bearer sk-not-issued',
      };
      final noAuth = <String, String>{'content-type': 'application/json'};

      for (final headers in [noAuth, bogus]) {
        final created = await post(
          Uri.parse('$host/modelkit/app-models'),
          headers: headers,
          body: jsonEncode(decisionBody()),
        );
        expect(created.statusCode, 401);
        expect(_asMap(created)['error'], isNotEmpty);

        expect(
          (await put(
            Uri.parse('$host/modelkit/app-models/dec-1'),
            headers: headers,
            body: jsonEncode({'name': 'x'}),
          )).statusCode,
          401,
        );
        expect(
          (await delete(
            Uri.parse('$host/modelkit/app-models/dec-1'),
            headers: headers,
          )).statusCode,
          401,
        );
        expect(
          (await post(
            Uri.parse('$host/modelkit/app-models/dec-1/toggle'),
            headers: headers,
          )).statusCode,
          401,
        );
      }

      expect(locator.appModels, isEmpty);
    });

    test('GET /app-models 保持开放，不需要 token', () async {
      final response = await get(Uri.parse('$host/modelkit/app-models'));
      expect(response.statusCode, 200);
      expect(_decode(response), isEmpty);
    });

    test('locator 不支持 app model 持久化时返回 501，而不是假成功', () async {
      final bare = await _serveGateway(DefaultServiceLocator());
      addTearDown(() => bare.close(force: true));
      final bareHost = _hostOf(bare);
      final token = await registerBundle('com.example.a', base: bareHost);

      final response = await post(
        Uri.parse('$bareHost/modelkit/app-models'),
        headers: authHeaders(token),
        body: jsonEncode(decisionBody()),
      );
      expect(response.statusCode, 501);
    });
  });

  group('decision 注册', () {
    test('最小请求体即可注册，输入输出与能力位按 decision 约定补全', () async {
      final token = await registerBundle('com.example.a');

      final response = await register(token, decisionBody());
      expect(response.statusCode, 200, reason: response.body);
      expect(_asMap(response), {'success': true, 'id': 'dec-1'});

      final list =
          _decode(await get(Uri.parse('$host/modelkit/app-models')))
              as List<dynamic>;
      expect(list, hasLength(1));
      final model = list.single as Map<String, dynamic>;
      expect(model['task'], 'decision');
      expect(model['input'], ['text']);
      expect(model['output'], ['decisions']);
      expect(model['capabilities'], {
        'stream': false,
        'tool_call': false,
        'reasoning': false,
      });
      expect(model['appBundleId'], 'com.example.a');
      expect(model['appName'], 'com.example.a');
    });

    test('别名 task 与不合规的输入/输出/能力位会被归一化', () async {
      final token = await registerBundle('com.example.a');

      final response = await register(token, {
        ...decisionBody(),
        'task': 'SystemOne',
        'input': ['decisions', 'audio', 'image', 'text'],
        'output': ['text'],
        'capabilities': {'stream': true, 'tool_call': true, 'reasoning': true},
      });
      expect(response.statusCode, 200, reason: response.body);

      final model = locator.byId('dec-1')!;
      expect(model.task, 'decision');
      expect(model.inputModalities, ['text', 'image']);
      expect(model.outputModalities, ['decisions']);
      expect(
        [model.stream, model.toolCall, model.reasoning],
        [false, false, false],
      );
    });

    test('未知 task 返回 400；缺省 task 视为 chat 并沿用 chat 默认值', () async {
      final token = await registerBundle('com.example.a');

      final bad = await register(token, {...decisionBody(), 'task': 'vision'});
      expect(bad.statusCode, 400);
      expect(_asMap(bad)['error'], contains('decision'));
      expect(locator.appModels, isEmpty);

      final implicit = await register(token, {
        'id': 'chat-1',
        'name': 'gpt',
        'baseUrl': 'http://127.0.0.1:1',
      });
      expect(implicit.statusCode, 200, reason: implicit.body);
      final chat = locator.byId('chat-1')!;
      expect(chat.task, 'chat');
      expect(chat.inputModalities, ['text']);
      expect(chat.outputModalities, ['text']);
      expect([chat.stream, chat.toolCall, chat.reasoning], [true, false, true]);
    });

    test('非 decision 任务不接受 decisions 模态，缺省回退到该任务的默认值', () async {
      final token = await registerBundle('com.example.a');

      final response = await register(token, {
        'id': 'chat-1',
        'name': 'gpt',
        'baseUrl': 'http://127.0.0.1:1',
        'input': ['text', 'decisions'],
        'output': ['decisions'],
      });
      expect(response.statusCode, 200, reason: response.body);

      final chat = locator.byId('chat-1')!;
      expect(chat.inputModalities, ['text']);
      expect(chat.outputModalities, ['text']);
    });

    test('请求体类型错误返回 400，而不是 500', () async {
      final token = await registerBundle('com.example.a');

      for (final body in <Map<String, dynamic>>[
        {...decisionBody(), 'id': 123},
        {...decisionBody(), 'capabilities': 'yes'},
        {
          ...decisionBody(),
          'capabilities': {'stream': 'true'},
        },
        {...decisionBody(), 'input': 'text'},
        {...decisionBody(), 'contextWindowSize': 'big'},
      ]) {
        final response = await register(token, body);
        expect(response.statusCode, 400, reason: '$body -> ${response.body}');
      }

      final malformed = await post(
        Uri.parse('$host/modelkit/app-models'),
        headers: authHeaders(token),
        body: '{not json',
      );
      expect(malformed.statusCode, 400);

      final empty = await post(
        Uri.parse('$host/modelkit/app-models'),
        headers: authHeaders(token),
      );
      expect(empty.statusCode, 400);
      expect(locator.appModels, isEmpty);
    });

    test('中文 appName / description 不会被解成乱码', () async {
      final token = await registerBundle('com.example.a');

      final response = await register(token, {
        ...decisionBody(),
        'appName': '我的应用',
        'description': '中文描述',
      });
      expect(response.statusCode, 200, reason: response.body);

      final model = locator.byId('dec-1')!;
      expect(model.appName, '我的应用');
      expect(model.description, '中文描述');
    });
  });

  group('归属校验', () {
    test('appBundleId 可省略；与 token 不一致时返回 403', () async {
      final token = await registerBundle('com.example.a');

      final spoofed = await register(token, {
        ...decisionBody(),
        'appBundleId': 'com.example.b',
      });
      expect(spoofed.statusCode, 403);
      expect(locator.appModels, isEmpty);

      final matching = await register(token, {
        ...decisionBody(),
        'appBundleId': 'com.example.a',
      });
      expect(matching.statusCode, 200, reason: matching.body);
      expect(locator.byId('dec-1')!.appBundleId, 'com.example.a');
    });

    test('其他调用方不能修改、删除或切换别人的模型', () async {
      final tokenA = await registerBundle('com.example.a');
      final tokenB = await registerBundle('com.example.b');
      expect((await register(tokenA, decisionBody())).statusCode, 200);

      expect(
        (await update(tokenB, 'dec-1', {'name': 'hijacked'})).statusCode,
        403,
      );
      expect((await unregister(tokenB, 'dec-1')).statusCode, 403);
      expect((await toggle(tokenB, 'dec-1')).statusCode, 403);

      final model = locator.byId('dec-1')!;
      expect(model.name, 'qwen-decision');
      expect(model.isDisabled, isFalse);
      expect(model.appBundleId, 'com.example.a');

      // 所属方仍然可以操作。
      expect((await toggle(tokenA, 'dec-1')).statusCode, 200);
      expect(locator.byId('dec-1')!.isDisabled, isTrue);
      expect((await unregister(tokenA, 'dec-1')).statusCode, 200);
      expect(locator.appModels, isEmpty);
    });

    test('未知 id 返回 404', () async {
      final token = await registerBundle('com.example.a');

      expect((await update(token, 'missing', {'name': 'x'})).statusCode, 404);
      expect((await unregister(token, 'missing')).statusCode, 404);
      expect((await toggle(token, 'missing')).statusCode, 404);
    });

    test('同 id 被其他 bundle 占用时返回 409，原模型不受影响', () async {
      final tokenA = await registerBundle('com.example.a');
      final tokenB = await registerBundle('com.example.b');
      expect((await register(tokenA, decisionBody())).statusCode, 200);

      final conflict = await register(tokenB, {
        ...decisionBody(),
        'name': 'evil',
      });
      expect(conflict.statusCode, 409);
      expect(locator.appModels, hasLength(1));
      expect(locator.byId('dec-1')!.name, 'qwen-decision');
      expect(locator.byId('dec-1')!.appBundleId, 'com.example.a');
    });

    test('同 bundle 重复注册按整体替换（upsert），保留禁用状态且不产生重复条目', () async {
      final token = await registerBundle('com.example.a');
      expect((await register(token, decisionBody())).statusCode, 200);
      expect((await toggle(token, 'dec-1')).statusCode, 200);

      final again = await register(token, {
        ...decisionBody(),
        'name': 'qwen-decision-v2',
      });
      expect(again.statusCode, 200, reason: again.body);
      expect(_asMap(again)['updated'], isTrue);

      expect(locator.appModels, hasLength(1));
      final model = locator.byId('dec-1')!;
      expect(model.name, 'qwen-decision-v2');
      expect(model.isDisabled, isTrue);
    });

    test('并发的同 id 注册只会留下一条记录', () async {
      final token = await registerBundle('com.example.a');

      final responses = await Future.wait([
        for (var i = 0; i < 5; i++)
          register(token, {...decisionBody(), 'name': 'name-$i'}),
      ]);
      expect(responses.map((r) => r.statusCode), everyElement(200));
      expect(locator.appModels, hasLength(1));
    });

    test('两个 bundle 并发抢同一个 id：恰好一个成功、一个 409', () async {
      final tokenA = await registerBundle('com.example.a');
      final tokenB = await registerBundle('com.example.b');

      final responses = await Future.wait([
        register(tokenA, decisionBody()),
        register(tokenB, decisionBody()),
      ]);
      expect(responses.map((r) => r.statusCode).toList()..sort(), [200, 409]);
      expect(locator.appModels, hasLength(1));
    });
  });

  group('更新', () {
    test('PUT 是部分更新，且空 apiKey 不会清除已保存的密钥', () async {
      final token = await registerBundle('com.example.a');
      expect(
        (await register(token, {
          ...decisionBody(),
          'apiKey': 'sk-upstream',
          'description': 'before',
        })).statusCode,
        200,
      );

      final response = await update(token, 'dec-1', {
        'name': 'renamed',
        'apiKey': '',
      });
      expect(response.statusCode, 200, reason: response.body);

      final model = locator.byId('dec-1')!;
      expect(model.name, 'renamed');
      expect(model.description, 'before');
      expect(model.apiKey, 'sk-upstream');
      expect(model.task, 'decision');
      expect(model.outputModalities, ['decisions']);
    });

    test('PUT 把 task 改成 decision 时，旧的模态与能力位会被重置', () async {
      final token = await registerBundle('com.example.a');
      expect(
        (await register(token, {
          'id': 'm-1',
          'name': 'multi',
          'task': 'chat',
          'baseUrl': 'http://127.0.0.1:1',
          'input': ['text', 'image'],
          'capabilities': {
            'stream': true,
            'tool_call': true,
            'reasoning': true,
          },
        })).statusCode,
        200,
      );

      final response = await update(token, 'm-1', {'task': 'decision'});
      expect(response.statusCode, 200, reason: response.body);

      final model = locator.byId('m-1')!;
      expect(model.task, 'decision');
      expect(model.inputModalities, ['text']);
      expect(model.outputModalities, ['decisions']);
      expect(
        [model.stream, model.toolCall, model.reasoning],
        [false, false, false],
      );
    });

    test('PUT 带未知 task 或不同的 appBundleId 时返回 400', () async {
      final token = await registerBundle('com.example.a');
      expect((await register(token, decisionBody())).statusCode, 200);

      expect((await update(token, 'dec-1', {'task': 'bogus'})).statusCode, 400);
      expect(
        (await update(token, 'dec-1', {
          'appBundleId': 'com.example.b',
        })).statusCode,
        400,
      );
      expect(locator.byId('dec-1')!.task, 'decision');
      expect(locator.byId('dec-1')!.appBundleId, 'com.example.a');
    });
  });

  group('接入 ModelKit', () {
    test(
      'decision app model 出现在 /modelkit/models，但不在 /modelkit/chat/models',
      () async {
        final token = await registerBundle('com.example.a');
        expect((await register(token, decisionBody())).statusCode, 200);
        expect(
          (await register(token, {
            'id': 'chat-1',
            'name': 'gpt-chat',
            'baseUrl': 'http://127.0.0.1:1',
          })).statusCode,
          200,
        );

        final models =
            _decode(await get(Uri.parse('$host/modelkit/models')))
                as List<dynamic>;
        final decision = models.cast<Map<String, dynamic>>().singleWhere(
          (m) => m['id'] == 'dec-1',
        );
        expect(decision['task'], 'decision');
        expect(decision['output'], ['decisions']);
        expect(decision['isAppModel'], isTrue);
        expect(decision['appBundleId'], 'com.example.a');
        expect(decision['isRemote'], isTrue);

        final chatList = _asMap(
          await get(Uri.parse('$host/modelkit/chat/models')),
        );
        final data = (chatList['data'] as List).cast<Map<String, dynamic>>();
        expect(data, hasLength(1));
        expect(jsonEncode(data), isNot(contains('qwen-decision')));
      },
    );

    test(
      'POST /modelkit/decision 按模型的 baseUrl/apiKey 转发到 /v1/systemone',
      () async {
        final requests = <_RecordedRequest>[];
        final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => upstream.close(force: true));
        upstream.listen((request) async {
          final raw = await utf8.decoder.bind(request).join();
          requests.add(
            _RecordedRequest(
              request.method,
              request.uri.path,
              request.headers.value('authorization'),
              jsonDecode(raw) as Map<String, dynamic>,
            ),
          );
          request.response
            ..statusCode = 200
            ..headers.set('content-type', 'application/json')
            ..write(
              jsonEncode({
                'decisions': [
                  {'id': 'a'},
                ],
              }),
            );
          await request.response.close();
        });

        final token = await registerBundle('com.example.a');
        final registered = await register(token, {
          ...decisionBody(),
          'baseUrl': 'http://127.0.0.1:${upstream.port}',
          'apiKey': 'sk-upstream',
        });
        expect(registered.statusCode, 200, reason: registered.body);

        final response = await post(
          Uri.parse('$host/modelkit/decision'),
          headers: {'content-type': 'application/json'},
          body: jsonEncode({
            'model': 'dec-1',
            'input': 'pick one',
            'options': ['a', 'b'],
          }),
        );
        expect(response.statusCode, 200, reason: response.body);
        expect(_asMap(response)['decisions'], isNotEmpty);

        expect(requests, hasLength(1));
        expect(requests.single.method, 'POST');
        expect(requests.single.path, '/v1/systemone');
        expect(requests.single.authorization, 'Bearer sk-upstream');
        expect(requests.single.body['model'], 'qwen-decision');
      },
    );
  });
}
