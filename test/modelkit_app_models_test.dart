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
/// 窗口，用于验证 controller 对并发同名写入的串行化。
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
          // 与真实 locator 一致：对外 id 就是网关生成的 hashid。
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

  /// 按 hashid 取模型。
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

const _bundleA = 'com.example.a';
const _bundleB = 'com.example.b';

/// 网关为 (bundleId, name) 生成的 hashid。
String _idOf(String bundleId, String name) =>
    AppModelId.generate(bundleId: bundleId, name: name);

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

  /// 注册并断言成功，返回网关生成的 hashid。
  Future<String> registerOk(String token, Map<String, dynamic> body) async {
    final response = await register(token, body);
    expect(response.statusCode, 200, reason: response.body);
    return _asMap(response)['id'] as String;
  }

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

  Map<String, dynamic> decisionBody({String name = 'qwen-decision'}) => {
    'name': name,
    'task': 'decision',
    'baseUrl': 'http://127.0.0.1:1',
  };

  Map<String, dynamic> chatBody(String name) => {
    'name': name,
    'baseUrl': 'http://127.0.0.1:1',
  };

  group('认证', () {
    test('写接口缺少或使用无效 token 时返回 401，且不会写入任何数据', () async {
      final bogus = <String, String>{
        'content-type': 'application/json',
        'authorization': 'Bearer sk-not-issued',
      };
      final noAuth = <String, String>{'content-type': 'application/json'};
      final id = _idOf(_bundleA, 'qwen-decision');

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
            Uri.parse('$host/modelkit/app-models/$id'),
            headers: headers,
            body: jsonEncode({'name': 'x'}),
          )).statusCode,
          401,
        );
        expect(
          (await delete(
            Uri.parse('$host/modelkit/app-models/$id'),
            headers: headers,
          )).statusCode,
          401,
        );
        expect(
          (await post(
            Uri.parse('$host/modelkit/app-models/$id/toggle'),
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
      final token = await registerBundle(_bundleA, base: bareHost);

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
      final token = await registerBundle(_bundleA);

      final response = await register(token, decisionBody());
      expect(response.statusCode, 200, reason: response.body);
      expect(_asMap(response), {
        'success': true,
        'id': _idOf(_bundleA, 'qwen-decision'),
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
      expect(model['appBundleId'], _bundleA);
      expect(model['appName'], _bundleA);
    });

    test('别名 task 与不合规的输入/输出/能力位会被归一化', () async {
      final token = await registerBundle(_bundleA);

      final id = await registerOk(token, {
        ...decisionBody(),
        'task': 'SystemOne',
        'input': ['decisions', 'audio', 'image', 'text'],
        'output': ['text'],
        'capabilities': {'stream': true, 'tool_call': true, 'reasoning': true},
      });

      final model = locator.byId(id)!;
      expect(model.task, 'decision');
      expect(model.inputModalities, ['text', 'image']);
      expect(model.outputModalities, ['decisions']);
      expect(
        [model.stream, model.toolCall, model.reasoning],
        [false, false, false],
      );
    });

    test('未知 task 返回 400；缺省 task 视为 chat 并沿用 chat 默认值', () async {
      final token = await registerBundle(_bundleA);

      final bad = await register(token, {...decisionBody(), 'task': 'vision'});
      expect(bad.statusCode, 400);
      expect(_asMap(bad)['error'], contains('decision'));
      expect(locator.appModels, isEmpty);

      final id = await registerOk(token, chatBody('gpt'));
      final chat = locator.byId(id)!;
      expect(chat.task, 'chat');
      expect(chat.inputModalities, ['text']);
      expect(chat.outputModalities, ['text']);
      expect([chat.stream, chat.toolCall, chat.reasoning], [true, false, true]);
    });

    test('非 decision 任务不接受 decisions 模态，缺省回退到该任务的默认值', () async {
      final token = await registerBundle(_bundleA);

      final id = await registerOk(token, {
        ...chatBody('gpt'),
        'input': ['text', 'decisions'],
        'output': ['decisions'],
      });

      final chat = locator.byId(id)!;
      expect(chat.inputModalities, ['text']);
      expect(chat.outputModalities, ['text']);
    });

    test('缺少 name 或 name 为空白时返回 400，且不会写入', () async {
      final token = await registerBundle(_bundleA);

      for (final body in <Map<String, dynamic>>[
        {'baseUrl': 'http://127.0.0.1:1'},
        {...decisionBody(name: '')},
        {...decisionBody(name: '   ')},
      ]) {
        final response = await register(token, body);
        expect(response.statusCode, 400, reason: '$body -> ${response.body}');
        expect(_asMap(response)['error'], contains('name'));
      }
      expect(locator.appModels, isEmpty);
    });

    test('请求体类型错误返回 400，而不是 500', () async {
      final token = await registerBundle(_bundleA);

      for (final body in <Map<String, dynamic>>[
        {...decisionBody(), 'name': 123},
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
      final token = await registerBundle(_bundleA);

      final id = await registerOk(token, {
        ...decisionBody(),
        'appName': '我的应用',
        'description': '中文描述',
      });

      final model = locator.byId(id)!;
      expect(model.appName, '我的应用');
      expect(model.description, '中文描述');
    });
  });

  group('hashid', () {
    test('注册响应返回由 bundleId + name 生成的 12 位 hashid，各接口使用同一个 id', () async {
      final token = await registerBundle(_bundleA);
      final id = await registerOk(token, decisionBody());

      expect(id, _idOf(_bundleA, 'qwen-decision'));
      expect(id, matches(RegExp(r'^[0-9a-f]{12}$')));

      final appModels =
          (_decode(await get(Uri.parse('$host/modelkit/app-models')))
                  as List<dynamic>)
              .cast<Map<String, dynamic>>();
      expect(appModels.single['id'], id);

      final models =
          (_decode(await get(Uri.parse('$host/modelkit/models')))
                  as List<dynamic>)
              .cast<Map<String, dynamic>>();
      expect(models.single['id'], id);
      expect(models.single['source'], 'app');
    });

    test('同一应用同名重复注册得到同一个 hashid：整体替换，保留禁用状态，不产生重复条目', () async {
      final token = await registerBundle(_bundleA);
      final id = await registerOk(token, decisionBody());
      expect((await toggle(token, id)).statusCode, 200);

      final again = await register(token, {
        ...decisionBody(),
        'description': 'refreshed',
      });
      expect(again.statusCode, 200, reason: again.body);
      expect(_asMap(again), {'success': true, 'id': id, 'updated': true});

      expect(locator.appModels, hasLength(1));
      final model = locator.byId(id)!;
      expect(model.description, 'refreshed');
      expect(model.isDisabled, isTrue);
    });

    test('不同应用注册同名模型得到不同的 hashid，互不影响', () async {
      final tokenA = await registerBundle(_bundleA);
      final tokenB = await registerBundle(_bundleB);
      final idA = await registerOk(tokenA, decisionBody());

      final other = await register(tokenB, decisionBody());
      expect(other.statusCode, 200, reason: other.body);
      expect(_asMap(other)['updated'], isNull);
      final idB = _asMap(other)['id'] as String;

      expect(idA, isNot(idB));
      expect(idB, _idOf(_bundleB, 'qwen-decision'));
      expect(locator.appModels, hasLength(2));
      expect(locator.byId(idA)!.appBundleId, _bundleA);
      expect(locator.byId(idB)!.appBundleId, _bundleB);
    });

    test('并发的同名注册只会留下一条记录，且得到同一个 id', () async {
      final token = await registerBundle(_bundleA);

      final responses = await Future.wait([
        for (var i = 0; i < 5; i++)
          register(token, {...decisionBody(), 'description': 'v$i'}),
      ]);
      expect(responses.map((r) => r.statusCode), everyElement(200));
      expect(responses.map((r) => _asMap(r)['id']).toSet(), {
        _idOf(_bundleA, 'qwen-decision'),
      });
      expect(
        responses.where((r) => _asMap(r)['updated'] == true),
        hasLength(4),
      );
      expect(locator.appModels, hasLength(1));
    });

    test('两个应用并发注册同名模型：都成功，各留一条', () async {
      final tokenA = await registerBundle(_bundleA);
      final tokenB = await registerBundle(_bundleB);

      final responses = await Future.wait([
        register(tokenA, decisionBody()),
        register(tokenB, decisionBody()),
      ]);
      expect(responses.map((r) => r.statusCode), everyElement(200));
      expect(locator.appModels.map((m) => m.id).toSet(), {
        _idOf(_bundleA, 'qwen-decision'),
        _idOf(_bundleB, 'qwen-decision'),
      });
    });

    test('注销后重新注册同名模型，得到同一个 hashid', () async {
      final token = await registerBundle(_bundleA);
      final id = await registerOk(token, chatBody('gpt-x'));
      expect((await unregister(token, id)).statusCode, 200);
      expect(locator.appModels, isEmpty);

      final again = await register(token, chatBody('gpt-x'));
      expect(again.statusCode, 200, reason: again.body);
      expect(_asMap(again), {'success': true, 'id': id});
      expect(locator.appModels, hasLength(1));
    });

    test('改名后 id 保持不变；再用旧 name 注册会因 hashid 仍被占用返回 409', () async {
      final token = await registerBundle(_bundleA);
      final id = await registerOk(token, chatBody('gpt-old'));

      expect((await update(token, id, {'name': 'gpt-new'})).statusCode, 200);
      expect(locator.byId(id)!.name, 'gpt-new');

      final conflict = await register(token, chatBody('gpt-old'));
      expect(conflict.statusCode, 409);
      final error = _asMap(conflict)['error'] as String;
      expect(error, contains(id));
      expect(error, contains('gpt-new'));
      expect(locator.appModels, hasLength(1));

      // 用新 name 注册命中的是同一条记录，id 不变。
      final again = await register(token, chatBody('gpt-new'));
      expect(again.statusCode, 200, reason: again.body);
      expect(_asMap(again), {'success': true, 'id': id, 'updated': true});
      expect(locator.appModels, hasLength(1));
    });
  });

  group('归属校验', () {
    test('appBundleId 可省略；与 token 不一致时返回 403', () async {
      final token = await registerBundle(_bundleA);

      final spoofed = await register(token, {
        ...decisionBody(),
        'appBundleId': _bundleB,
      });
      expect(spoofed.statusCode, 403);
      expect(locator.appModels, isEmpty);

      final matching = await register(token, {
        ...decisionBody(),
        'appBundleId': _bundleA,
      });
      expect(matching.statusCode, 200, reason: matching.body);
      expect(
        locator.byId(_asMap(matching)['id'] as String)!.appBundleId,
        _bundleA,
      );
    });

    test('其他调用方不能修改、删除或切换别人的模型（别人的 hashid 对自己不可见 → 404）', () async {
      final tokenA = await registerBundle(_bundleA);
      final tokenB = await registerBundle(_bundleB);
      final id = await registerOk(tokenA, decisionBody());

      expect((await update(tokenB, id, {'name': 'hijacked'})).statusCode, 404);
      expect((await unregister(tokenB, id)).statusCode, 404);
      expect((await toggle(tokenB, id)).statusCode, 404);

      final model = locator.byId(id)!;
      expect(model.name, 'qwen-decision');
      expect(model.isDisabled, isFalse);
      expect(model.appBundleId, _bundleA);

      // 所属方仍然可以操作。
      expect((await toggle(tokenA, id)).statusCode, 200);
      expect(locator.byId(id)!.isDisabled, isTrue);
      expect((await unregister(tokenA, id)).statusCode, 200);
      expect(locator.appModels, isEmpty);
    });

    test('未知 id 返回 404', () async {
      final token = await registerBundle(_bundleA);

      expect((await update(token, 'missing', {'name': 'x'})).statusCode, 404);
      expect((await unregister(token, 'missing')).statusCode, 404);
      expect((await toggle(token, 'missing')).statusCode, 404);
    });

    test('PUT / toggle / DELETE 只作用于调用方自己 hashid 对应的模型', () async {
      final tokenA = await registerBundle(_bundleA);
      final tokenB = await registerBundle(_bundleB);
      final idA = await registerOk(tokenA, decisionBody());
      final idB = await registerOk(tokenB, decisionBody());

      expect(
        (await update(tokenB, idB, {'description': 'b only'})).statusCode,
        200,
      );
      expect(locator.byId(idA)!.description, '');
      expect(locator.byId(idB)!.description, 'b only');

      expect((await toggle(tokenB, idB)).statusCode, 200);
      expect(locator.byId(idA)!.isDisabled, isFalse);
      expect(locator.byId(idB)!.isDisabled, isTrue);

      expect((await unregister(tokenA, idA)).statusCode, 200);
      expect(locator.byId(idA), isNull);
      expect(locator.byId(idB), isNotNull);
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
  });

  group('更新', () {
    test('PUT 是部分更新，且空 apiKey 不会清除已保存的密钥', () async {
      final token = await registerBundle(_bundleA);
      final id = await registerOk(token, {
        ...decisionBody(),
        'apiKey': 'sk-upstream',
        'description': 'before',
      });

      final response = await update(token, id, {
        'name': 'renamed',
        'apiKey': '',
      });
      expect(response.statusCode, 200, reason: response.body);

      final model = locator.byId(id)!;
      expect(model.name, 'renamed');
      expect(model.description, 'before');
      expect(model.apiKey, 'sk-upstream');
      expect(model.task, 'decision');
      expect(model.outputModalities, ['decisions']);
    });

    test('PUT 把 task 改成 decision 时，旧的模态与能力位会被重置', () async {
      final token = await registerBundle(_bundleA);
      final id = await registerOk(token, {
        'name': 'multi',
        'task': 'chat',
        'baseUrl': 'http://127.0.0.1:1',
        'input': ['text', 'image'],
        'capabilities': {'stream': true, 'tool_call': true, 'reasoning': true},
      });

      final response = await update(token, id, {'task': 'decision'});
      expect(response.statusCode, 200, reason: response.body);

      final model = locator.byId(id)!;
      expect(model.task, 'decision');
      expect(model.inputModalities, ['text']);
      expect(model.outputModalities, ['decisions']);
      expect(
        [model.stream, model.toolCall, model.reasoning],
        [false, false, false],
      );
    });

    test('PUT 带未知 task 或不同的 appBundleId 时返回 400', () async {
      final token = await registerBundle(_bundleA);
      final id = await registerOk(token, decisionBody());

      expect((await update(token, id, {'task': 'bogus'})).statusCode, 400);
      expect(
        (await update(token, id, {'appBundleId': _bundleB})).statusCode,
        400,
      );
      expect(locator.byId(id)!.task, 'decision');
      expect(locator.byId(id)!.appBundleId, _bundleA);
    });
  });

  group('同一应用下 name 唯一', () {
    test('PUT 改名为本应用已占用的 name 返回 409', () async {
      final token = await registerBundle(_bundleA);
      await registerOk(token, chatBody('gpt-x'));
      final id2 = await registerOk(token, chatBody('gpt-y'));

      final conflict = await update(token, id2, {'name': 'gpt-x'});
      expect(conflict.statusCode, 409);
      final error = _asMap(conflict)['error'] as String;
      // 冲突提示要能告诉调用方是哪个名称、与哪个已有 id 冲突。
      expect(error, contains('gpt-x'));
      expect(error, contains(_idOf(_bundleA, 'gpt-x')));
      expect(locator.byId(id2)!.name, 'gpt-y');

      // 改成未被占用的名称、或保持原名只改其他字段，都应成功。
      final renamed = await update(token, id2, {'name': 'gpt-z'});
      expect(renamed.statusCode, 200, reason: renamed.body);
      expect(locator.byId(id2)!.name, 'gpt-z');

      final sameName = await update(token, id2, {
        'name': 'gpt-z',
        'description': 'only description',
      });
      expect(sameName.statusCode, 200, reason: sameName.body);
      expect(locator.byId(id2)!.description, 'only description');
    });

    test('PUT 可以改成其他应用已使用的 name', () async {
      final tokenA = await registerBundle(_bundleA);
      final tokenB = await registerBundle(_bundleB);
      await registerOk(tokenA, chatBody('gpt-x'));
      final idB = await registerOk(tokenB, chatBody('gpt-y'));

      final response = await update(tokenB, idB, {'name': 'gpt-x'});
      expect(response.statusCode, 200, reason: response.body);
      expect(locator.byId(idB)!.name, 'gpt-x');
    });

    test('已禁用的模型仍占用名称', () async {
      final token = await registerBundle(_bundleA);
      final id1 = await registerOk(token, chatBody('gpt-x'));
      final id2 = await registerOk(token, chatBody('gpt-y'));
      expect((await toggle(token, id1)).statusCode, 200);
      expect(locator.byId(id1)!.isDisabled, isTrue);

      expect((await update(token, id2, {'name': 'gpt-x'})).statusCode, 409);
      expect(locator.byId(id2)!.name, 'gpt-y');
    });

    test('name 前后空白会被 trim：与不带空白的同名模型是同一个', () async {
      final token = await registerBundle(_bundleA);
      final id = await registerOk(token, chatBody('  gpt-x  '));
      expect(id, _idOf(_bundleA, 'gpt-x'));
      expect(locator.byId(id)!.name, 'gpt-x');

      final again = await register(token, chatBody('gpt-x'));
      expect(_asMap(again), {'success': true, 'id': id, 'updated': true});
      expect(locator.appModels, hasLength(1));
    });

    test('name 区分大小写：仅大小写不同视为不同模型', () async {
      final token = await registerBundle(_bundleA);
      final upper = await registerOk(token, chatBody('GPT-X'));
      final lower = await registerOk(token, chatBody('gpt-x'));
      expect(upper, isNot(lower));
      expect(locator.appModels, hasLength(2));
    });
  });

  group('接入 ModelKit', () {
    test(
      'decision app model 出现在 /modelkit/models，但不在 /modelkit/chat/models',
      () async {
        final token = await registerBundle(_bundleA);
        final decisionId = await registerOk(token, decisionBody());
        await registerOk(token, chatBody('gpt-chat'));

        final models =
            _decode(await get(Uri.parse('$host/modelkit/models')))
                as List<dynamic>;
        final decision = models.cast<Map<String, dynamic>>().singleWhere(
          // 对外 id 就是注册时返回的 hashid。
          (m) => m['id'] == decisionId,
        );
        expect(decision['task'], 'decision');
        expect(decision['output'], ['decisions']);
        expect(decision['isAppModel'], isTrue);
        expect(decision['appBundleId'], _bundleA);
        expect(decision['isRemote'], isTrue);
        // 应用模型同样是 isRemote=true、isCustom=false，必须由 source 与平台模型区分。
        expect(decision['isCustom'], isFalse);
        expect(decision['source'], 'app');
        expect(decision['appName'], _bundleA);

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

        final token = await registerBundle(_bundleA);
        final id = await registerOk(token, {
          ...decisionBody(),
          'baseUrl': 'http://127.0.0.1:${upstream.port}',
          'apiKey': 'sk-upstream',
        });

        final response = await post(
          Uri.parse('$host/modelkit/decision'),
          headers: {'content-type': 'application/json'},
          body: jsonEncode({
            'model': id,
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

    test('不同应用的同名模型在 /modelkit/models 里是两个不同的 id', () async {
      final tokenA = await registerBundle(_bundleA);
      final tokenB = await registerBundle(_bundleB);
      final idA = await registerOk(tokenA, decisionBody());
      final idB = await registerOk(tokenB, decisionBody());

      final models =
          (_decode(await get(Uri.parse('$host/modelkit/models')))
                  as List<dynamic>)
              .cast<Map<String, dynamic>>();
      expect(models.map((m) => m['id']).toSet(), {idA, idB});
      expect(models.map((m) => m['source']), everyElement('app'));
    });

    test('按 hashid 精确路由到各自应用的 upstream', () async {
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

      final (upstreamA, hitsA) = await startUpstream('A');
      final (upstreamB, hitsB) = await startUpstream('B');
      final tokenA = await registerBundle(_bundleA);
      final tokenB = await registerBundle(_bundleB);
      final idA = await registerOk(tokenA, {
        ...decisionBody(),
        'baseUrl': 'http://127.0.0.1:${upstreamA.port}',
      });
      final idB = await registerOk(tokenB, {
        ...decisionBody(),
        'baseUrl': 'http://127.0.0.1:${upstreamB.port}',
      });

      final toB = await callDecision(idB);
      expect(toB.statusCode, 200, reason: toB.body);
      expect(hitsB, ['B']);
      expect(hitsA, isEmpty);

      final toA = await callDecision(idA);
      expect(toA.statusCode, 200, reason: toA.body);
      expect(hitsA, ['A']);
      expect(hitsB, ['B']);
    });

    test('/chat/models：菜单标签冲突的模型回退为真实 id，不冲突的保持标签', () async {
      final tokenA = await registerBundle(_bundleA);
      final tokenB = await registerBundle(_bundleB);
      final idAX = await registerOk(tokenA, chatBody('gpt-x'));
      final idBX = await registerOk(tokenB, chatBody('gpt-x'));
      await registerOk(tokenA, chatBody('gpt-y'));

      final chatList = _asMap(
        await get(Uri.parse('$host/modelkit/chat/models')),
      );
      final ids = (chatList['data'] as List)
          .cast<Map<String, dynamic>>()
          .map((m) => m['id'])
          .toList();
      expect(ids, hasLength(3));
      expect(ids, containsAll([idAX, idBX]));
      expect(ids, contains('gpt-y'));
      expect(ids, isNot(contains('gpt-x')));
    });
  });
}
