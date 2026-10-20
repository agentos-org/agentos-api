import 'package:agentos_api/agentos_api.dart';
import 'package:test/test.dart';

void main() {
  group('AppModelId 字符与长度约束', () {
    test('localId：允许 [A-Za-z0-9._-]，长度 1 到 64', () {
      for (final good in ['a', 'A.b_c-1', '0', 'x' * 64, 'rknn-qwen3-0.6b']) {
        expect(AppModelId.isValidLocalId(good), isTrue, reason: good);
      }
      for (final bad in [
        '',
        ' ',
        'has space',
        'a@b',
        'a(b)',
        'a/b',
        'a\\b',
        '中文',
        'a\nb',
        'x' * 65,
      ]) {
        expect(AppModelId.isValidLocalId(bad), isFalse, reason: bad);
      }
    });

    test('bundleId：允许 [A-Za-z0-9._-]，长度 1 到 128', () {
      for (final good in ['com.example.app', 'a', 'x' * 128, 'My-App_1.0']) {
        expect(AppModelId.isValidBundleId(good), isTrue, reason: good);
      }
      for (final bad in ['', 'com example', 'com@example', 'x' * 129, '应用']) {
        expect(AppModelId.isValidBundleId(bad), isFalse, reason: bad);
      }
    });

    test('分隔符 @ 不在任何一方的合法字符里，所以 qualifiedId 的拆分没有歧义', () {
      expect(AppModelId.separator, '@');
      expect(AppModelId.isValidLocalId('a@b'), isFalse);
      expect(AppModelId.isValidBundleId('a@b'), isFalse);
    });
  });

  group('AppModelId.qualify / localIdOf', () {
    test('qualify 拼成 localId@bundleId', () {
      expect(
        AppModelId.qualify(bundleId: 'com.example.a', localId: 'chat-1'),
        'chat-1@com.example.a',
      );
    });

    test('localIdOf 按 bundleId 去后缀，可还原 qualify 的结果', () {
      final qualified = AppModelId.qualify(
        bundleId: 'com.example.a',
        localId: 'chat-1',
      );
      expect(
        AppModelId.localIdOf(qualified, bundleId: 'com.example.a'),
        'chat-1',
      );
    });

    test('历史遗留的、localId 本身含 @ 的记录也能还原（按 bundleId 去后缀而不是按 @ 切分）', () {
      expect(
        AppModelId.localIdOf(
          'weird@id@com.example.a',
          bundleId: 'com.example.a',
        ),
        'weird@id',
      );
    });

    test('后缀不是该 bundleId 或去掉后缀后为空时返回 null', () {
      expect(
        AppModelId.localIdOf('chat-1@com.example.b', bundleId: 'com.example.a'),
        isNull,
      );
      expect(AppModelId.localIdOf('chat-1', bundleId: 'com.example.a'), isNull);
      expect(
        AppModelId.localIdOf('@com.example.a', bundleId: 'com.example.a'),
        isNull,
      );
    });
  });

  group('AppModelData.qualifiedId', () {
    test('由 localId 与 appBundleId 组成，并出现在 toJson 里（id 仍是 localId）', () {
      const model = AppModelData(
        id: 'chat-1',
        name: 'gpt',
        appBundleId: 'com.example.a',
      );
      expect(model.qualifiedId, 'chat-1@com.example.a');

      final json = model.toJson();
      expect(json['id'], 'chat-1');
      expect(json['qualifiedId'], 'chat-1@com.example.a');
    });
  });
}
