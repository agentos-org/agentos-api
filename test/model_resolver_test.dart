import 'package:agentos_api/agentos_api.dart';
import 'package:test/test.dart';

LlmModelInfo _firstParty(
  String id, {
  String name = '',
  String alias = '',
  bool custom = false,
}) {
  return LlmModelInfo(
    id: id,
    name: name.isEmpty ? 'name-of-$id' : name,
    alias: alias,
    description: '',
    parameters: '',
    paramsB: 0,
    quantization: '',
    sizeGB: 0,
    minRAMGB: 0,
    downloadUrl: '',
    tags: const [],
    repoId: '',
    type: 'textGeneration',
    baseUrl: 'https://upstream.example.test/v1',
    isCustom: custom,
  );
}

LlmModelInfo _app(
  String localId,
  String bundleId, {
  String name = '',
  String alias = '',
}) {
  return LlmModelInfo(
    id: AppModelId.qualify(bundleId: bundleId, localId: localId),
    name: name.isEmpty ? 'name-of-$localId' : name,
    alias: alias,
    description: '',
    parameters: '',
    paramsB: 0,
    quantization: '',
    sizeGB: 0,
    minRAMGB: 0,
    downloadUrl: '',
    tags: const [],
    repoId: '',
    type: 'textGeneration',
    baseUrl: 'https://app.example.test/v1',
    isAppModel: true,
    appBundleId: bundleId,
  );
}

void main() {
  group('modelIdentifierCandidates', () {
    test('普通标识只有它自己；空白与空串没有候选', () {
      expect(modelIdentifierCandidates(' gpt-4o '), ['gpt-4o']);
      expect(modelIdentifierCandidates(''), isEmpty);
      expect(modelIdentifierCandidates('   '), isEmpty);
    });

    test('菜单标签 alias (name) 依次展开为 原文、name、alias', () {
      expect(modelIdentifierCandidates('Fast (gpt-4o)'), [
        'Fast (gpt-4o)',
        'gpt-4o',
        'Fast',
      ]);
    });

    test('括号在开头时不是标签格式，不拆分', () {
      expect(modelIdentifierCandidates('(abc)'), ['(abc)']);
    });
  });

  group('appLocalIdOf', () {
    test('应用模型取出 localId；第一方与非 qualified 形态返回 null', () {
      expect(appLocalIdOf(_app('chat-1', 'com.example.a')), 'chat-1');
      expect(appLocalIdOf(_firstParty('abc123def456')), isNull);

      final legacy = LlmModelInfo(
        id: 'bare-id',
        name: 'n',
        alias: '',
        description: '',
        parameters: '',
        paramsB: 0,
        quantization: '',
        sizeGB: 0,
        minRAMGB: 0,
        downloadUrl: '',
        tags: const [],
        repoId: '',
        type: 'textGeneration',
        isAppModel: true,
        appBundleId: 'com.example.a',
      );
      expect(appLocalIdOf(legacy), isNull);
    });
  });

  group('resolveModelIdentifier：分层解析', () {
    test('精确 id 命中，且没有告警', () {
      final target = _app('chat-1', 'com.example.a');
      final result = resolveModelIdentifier([
        _firstParty('aaaaaaaaaaaa', name: 'gpt'),
        target,
      ], 'chat-1@com.example.a');
      expect(result.model, same(target));
      expect(result.warnings, isEmpty);
    });

    test('找不到时返回 null 且 found 为 false', () {
      final result = resolveModelIdentifier([
        _firstParty('aaaaaaaaaaaa', name: 'gpt'),
      ], 'missing');
      expect(result.found, isFalse);
      expect(result.model, isNull);
    });

    test('id 优先于任何模型的 alias / name', () {
      final byId = _firstParty('target0000000', name: 'something-else');
      final byName = _firstParty('other1111111', name: 'target0000000');
      final result = resolveModelIdentifier([byName, byId], 'target0000000');
      expect(result.model, same(byId));
    });

    test('应用把 alias 设成第一方的 name，按 name 寻址仍然命中第一方（alias 劫持）', () {
      final platform = _firstParty('aaaaaaaaaaaa', name: 'gpt-4o');
      final hijacker = _app('evil', 'com.example.evil', alias: 'gpt-4o');
      // 即使应用模型排在前面，也不能压过第一方。
      for (final models in [
        [platform, hijacker],
        [hijacker, platform],
      ]) {
        final result = resolveModelIdentifier(models, 'gpt-4o');
        expect(result.model, same(platform));
      }
    });

    test('应用把 name 设成第一方的 alias，仍然命中第一方', () {
      final platform = _firstParty('aaaaaaaaaaaa', name: 'real', alias: 'fast');
      final hijacker = _app('evil', 'com.example.evil', name: 'fast');
      final result = resolveModelIdentifier([hijacker, platform], 'fast');
      expect(result.model, same(platform));
    });

    test('应用的裸 localId 等于第一方的 name 时，第一方优先（id 劫持）', () {
      final platform = _firstParty('aaaaaaaaaaaa', name: 'gpt-4o');
      final hijacker = _app('gpt-4o', 'com.example.evil');
      final result = resolveModelIdentifier([hijacker, platform], 'gpt-4o');
      expect(result.model, same(platform));
    });

    test('没有第一方匹配时，裸 localId 唯一则命中，并给出弃用告警', () {
      final app = _app('legacy-id', 'com.example.a', name: 'upstream');
      final result = resolveModelIdentifier([
        _firstParty('aaaaaaaaaaaa', name: 'gpt'),
        app,
      ], 'legacy-id');
      expect(result.model, same(app));
      expect(result.warnings, hasLength(1));
      expect(result.warnings.single, contains('弃用'));
      expect(result.warnings.single, contains('legacy-id@com.example.a'));
    });

    test('多个应用共用同一个 localId 时，裸 id 无法判定目标：不命中并给出提示', () {
      final result = resolveModelIdentifier([
        _app('shared', 'com.example.a'),
        _app('shared', 'com.example.b'),
      ], 'shared');
      expect(result.model, isNull);
      expect(result.warnings, hasLength(1));
      expect(result.warnings.single, contains('shared@com.example.a'));
      expect(result.warnings.single, contains('shared@com.example.b'));
    });

    test('裸 localId 不唯一时，仍可继续按应用 name 命中', () {
      final a = _app('shared', 'com.example.a', name: 'shared');
      final result = resolveModelIdentifier([
        a,
        _app('shared', 'com.example.b', name: 'other'),
      ], 'shared');
      // 两个应用的 localId 都是 shared（歧义），退到应用 name 层后只有 a 的 name 是 shared。
      expect(result.model, same(a));
    });

    test('没有第一方匹配时，应用 alias 再 name 依次生效', () {
      final byAlias = _app(
        'a-1',
        'com.example.a',
        name: 'x',
        alias: 'friendly',
      );
      final byName = _app('b-1', 'com.example.b', name: 'friendly');
      expect(
        resolveModelIdentifier([byName, byAlias], 'friendly').model,
        same(byAlias),
      );
      expect(resolveModelIdentifier([byName], 'friendly').model, same(byName));
    });

    test('第一方内 alias 先于 name', () {
      final byName = _firstParty('aaaaaaaaaaaa', name: 'shared');
      final byAlias = _firstParty(
        'bbbbbbbbbbbb',
        name: 'other',
        alias: 'shared',
      );
      final result = resolveModelIdentifier([byName, byAlias], 'shared');
      expect(result.model, same(byAlias));
    });

    test('同一层级匹配到多个模型时取列表第一个，并在告警里列出全部候选 id', () {
      final first = _firstParty('aaaaaaaaaaaa', name: 'gpt-oss-20b');
      final second = _firstParty('bbbbbbbbbbbb', name: 'gpt-oss-20b');
      final third = _firstParty('cccccccccccc', name: 'gpt-oss-20b');
      final result = resolveModelIdentifier([
        first,
        second,
        third,
      ], 'gpt-oss-20b');
      expect(result.model, same(first));
      expect(result.warnings, hasLength(1));
      for (final id in ['aaaaaaaaaaaa', 'bbbbbbbbbbbb', 'cccccccccccc']) {
        expect(result.warnings.single, contains(id));
      }
    });

    test('菜单标签 alias (name) 能解析到对应模型', () {
      final platform = _firstParty(
        'aaaaaaaaaaaa',
        name: 'gpt-4o',
        alias: 'Fast',
      );
      final result = resolveModelIdentifier([platform], 'Fast (gpt-4o)');
      expect(result.model, same(platform));
    });

    test('alias 为空的模型不会被空候选或空 alias 误匹配', () {
      final platform = _firstParty('aaaaaaaaaaaa', name: 'gpt', alias: '');
      expect(resolveModelIdentifier([platform], '').model, isNull);
      expect(resolveModelIdentifier([platform], ' ').model, isNull);
    });
  });

  group('resolveModelId：只按 id 解析', () {
    test('精确 id 命中', () {
      final target = _firstParty('aaaaaaaaaaaa');
      expect(resolveModelId([target], 'aaaaaaaaaaaa').model, same(target));
    });

    test('不会按 alias / name 匹配', () {
      final platform = _firstParty(
        'aaaaaaaaaaaa',
        name: 'gpt-4o',
        alias: 'fast',
      );
      expect(resolveModelId([platform], 'gpt-4o').model, isNull);
      expect(resolveModelId([platform], 'fast').model, isNull);
    });

    test('兼容唯一的应用裸 localId（并告警），歧义时不命中', () {
      final app = _app('legacy-id', 'com.example.a');
      final hit = resolveModelId([app], 'legacy-id');
      expect(hit.model, same(app));
      expect(hit.warnings, isNotEmpty);

      final miss = resolveModelId([
        app,
        _app('legacy-id', 'com.example.b'),
      ], 'legacy-id');
      expect(miss.model, isNull);
      expect(miss.warnings, isNotEmpty);
    });

    test('空 id 不命中', () {
      expect(resolveModelId([_firstParty('aaaaaaaaaaaa')], '').model, isNull);
    });
  });
}
