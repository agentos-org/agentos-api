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

/// 应用模型：id 是网关由 `bundleId + key` 生成的 hashid（key 即注册时的 name）。
LlmModelInfo _app(
  String key,
  String bundleId, {
  String name = '',
  String alias = '',
}) {
  return LlmModelInfo(
    id: AppModelId.generate(bundleId: bundleId, name: key),
    name: name.isEmpty ? 'name-of-$key' : name,
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

  group('resolveModelIdentifier：分层解析', () {
    test('精确 id 命中，且没有告警', () {
      final target = _app('chat-1', 'com.example.a');
      final result = resolveModelIdentifier([
        _firstParty('aaaaaaaaaaaa', name: 'gpt'),
        target,
      ], target.id);
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

    test('应用模型的 id 是 12 位 hashid，按 id 精确命中', () {
      final app = _app('chat-1', 'com.example.a', name: 'upstream');
      expect(app.id, matches(RegExp(r'^[0-9a-f]{12}$')));
      expect(resolveModelIdentifier([app], app.id).model, same(app));
    });

    test('同名模型在不同应用下 hashid 不同，按 hashid 各自精确命中', () {
      final a = _app('shared', 'com.example.a');
      final b = _app('shared', 'com.example.b');
      expect(a.id, isNot(b.id));
      expect(resolveModelIdentifier([a, b], a.id).model, same(a));
      expect(resolveModelIdentifier([a, b], b.id).model, same(b));
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

    test('应用模型按 hashid 精确命中', () {
      final app = _app('chat-1', 'com.example.a');
      final hit = resolveModelId([app], app.id);
      expect(hit.model, same(app));
      expect(hit.warnings, isEmpty);
      expect(resolveModelId([app], 'missing').model, isNull);
    });

    test('空 id 不命中', () {
      expect(resolveModelId([_firstParty('aaaaaaaaaaaa')], '').model, isNull);
    });
  });
}
