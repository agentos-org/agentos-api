import 'dart:convert';

import 'package:agentos_api/agentos_api.dart';
import 'package:crypto/crypto.dart';
import 'package:test/test.dart';

void main() {
  group('AppModelId.generate', () {
    test('是 sha256("<bundleId>:<name>") 的前 12 位小写 hex', () {
      final expected = sha256
          .convert(utf8.encode('com.example.a:gpt-4o'))
          .toString()
          .substring(0, 12);
      expect(
        AppModelId.generate(bundleId: 'com.example.a', name: 'gpt-4o'),
        expected,
      );
      expect(expected, hasLength(AppModelId.hashLength));
      expect(AppModelId.isHashId(expected), isTrue);
    });

    test('同一 bundleId + name 总是得到同一个 id（幂等）', () {
      expect(
        AppModelId.generate(bundleId: 'com.example.a', name: 'chat'),
        AppModelId.generate(bundleId: 'com.example.a', name: 'chat'),
      );
    });

    test('bundleId 或 name 任一不同，id 就不同；name 区分大小写', () {
      final base = AppModelId.generate(bundleId: 'com.example.a', name: 'chat');
      expect(
        AppModelId.generate(bundleId: 'com.example.b', name: 'chat'),
        isNot(base),
      );
      expect(
        AppModelId.generate(bundleId: 'com.example.a', name: 'chat2'),
        isNot(base),
      );
      expect(
        AppModelId.generate(bundleId: 'com.example.a', name: 'Chat'),
        isNot(base),
      );
    });

    test('bundleId 与 name 都会先 trim', () {
      expect(
        AppModelId.generate(bundleId: ' com.example.a ', name: ' chat '),
        AppModelId.generate(bundleId: 'com.example.a', name: 'chat'),
      );
    });

    test('bundleId 不含 ":"，所以 bundleId:name 的拼接没有歧义', () {
      expect(AppModelId.isValidBundleId('a:b'), isFalse);
    });
  });

  group('AppModelId.isHashId', () {
    test('只接受 12 位小写 hex', () {
      expect(AppModelId.isHashId('0123456789ab'), isTrue);
      for (final bad in [
        '',
        '0123456789a',
        '0123456789abc',
        '0123456789AB',
        '0123456789ag',
        'chat-1',
        'chat-1@com.example.a',
      ]) {
        expect(AppModelId.isHashId(bad), isFalse, reason: bad);
      }
    });
  });

  group('AppModelId.isValidBundleId', () {
    test('允许 [A-Za-z0-9._-]，长度 1 到 128', () {
      for (final good in ['com.example.app', 'a', 'x' * 128, 'My-App_1.0']) {
        expect(AppModelId.isValidBundleId(good), isTrue, reason: good);
      }
      for (final bad in ['', 'com example', 'com@example', 'x' * 129, '应用']) {
        expect(AppModelId.isValidBundleId(bad), isFalse, reason: bad);
      }
    });
  });

  group('AppModelData', () {
    test('toJson 的 id 就是 hashid', () {
      final id = AppModelId.generate(bundleId: 'com.example.a', name: 'gpt');
      final json = AppModelData(
        id: id,
        name: 'gpt',
        appBundleId: 'com.example.a',
      ).toJson();
      expect(json['id'], id);
    });
  });
}
