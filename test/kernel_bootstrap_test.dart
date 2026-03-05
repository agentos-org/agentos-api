import 'package:agentos_api/src/locator.dart';
import 'package:agentos_api/src/services/kernel/kernel_bootstrap.dart';
import 'package:agentos_kernel/agentos_kernel.dart'
    show EmbeddingsConfig, KernelLlmModel, KernelService;
import 'package:liteagent_sdk_dart/liteagent_sdk_dart.dart';
import 'package:test/test.dart';

class _FakeServiceLocator implements AgentOSServiceLocator {
  _FakeServiceLocator({this.llmPort, this.models = const []});

  final int? llmPort;
  final List<LlmModelInfo> models;

  @override
  String get liteagentBaseUrl => 'http://127.0.0.1:9527/api/v1';

  @override
  Future<List<AppInfo>> getAppInfoList() async => const [];

  @override
  Future<List<LlmModelInfo>> getLlmModelList() async => models;

  @override
  Future<int?> getServicePort(String serviceKey, {String? modelId}) async {
    if (serviceKey == 'llm_text') {
      return llmPort;
    }
    if (serviceKey == 'llm_embedding') {
      return 52030;
    }
    if (serviceKey == 'opentool') {
      return 19627;
    }
    return null;
  }
}

class _FakeKernelService implements KernelService {
  List<KernelLlmModel>? updatedModels;
  EmbeddingsConfig? updatedEmbeddings;
  LiteAgentSDK? updatedLiteAgentSdk;
  ({String host, int port})? updatedOpenToolDaemon;

  @override
  void updateLlmModels(
    List<KernelLlmModel> models, {
    bool refreshServices = false,
  }) {
    updatedModels = models;
  }

  @override
  Future<void> updateLiteAgentSdk(
    LiteAgentSDK sdk, {
    List<PresetOpenSpec>? presetOpenSpecList,
  }) async {
    updatedLiteAgentSdk = sdk;
  }

  @override
  void updateOpenToolDaemon({required String host, required int port}) {
    updatedOpenToolDaemon = (host: host, port: port);
  }

  @override
  Future<bool> updateEmbeddingsConfig(EmbeddingsConfig config) async {
    updatedEmbeddings = config;
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not mocked');
}

void main() {
  test('syncLiteagentBaseUrlFromServiceLocator updates sdk base url', () async {
    final kernel = _FakeKernelService();
    final result = KernelBootstrapResult(
      kernelService: kernel,
      liteAgentSdk: LiteAgentSDK(baseUrl: 'http://127.0.0.1:9527/api/v1'),
    );
    final locator = _FakeServiceLocator(llmPort: 52010);

    final ok = await result.syncLiteagentBaseUrlFromServiceLocator(locator);

    expect(ok, isTrue);
    expect(result.liteAgentSdk.dio.options.baseUrl, locator.liteagentBaseUrl);
    expect(result.liteAgentSdk.sseService.baseUrl, locator.liteagentBaseUrl);
    expect(kernel.updatedLiteAgentSdk, isNotNull);
  });

  test('syncLlmModelsFromServiceLocator updates kernel models', () async {
    final kernel = _FakeKernelService();
    final result = KernelBootstrapResult(
      kernelService: kernel,
      liteAgentSdk: LiteAgentSDK(baseUrl: 'http://127.0.0.1:9527/api/v1'),
    );
    final locator = _FakeServiceLocator(
      llmPort: 52010,
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
    );

    final ok = await result.syncLlmModelsFromServiceLocator(locator);

    expect(ok, isTrue);
    expect(kernel.updatedModels, isNotNull);
    expect(kernel.updatedModels!.single.model, 'qwen');
  });

  test(
    'syncLlmModelsFromServiceLocator returns false without llm port',
    () async {
      final kernel = _FakeKernelService();
      final result = KernelBootstrapResult(
        kernelService: kernel,
        liteAgentSdk: LiteAgentSDK(baseUrl: 'http://127.0.0.1:9527/api/v1'),
      );
      final locator = _FakeServiceLocator(llmPort: null);

      final ok = await result.syncLlmModelsFromServiceLocator(locator);

      expect(ok, isFalse);
      expect(kernel.updatedModels, isNull);
    },
  );

  test('syncServicesFromServiceLocator updates available services', () async {
    final kernel = _FakeKernelService();
    final result = KernelBootstrapResult(
      kernelService: kernel,
      liteAgentSdk: LiteAgentSDK(baseUrl: 'http://127.0.0.1:9527/api/v1'),
    );
    final locator = _FakeServiceLocator(
      llmPort: 52010,
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
    );

    final ok = await result.syncServicesFromServiceLocator(locator);

    expect(ok, isTrue);
    expect(result.liteAgentSdk.dio.options.baseUrl, locator.liteagentBaseUrl);
    expect(kernel.updatedModels, isNotNull);
    expect(kernel.updatedEmbeddings, isNotNull);
    expect(kernel.updatedEmbeddings!.baseUrl, 'http://localhost:52030');
    expect(kernel.updatedOpenToolDaemon, isNotNull);
    expect(kernel.updatedOpenToolDaemon!.host, '127.0.0.1');
    expect(kernel.updatedOpenToolDaemon!.port, 19627);
  });
}
