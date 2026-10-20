import 'package:agentos_api/agentos_api.dart';
import 'package:test/test.dart';

LlmModelInfo _model(String id, {String name = 'n', bool app = false}) {
  return LlmModelInfo(
    id: id,
    name: name,
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
    baseUrl: 'https://upstream.example.test/v1',
    isAppModel: app,
    appBundleId: app ? 'com.example.a' : null,
  );
}

void main() {
  group('dedupeModelsById', () {
    test('没有重复时原样返回且没有冲突', () {
      final models = [_model('a'), _model('b'), _model('c', app: true)];
      final result = dedupeModelsById(models);
      expect(result.models, models);
      expect(result.conflicts, isEmpty);
    });

    test('第一方与应用模型 id 相同：保留第一方，丢弃应用模型（与输入顺序无关）', () {
      final firstParty = _model('dup', name: 'first-party');
      final app = _model('dup', name: 'app', app: true);
      for (final input in [
        [firstParty, app],
        [app, firstParty],
      ]) {
        final result = dedupeModelsById(input);
        expect(result.models, [firstParty]);
        expect(result.conflicts, hasLength(1));
        expect(result.conflicts.single.id, 'dup');
        expect(result.conflicts.single.kept, same(firstParty));
        expect(result.conflicts.single.dropped, same(app));
      }
    });

    test('同一层级内 id 相同：保留列表中先出现的', () {
      final first = _model('dup', name: 'first');
      final second = _model('dup', name: 'second');
      final result = dedupeModelsById([first, second]);
      expect(result.models, [first]);
      expect(result.conflicts.single.kept, same(first));
      expect(result.conflicts.single.dropped, same(second));
    });

    test('去重后保持其余模型的相对顺序', () {
      final a = _model('a');
      final dupApp = _model('b', app: true);
      final b = _model('b');
      final c = _model('c');
      final result = dedupeModelsById([a, dupApp, b, c]);
      expect(result.models, [a, b, c]);
    });

    test('三个以上同 id：只保留一个，其余都记为冲突', () {
      final models = [_model('x'), _model('x'), _model('x', app: true)];
      final result = dedupeModelsById(models);
      expect(result.models, hasLength(1));
      expect(result.conflicts, hasLength(2));
    });

    test('空 id 不参与去重', () {
      final result = dedupeModelsById([_model(''), _model('')]);
      expect(result.models, hasLength(2));
      expect(result.conflicts, isEmpty);
    });
  });

  group('resolveMenuIds', () {
    test('标签唯一时输出标签', () {
      final models = [_model('id-1'), _model('id-2')];
      expect(resolveMenuIds(models: models, labels: ['A', 'B']), ['A', 'B']);
    });

    test('标签冲突的所有模型都回退为真实 id，不冲突的保持标签', () {
      final models = [_model('id-1'), _model('id-2'), _model('id-3')];
      expect(
        resolveMenuIds(models: models, labels: ['same', 'same', 'other']),
        ['id-1', 'id-2', 'other'],
      );
    });

    test('没有标签的模型回退为真实 id', () {
      final models = [_model('id-1'), _model('id-2')];
      expect(resolveMenuIds(models: models, labels: [null, 'B']), [
        'id-1',
        'B',
      ]);
    });

    test('空列表返回空列表', () {
      expect(resolveMenuIds(models: const [], labels: const []), isEmpty);
    });
  });
}
