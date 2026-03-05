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
  Future<int?> getServicePort(String serviceKey, {String? modelId}) async =>
      null;

  @override
  Stream<ServiceStatusEvent> get serviceStatusStream => const Stream.empty();
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
              alias: 'qwen',
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

  test('buildKernelModels filters out non-text models', () {
    final models = IntentKitInitializer.buildKernelModels(const [
      LlmModelInfo(
        id: 'bge-large-zh-v1.5-q8_0',
        name: 'bge-large-zh-v1.5-q8_0',
        alias: 'bge-large-zh-v1.5-q8_0',
        description: 'embedding model',
        parameters: 'embedding',
        paramsB: 0,
        quantization: 'q8_0',
        sizeGB: 0,
        minRAMGB: 0,
        downloadUrl: '',
        tags: ['embedding'],
        repoId: 'repo',
        type: 'llm_embedding',
        contextWindowSize: 4096,
      ),
      LlmModelInfo(
        id: 'qwen3-8b',
        name: 'qwen3-8b',
        alias: 'qwen3-8b',
        description: 'text model',
        parameters: '8B',
        paramsB: 8,
        quantization: 'q4',
        sizeGB: 0,
        minRAMGB: 0,
        downloadUrl: '',
        tags: ['chat'],
        repoId: 'repo',
        type: 'text',
        contextWindowSize: 8192,
      ),
    ], llmBaseUrl: 'http://127.0.0.1:52010');

    expect(models.length, 1);
    expect(models.single.model, 'qwen3-8b');
    expect(models.single.contextWindowSize, 8192);
  });

  test('buildKernelModels accepts desktop textGeneration model type', () {
    final models = IntentKitInitializer.buildKernelModels(const [
      LlmModelInfo(
        id: 'qwen3-8b',
        name: 'qwen3-8b',
        alias: 'qwen3-8b',
        description: 'text model',
        parameters: '8B',
        paramsB: 8,
        quantization: 'q4',
        sizeGB: 0,
        minRAMGB: 0,
        downloadUrl: '',
        tags: ['chat'],
        repoId: 'repo',
        type: 'textGeneration',
        contextWindowSize: 8192,
      ),
    ], llmBaseUrl: 'http://127.0.0.1:52010');

    expect(models.length, 1);
    expect(models.single.model, 'qwen3-8b');
  });
}
