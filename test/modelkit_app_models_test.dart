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
          // 与真实 locator 一致：对外 id 是 qualifiedId（localId@bundleId）。
          id: m.qualifiedId,
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
          appName: m.appName,
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

  /// 按 localId 取模型。仅适用于 localId 在整个 fake 里唯一的用例；
  /// 多个 bundle 共用同一个 localId 时请用 [byQualifiedId]。
  AppModelData? byId(String id) {
    for (final m in _models) {
      if (m.id == id) return m;
    }
    return null;
  }

  AppModelData? byQualifiedId(String qualifiedId) {
    for (final m in _models) {
      if (m.qualifiedId == qualifiedId) return m;
    }
    return null;
  }

  @override
  Future<void> addAppModel(AppModelData model) async {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    _models.add(model);
  }

  @override
  Future<bool> updateAppModel(String qualifiedId, AppModelData model) async {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    final index = _models.indexWhere((m) => m.qualifiedId == qualifiedId);
    if (index < 0) return false;
    _models[index] = model;
    return true;
  }

  @override
  Future<bool> deleteAppModel(String qualifiedId) async {
    final before = _models.length;
    _models.removeWhere((m) => m.qualifiedId == qualifiedId);
    return _models.length != before;
  }

  @override
  Future<bool> toggleAppModelDisabled(String qualifiedId) async {
    final index = _models.indexWhere((m) => m.qualifiedId == qualifiedId);
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
      expect(_asMap(response), {
        'success': true,
        'id': 'dec-1',
        'qualifiedId': 'dec-1@com.example.a',
      });

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

    test('其他调用方不能修改、删除或切换别人的模型（别人的 localId 在自己的命名空间里不存在 → 404）', () async {
      final tokenA = await registerBundle('com.example.a');
      final tokenB = await registerBundle('com.example.b');
      expect((await register(tokenA, decisionBody())).statusCode, 200);

      expect(
        (await update(tokenB, 'dec-1', {'name': 'hijacked'})).statusCode,
        404,
      );
      expect((await unregister(tokenB, 'dec-1')).statusCode, 404);
      expect((await toggle(tokenB, 'dec-1')).statusCode, 404);

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

    test('另一个 bundle 使用同一个 localId 不再冲突：各自独立，原模型不受影响', () async {
      final tokenA = await registerBundle('com.example.a');
      final tokenB = await registerBundle('com.example.b');
      expect((await register(tokenA, decisionBody())).statusCode, 200);

      final other = await register(tokenB, {
        ...decisionBody(),
        'name': 'other-name',
      });
      expect(other.statusCode, 200, reason: other.body);
      expect(_asMap(other)['updated'], isNull);

      expect(locator.appModels, hasLength(2));
      expect(
        locator.byQualifiedId('dec-1@com.example.a')!.name,
        'qwen-decision',
      );
      expect(locator.byQualifiedId('dec-1@com.example.b')!.name, 'other-name');
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

    test('两个 bundle 并发使用同一个 localId：都成功，各留一条', () async {
      final tokenA = await registerBundle('com.example.a');
      final tokenB = await registerBundle('com.example.b');

      final responses = await Future.wait([
        register(tokenA, decisionBody()),
        register(tokenB, decisionBody()),
      ]);
      expect(responses.map((r) => r.statusCode), everyElement(200));
      expect(locator.appModels, hasLength(2));
      expect(locator.appModels.map((m) => m.qualifiedId).toSet(), {
        'dec-1@com.example.a',
        'dec-1@com.example.b',
      });
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

  group('同一应用下 name 唯一', () {
    Map<String, dynamic> chatBody(String id, String name) => {
      'id': id,
      'name': name,
      'baseUrl': 'http://127.0.0.1:1',
    };

    test('同一应用用不同 id 注册同名模型返回 409，且不会写入', () async {
      final token = await registerBundle('com.example.a');
      expect((await register(token, chatBody('m-1', 'gpt-x'))).statusCode, 200);

      final conflict = await register(token, chatBody('m-2', 'gpt-x'));
      expect(conflict.statusCode, 409);
      final error = _asMap(conflict)['error'] as String;
      // 冲突提示要能告诉调用方是哪个名称、与哪个已有 id 冲突。
      expect(error, contains('gpt-x'));
      expect(error, contains('m-1'));

      expect(locator.appModels, hasLength(1));
      expect(locator.byId('m-1')!.name, 'gpt-x');
      expect(locator.byId('m-2'), isNull);
    });

    test('不同应用可以注册相同 name', () async {
      final tokenA = await registerBundle('com.example.a');
      final tokenB = await registerBundle('com.example.b');

      expect(
        (await register(tokenA, chatBody('a-1', 'gpt-x'))).statusCode,
        200,
      );
      final other = await register(tokenB, chatBody('b-1', 'gpt-x'));
      expect(other.statusCode, 200, reason: other.body);

      expect(locator.appModels, hasLength(2));
      expect(locator.byId('a-1')!.appBundleId, 'com.example.a');
      expect(locator.byId('b-1')!.appBundleId, 'com.example.b');
    });

    test('同 id 重复注册且 name 未变化仍是整体替换，不被拦截', () async {
      final token = await registerBundle('com.example.a');
      expect((await register(token, chatBody('m-1', 'gpt-x'))).statusCode, 200);

      final again = await register(token, {
        ...chatBody('m-1', 'gpt-x'),
        'description': 'refreshed',
      });
      expect(again.statusCode, 200, reason: again.body);
      expect(_asMap(again)['updated'], isTrue);
      expect(locator.appModels, hasLength(1));
      expect(locator.byId('m-1')!.description, 'refreshed');
    });

    test('同 id 重复注册时改成本应用已占用的 name 返回 409，原记录不变', () async {
      final token = await registerBundle('com.example.a');
      expect((await register(token, chatBody('m-1', 'gpt-x'))).statusCode, 200);
      expect((await register(token, chatBody('m-2', 'gpt-y'))).statusCode, 200);

      final conflict = await register(token, chatBody('m-2', 'gpt-x'));
      expect(conflict.statusCode, 409);
      expect(locator.byId('m-2')!.name, 'gpt-y');
      expect(locator.byId('m-1')!.name, 'gpt-x');
    });

    test('PUT 改名为本应用已占用的 name 返回 409，不能绕过注册时的检查', () async {
      final token = await registerBundle('com.example.a');
      expect((await register(token, chatBody('m-1', 'gpt-x'))).statusCode, 200);
      expect((await register(token, chatBody('m-2', 'gpt-y'))).statusCode, 200);

      final conflict = await update(token, 'm-2', {'name': 'gpt-x'});
      expect(conflict.statusCode, 409);
      expect(locator.byId('m-2')!.name, 'gpt-y');

      // 改成未被占用的名称、或保持原名只改其他字段，都应成功。
      final renamed = await update(token, 'm-2', {'name': 'gpt-z'});
      expect(renamed.statusCode, 200, reason: renamed.body);
      expect(locator.byId('m-2')!.name, 'gpt-z');

      final sameName = await update(token, 'm-2', {
        'name': 'gpt-z',
        'description': 'only description',
      });
      expect(sameName.statusCode, 200, reason: sameName.body);
      expect(locator.byId('m-2')!.description, 'only description');
    });

    test('PUT 可以改成其他应用已使用的 name', () async {
      final tokenA = await registerBundle('com.example.a');
      final tokenB = await registerBundle('com.example.b');
      expect(
        (await register(tokenA, chatBody('a-1', 'gpt-x'))).statusCode,
        200,
      );
      expect(
        (await register(tokenB, chatBody('b-1', 'gpt-y'))).statusCode,
        200,
      );

      final response = await update(tokenB, 'b-1', {'name': 'gpt-x'});
      expect(response.statusCode, 200, reason: response.body);
      expect(locator.byId('b-1')!.name, 'gpt-x');
    });

    test('已禁用的模型仍占用名称', () async {
      final token = await registerBundle('com.example.a');
      expect((await register(token, chatBody('m-1', 'gpt-x'))).statusCode, 200);
      expect((await toggle(token, 'm-1')).statusCode, 200);
      expect(locator.byId('m-1')!.isDisabled, isTrue);

      expect((await register(token, chatBody('m-2', 'gpt-x'))).statusCode, 409);
      expect(locator.appModels, hasLength(1));
    });

    test('注销后名称可以被复用', () async {
      final token = await registerBundle('com.example.a');
      expect((await register(token, chatBody('m-1', 'gpt-x'))).statusCode, 200);
      expect((await unregister(token, 'm-1')).statusCode, 200);

      final reuse = await register(token, chatBody('m-2', 'gpt-x'));
      expect(reuse.statusCode, 200, reason: reuse.body);
      expect(locator.appModels.map((m) => m.id), ['m-2']);
    });

    test('同一应用并发注册同名但不同 id：恰好一个成功、一个 409', () async {
      final token = await registerBundle('com.example.a');

      final responses = await Future.wait([
        register(token, chatBody('m-1', 'gpt-x')),
        register(token, chatBody('m-2', 'gpt-x')),
        register(token, chatBody('m-3', 'gpt-x')),
      ]);
      expect(responses.map((r) => r.statusCode).toList()..sort(), [
        200,
        409,
        409,
      ]);
      expect(locator.appModels.where((m) => m.name == 'gpt-x'), hasLength(1));
    });

    test('name 前后空白会被 trim 后再比较', () async {
      final token = await registerBundle('com.example.a');
      expect(
        (await register(token, chatBody('m-1', '  gpt-x  '))).statusCode,
        200,
      );
      expect(locator.byId('m-1')!.name, 'gpt-x');

      expect((await register(token, chatBody('m-2', 'gpt-x'))).statusCode, 409);
    });

    test('name 区分大小写：仅大小写不同视为不同名称', () async {
      final token = await registerBundle('com.example.a');
      expect((await register(token, chatBody('m-1', 'GPT-X'))).statusCode, 200);
      expect((await register(token, chatBody('m-2', 'gpt-x'))).statusCode, 200);
      expect(locator.appModels, hasLength(2));
    });

    test('历史遗留的同名数据不会被锁死：名称未变化时仍可更新与重新注册', () async {
      final token = await registerBundle('com.example.a');
      // 绕过 API 直接写入两条同名数据，模拟引入该约束之前遗留的记录。
      for (final id in ['legacy-1', 'legacy-2']) {
        await locator.addAppModel(
          AppModelData(
            id: id,
            name: 'legacy-name',
            baseUrl: 'http://127.0.0.1:1',
            appBundleId: 'com.example.a',
            appName: 'A',
          ),
        );
      }

      final updated = await update(token, 'legacy-1', {
        'description': 'still editable',
      });
      expect(updated.statusCode, 200, reason: updated.body);
      expect(locator.byId('legacy-1')!.description, 'still editable');

      final reregistered = await register(
        token,
        chatBody('legacy-2', 'legacy-name'),
      );
      expect(reregistered.statusCode, 200, reason: reregistered.body);

      // 但新增第三条同名记录仍被拒绝。
      expect(
        (await register(token, chatBody('legacy-3', 'legacy-name'))).statusCode,
        409,
      );
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
          // 对外 id 是 qualifiedId：localId@bundleId。
          (m) => m['id'] == 'dec-1@com.example.a',
        );
        expect(decision['task'], 'decision');
        expect(decision['output'], ['decisions']);
        expect(decision['isAppModel'], isTrue);
        expect(decision['appBundleId'], 'com.example.a');
        expect(decision['isRemote'], isTrue);
        // 应用模型同样是 isRemote=true、isCustom=false，必须由 source 与平台模型区分。
        expect(decision['isCustom'], isFalse);
        expect(decision['source'], 'app');
        expect(decision['appName'], 'com.example.a');

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
            'model': 'dec-1@com.example.a',
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

  group('命名空间 id（localId@bundleId）', () {
    Map<String, dynamic> chatBody(String id, String name) => {
      'id': id,
      'name': name,
      'baseUrl': 'http://127.0.0.1:1',
    };

    /// 启动一个记录“被命中次数”的 decision upstream，返回 server 与命中计数器。
    Future<(HttpServer, List<String>)> startUpstream(String tag) async {
      final hits = <String>[];
      final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => upstream.close(force: true));
      upstream.listen((request) async {
        await utf8.decoder.bind(request).join();
        hits.add(tag);
        request.response
          ..statusCode = 200
          ..headers.set('content-type', 'application/json')
          ..write(
            jsonEncode({
              'decisions': [
                {'id': tag},
              ],
            }),
          );
        await request.response.close();
      });
      return (upstream, hits);
    }

    Future<Response> callDecision(String model) => post(
      Uri.parse('$host/modelkit/decision'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({
        'model': model,
        'input': 'pick one',
        'options': ['a', 'b'],
      }),
    );

    test('注册响应与 GET /app-models 同时返回 localId（id）和 qualifiedId', () async {
      final token = await registerBundle('com.example.a');
      final registered = await register(token, decisionBody());
      expect(registered.statusCode, 200, reason: registered.body);
      expect(_asMap(registered)['id'], 'dec-1');
      expect(_asMap(registered)['qualifiedId'], 'dec-1@com.example.a');

      final list =
          _decode(await get(Uri.parse('$host/modelkit/app-models')))
              as List<dynamic>;
      final entry = (list.single as Map<String, dynamic>);
      expect(entry['id'], 'dec-1');
      expect(entry['qualifiedId'], 'dec-1@com.example.a');
    });

    test('不同 bundle 的同名 localId 在 /modelkit/models 里是两个不同的 id', () async {
      final tokenA = await registerBundle('com.example.a');
      final tokenB = await registerBundle('com.example.b');
      expect((await register(tokenA, decisionBody())).statusCode, 200);
      expect((await register(tokenB, decisionBody())).statusCode, 200);

      final models =
          (_decode(await get(Uri.parse('$host/modelkit/models')))
                  as List<dynamic>)
              .cast<Map<String, dynamic>>();
      expect(models.map((m) => m['id']).toSet(), {
        'dec-1@com.example.a',
        'dec-1@com.example.b',
      });
      expect(models.map((m) => m['source']), everyElement('app'));
    });

    test('PUT / toggle / DELETE 只作用于调用方命名空间内的同名 localId', () async {
      final tokenA = await registerBundle('com.example.a');
      final tokenB = await registerBundle('com.example.b');
      expect((await register(tokenA, decisionBody())).statusCode, 200);
      expect((await register(tokenB, decisionBody())).statusCode, 200);

      expect(
        (await update(tokenB, 'dec-1', {'description': 'b only'})).statusCode,
        200,
      );
      expect(locator.byQualifiedId('dec-1@com.example.a')!.description, '');
      expect(
        locator.byQualifiedId('dec-1@com.example.b')!.description,
        'b only',
      );

      expect((await toggle(tokenB, 'dec-1')).statusCode, 200);
      expect(locator.byQualifiedId('dec-1@com.example.a')!.isDisabled, isFalse);
      expect(locator.byQualifiedId('dec-1@com.example.b')!.isDisabled, isTrue);

      expect((await unregister(tokenA, 'dec-1')).statusCode, 200);
      expect(locator.byQualifiedId('dec-1@com.example.a'), isNull);
      expect(locator.byQualifiedId('dec-1@com.example.b'), isNotNull);
    });

    test('localId 不符合 [A-Za-z0-9._-]{1,64} 时返回 400，且不会写入', () async {
      final token = await registerBundle('com.example.a');

      for (final bad in ['has space', 'a@b', 'a(b)', 'a/b', '中文', 'x' * 65]) {
        final response = await register(token, decisionBody(id: bad));
        expect(response.statusCode, 400, reason: 'id "$bad"');
        expect(_asMap(response)['error'], contains('[A-Za-z0-9._-]'));
      }
      expect(locator.appModels, isEmpty);

      // 边界：64 个字符与全部允许的符号可以注册（name 各不相同，避免触发同应用重名）。
      for (final good in ['x' * 64, 'A.b_c-1']) {
        final response = await register(token, chatBody(good, 'name-$good'));
        expect(response.statusCode, 200, reason: 'id "$good"');
      }
      expect(locator.appModels, hasLength(2));
    });

    test('bundleId 不符合 [A-Za-z0-9._-]{1,128} 时注册模型返回 400，且不会写入', () async {
      for (final bundle in ['com.example@a', 'com example', 'x' * 129]) {
        final token = await registerBundle(bundle);
        final response = await register(token, decisionBody());
        expect(response.statusCode, 400, reason: 'bundleId "$bundle"');
        expect(_asMap(response)['error'], contains('bundleId'));
      }
      expect(locator.appModels, isEmpty);

      // 边界：128 个字符的 bundleId 可以注册。
      final token = await registerBundle('x' * 128);
      expect((await register(token, decisionBody())).statusCode, 200);
    });

    test('按 qualifiedId 精确路由到各自 bundle 的 upstream', () async {
      final (upstreamA, hitsA) = await startUpstream('A');
      final (upstreamB, hitsB) = await startUpstream('B');
      final tokenA = await registerBundle('com.example.a');
      final tokenB = await registerBundle('com.example.b');
      expect(
        (await register(tokenA, {
          ...decisionBody(),
          'baseUrl': 'http://127.0.0.1:${upstreamA.port}',
        })).statusCode,
        200,
      );
      expect(
        (await register(tokenB, {
          ...decisionBody(),
          'baseUrl': 'http://127.0.0.1:${upstreamB.port}',
        })).statusCode,
        200,
      );

      final toB = await callDecision('dec-1@com.example.b');
      expect(toB.statusCode, 200, reason: toB.body);
      expect(hitsB, ['B']);
      expect(hitsA, isEmpty);

      final toA = await callDecision('dec-1@com.example.a');
      expect(toA.statusCode, 200, reason: toA.body);
      expect(hitsA, ['A']);
      expect(hitsB, ['B']);
    });

    test('裸 localId 兜底：只有一个 bundle 使用时仍可解析（兼容旧调用方）', () async {
      final (upstream, hits) = await startUpstream('A');
      final token = await registerBundle('com.example.a');
      expect(
        (await register(token, {
          ...decisionBody(),
          'baseUrl': 'http://127.0.0.1:${upstream.port}',
        })).statusCode,
        200,
      );

      final response = await callDecision('dec-1');
      expect(response.statusCode, 200, reason: response.body);
      expect(hits, ['A']);
    });

    test('裸 localId 被多个 bundle 使用时无法判定目标，不会随便挑一个转发', () async {
      final (upstreamA, hitsA) = await startUpstream('A');
      final (upstreamB, hitsB) = await startUpstream('B');
      final tokenA = await registerBundle('com.example.a');
      final tokenB = await registerBundle('com.example.b');
      for (final (token, upstream) in [
        (tokenA, upstreamA),
        (tokenB, upstreamB),
      ]) {
        expect(
          (await register(token, {
            ...decisionBody(),
            'baseUrl': 'http://127.0.0.1:${upstream.port}',
          })).statusCode,
          200,
        );
      }

      final response = await callDecision('dec-1');
      expect(response.statusCode, isNot(200), reason: response.body);
      expect(hitsA, isEmpty);
      expect(hitsB, isEmpty);
    });

    test('/chat/models：菜单标签冲突的模型回退为真实 id，不冲突的保持标签', () async {
      final tokenA = await registerBundle('com.example.a');
      final tokenB = await registerBundle('com.example.b');
      expect(
        (await register(tokenA, chatBody('m-1', 'gpt-x'))).statusCode,
        200,
      );
      expect(
        (await register(tokenB, chatBody('m-1', 'gpt-x'))).statusCode,
        200,
      );
      expect(
        (await register(tokenA, chatBody('m-2', 'gpt-y'))).statusCode,
        200,
      );

      final chatList = _asMap(
        await get(Uri.parse('$host/modelkit/chat/models')),
      );
      final ids = (chatList['data'] as List)
          .cast<Map<String, dynamic>>()
          .map((m) => m['id'])
          .toList();
      expect(ids, hasLength(3));
      expect(ids, containsAll(['m-1@com.example.a', 'm-1@com.example.b']));
      expect(ids, contains('gpt-y'));
      expect(ids, isNot(contains('gpt-x')));
    });
  });
}
