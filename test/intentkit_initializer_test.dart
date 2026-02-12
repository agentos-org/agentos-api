import 'package:agentos_api/src/locator.dart';
import 'package:agentos_api/src/services/intentkit/intentkit_initializer.dart';
import 'package:liteagent_sdk_dart/liteagent_sdk_dart.dart';
import 'package:test/test.dart';

class _FakeServiceLocator implements AgentOSServiceLocator {
  _FakeServiceLocator({this.models = const []});

  final List<LlmModelInfo> models;

  @override
  String get liteagentBaseUrl => 'http://127.0.0.1:9527/api/v1';

  @override
  Future<List<AppInfo>> getAppInfoList() async => const [];

  @override
  Future<List<LlmModelInfo>> getLlmModelList() async => models;

  @override
  Future<int?> getServicePort(String serviceKey) async => null;

  @override
  Future<int?> resolveLLMPort(String serviceKey, String? modelId) async => null;
}

void main() {
  test('buildKernelConfig succeeds without llm base url', () async {
    final config = await IntentKitInitializer.buildKernelConfig(
      serviceLocator: _FakeServiceLocator(),
      liteAgentSdk: LiteAgentSDK(baseUrl: 'http://127.0.0.1:9527/api/v1'),
      llmBaseUrl: null,
      embeddingsBaseUrl: 'http://127.0.0.1:52030',
      embeddingsDocsName: 'test_docs',
    );

    expect(config, isNotNull);
    expect(config!.llm, isNull);
  });

  test(
    'buildKernelConfig includes llm group when models are available',
    () async {
      final config = await IntentKitInitializer.buildKernelConfig(
        serviceLocator: _FakeServiceLocator(
          models: const [
            LlmModelInfo(
              id: 'qwen',
              name: 'Qwen',
              description: 'test',
              parameters: '7B',
              paramsB: 7,
              quantization: 'q4',
              sizeGB: 4,
              minRAMGB: 8,
              downloadUrl: '',
              tags: ['chat'],
              repoId: 'repo',
              type: 'text',
              contextWindowSize: 8192,
            ),
          ],
        ),
        liteAgentSdk: LiteAgentSDK(baseUrl: 'http://127.0.0.1:9527/api/v1'),
        llmBaseUrl: 'http://127.0.0.1:52010',
        embeddingsBaseUrl: 'http://127.0.0.1:52030',
        embeddingsDocsName: 'test_docs',
      );

      expect(config, isNotNull);
      expect(config!.llm, isNotNull);
      expect(config.llm!.models.single.model, 'qwen');
    },
  );
}
