import 'package:agentos_api/agentos_api.dart';
import 'package:test/test.dart';

LlmModelInfo _model({
  String? baseUrl,
  bool isCustom = false,
  bool isAppModel = false,
  String? appBundleId,
  String? appName,
}) {
  return LlmModelInfo(
    id: 'm',
    name: 'm-name',
    alias: 'm-alias',
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
    baseUrl: baseUrl,
    isCustom: isCustom,
    isAppModel: isAppModel,
    appBundleId: appBundleId,
    appName: appName,
  );
}

void main() {
  group('LlmModelInfo.source 推导', () {
    test('没有 baseUrl 的模型是 local', () {
      expect(_model().source, LlmModelSource.local);
      expect(_model(baseUrl: '').source, LlmModelSource.local);
    });

    test('有 baseUrl 且非自定义的模型是 platform', () {
      expect(
        _model(baseUrl: 'https://platform.example.test/v1').source,
        LlmModelSource.platform,
      );
    });

    test('有 baseUrl 且自定义的模型是 custom', () {
      expect(
        _model(baseUrl: 'https://example.test/v1', isCustom: true).source,
        LlmModelSource.custom,
      );
    });

    test('应用模型是 app，且不会被误判为 platform', () {
      final model = _model(
        baseUrl: 'https://app.example.test/v1',
        isAppModel: true,
        appBundleId: 'com.example.app',
      );
      // 旧使用端只看 isRemote/isCustom 时，会把它当成 platform。
      expect(model.isRemote, isTrue);
      expect(model.isCustom, isFalse);
      expect(model.source, LlmModelSource.app);
    });

    test('应用模型优先级最高：即使没有 baseUrl 或被标记为 custom 也归 app', () {
      expect(_model(isAppModel: true).source, LlmModelSource.app);
      expect(
        _model(
          baseUrl: 'https://example.test/v1',
          isCustom: true,
          isAppModel: true,
        ).source,
        LlmModelSource.app,
      );
    });

    test('没有 baseUrl 时，即便 isCustom 为 true 也不是 custom（以运行位置为准）', () {
      expect(_model(isCustom: true).source, LlmModelSource.local);
    });
  });

  group('LlmModelInfo.toJson', () {
    test('始终携带 source，并保持旧布尔字段不变', () {
      final local = _model().toJson();
      expect(local['source'], 'local');
      expect(local.containsKey('isCustom'), isFalse);
      expect(local.containsKey('isAppModel'), isFalse);
      expect(local.containsKey('appName'), isFalse);

      final custom = _model(
        baseUrl: 'https://example.test/v1',
        isCustom: true,
      ).toJson();
      expect(custom['source'], 'custom');
      expect(custom['isCustom'], isTrue);
    });

    test('应用模型携带 appBundleId 与 appName', () {
      final json = _model(
        baseUrl: 'https://app.example.test/v1',
        isAppModel: true,
        appBundleId: 'com.example.app',
        appName: 'Example',
      ).toJson();
      expect(json['source'], 'app');
      expect(json['isAppModel'], isTrue);
      expect(json['appBundleId'], 'com.example.app');
      expect(json['appName'], 'Example');
    });

    test('空 appName 不会下发', () {
      final json = _model(
        baseUrl: 'https://app.example.test/v1',
        isAppModel: true,
        appBundleId: 'com.example.app',
        appName: '',
      ).toJson();
      expect(json.containsKey('appName'), isFalse);
    });
  });

  group('LlmModelSource', () {
    test('wireName 与枚举名一致且互不相同', () {
      final wireNames = LlmModelSource.values.map((s) => s.wireName).toList();
      expect(wireNames, ['local', 'platform', 'custom', 'app']);
      expect(wireNames.toSet(), hasLength(LlmModelSource.values.length));
    });

    test('tryParse 往返一致，未知值返回 null', () {
      for (final source in LlmModelSource.values) {
        expect(LlmModelSource.tryParse(source.wireName), source);
      }
      expect(LlmModelSource.tryParse('system'), isNull);
      expect(LlmModelSource.tryParse(''), isNull);
      expect(LlmModelSource.tryParse(null), isNull);
    });
  });
}
