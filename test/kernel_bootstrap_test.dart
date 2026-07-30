import 'package:agentos_api/src/locator.dart';
import 'package:agentos_api/src/services/kernel/kernel_bootstrap.dart';
import 'package:agentos_kernel/agentos_kernel.dart'
    show EmbeddingsConfig, KernelLlmModel, KernelService;
import 'package:liteagent_sdk_dart/liteagent_sdk_dart.dart';
import 'package:test/test.dart';

class _FakeServiceLocator implements AgentOSServiceLocator {
  _FakeServiceLocator({
    this.llmPort,
    this.llmEmbeddingPort = 52030,
    this.models = const [],
    this.openToolHost = '127.0.0.1',
  });

  final int? llmPort;
  final int? llmEmbeddingPort;
  final List<LlmModelInfo> models;
  final String openToolHost;
  String? requestedEmbeddingModelId;

  @override
  String get liteagentBaseUrl => 'http://127.0.0.1:9527/api/v1';

  String get openToolDaemonHost => openToolHost;

  @override
  Future<List<AppInfo>> getAppInfoList() async => const [];

  @override
  Future<List<LlmModelInfo>> getLlmModelList() async => models;

  @override
  Future<int?> getServicePort(String serviceKey, {String? modelId}) async {
    if (serviceKey == 'llm_chat') {
      return llmPort;
    }
    if (serviceKey == 'llm_embedding') {
      requestedEmbeddingModelId = modelId;
      return llmEmbeddingPort;
    }
    if (serviceKey == 'embeddings') {
      return 9537;
    }
    if (serviceKey == 'opentool') {
      return 19627;
    }
    return null;
  }

  @override
  Stream<ServiceStatusEvent> get serviceStatusStream => const Stream.empty();
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
    );

    final ok = await result.syncLlmModelsFromServiceLocator(locator);

    expect(ok, isTrue);
    expect(kernel.updatedModels, isNotNull);
    expect(kernel.updatedModels!.single.model, 'Qwen');
    expect(kernel.updatedModels!.single.type, 'text');
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

  test(
    'syncLlmModelsFromServiceLocator excludes a task-only embedding model',
    () async {
      final kernel = _FakeKernelService();
      final result = KernelBootstrapResult(
        kernelService: kernel,
        liteAgentSdk: LiteAgentSDK(baseUrl: 'http://127.0.0.1:9527/api/v1'),
      );
      final locator = _FakeServiceLocator(
        models: const [
          LlmModelInfo(
            id: 'remote-embedding-id',
            name: 'remote-embedding',
            alias: 'remote-embedding',
            description: '',
            parameters: '',
            paramsB: 0,
            quantization: '',
            sizeGB: 0,
            minRAMGB: 0,
            downloadUrl: '',
            tags: ['remote'],
            repoId: '',
            type: '',
            task: 'embedding',
            baseUrl: 'https://embedding.example/v1',
          ),
        ],
      );

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
        LlmModelInfo(
          id: 'bge-local',
          name: 'bge-local',
          alias: 'bge-local',
          description: 'embedding model',
          parameters: 'embedding',
          paramsB: 0,
          quantization: 'q8',
          sizeGB: 0,
          minRAMGB: 0,
          downloadUrl: '',
          tags: ['embedding'],
          repoId: 'repo',
          type: 'llm_embedding',
        ),
      ],
    );

    final ok = await result.syncServicesFromServiceLocator(locator);

    expect(ok, isTrue);
    expect(result.liteAgentSdk.dio.options.baseUrl, locator.liteagentBaseUrl);
    expect(kernel.updatedModels, isNotNull);
    expect(kernel.updatedEmbeddings, isNotNull);
    expect(kernel.updatedEmbeddings!.baseUrl, 'http://localhost:9537');
    expect(
      kernel.updatedEmbeddings!.embeddingModelBaseUrl,
      'http://localhost:52030',
    );
    expect(kernel.updatedOpenToolDaemon, isNotNull);
    expect(kernel.updatedOpenToolDaemon!.host, '127.0.0.1');
    expect(kernel.updatedOpenToolDaemon!.port, 19627);
  });

  test('resolveRuntimeConfig injects opentool daemon runtime values', () async {
    final locator = _FakeServiceLocator(
      llmPort: 52010,
      openToolHost: 'daemon.internal',
    );

    final runtime = await KernelBootstrap.resolveRuntimeConfig(locator);

    expect(runtime.opentoolDaemonHost, 'daemon.internal');
    expect(runtime.opentoolDaemonPort, 19627);
  });

  test(
    'syncEmbeddingsFromServiceLocator configures a local embedding model',
    () async {
      final kernel = _FakeKernelService();
      final result = KernelBootstrapResult(
        kernelService: kernel,
        liteAgentSdk: LiteAgentSDK(baseUrl: 'http://127.0.0.1:9527/api/v1'),
      );
      final locator = _FakeServiceLocator(
        llmPort: 52010,
        models: const [
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
        ],
      );

      final ok = await result.syncEmbeddingsFromServiceLocator(locator);

      expect(ok, isTrue);
      expect(kernel.updatedEmbeddings, isNotNull);
      expect(kernel.updatedEmbeddings!.baseUrl, 'http://localhost:9537');
      expect(
        kernel.updatedEmbeddings!.embeddingModelBaseUrl,
        'http://localhost:52030',
      );
      expect(kernel.updatedEmbeddings!.embeddingModelApiKey, isNull);
      expect(kernel.updatedEmbeddings!.docsName, 'agentos_default_embeddings');
      expect(kernel.updatedEmbeddings!.model, 'bge-large-zh-v1.5-q8_0');
      expect(locator.requestedEmbeddingModelId, 'bge-large-zh-v1.5-q8_0');
    },
  );

  test(
    'syncEmbeddingsFromServiceLocator forwards a remote model endpoint and key',
    () async {
      final kernel = _FakeKernelService();
      final result = KernelBootstrapResult(
        kernelService: kernel,
        liteAgentSdk: LiteAgentSDK(baseUrl: 'http://127.0.0.1:9527/api/v1'),
      );
      final locator = _FakeServiceLocator(
        llmEmbeddingPort: null,
        models: const [
          LlmModelInfo(
            id: 'remote-embedding-id',
            name: 'text-embedding-3-large',
            alias: 'remote-embedding',
            description: 'remote embedding model',
            parameters: '',
            paramsB: 0,
            quantization: '',
            sizeGB: 0,
            minRAMGB: 0,
            downloadUrl: '',
            tags: ['remote'],
            repoId: '',
            type: '',
            task: 'embedding',
            baseUrl: 'https://embedding.example/v1',
            apiKey: 'remote-model-key',
            isCustom: true,
          ),
        ],
      );

      final ok = await result.syncEmbeddingsFromServiceLocator(
        locator,
        embeddingsApiKey: 'vector-store-key',
      );

      expect(ok, isTrue);
      final config = kernel.updatedEmbeddings!;
      expect(config.baseUrl, 'http://localhost:9537');
      expect(config.apiKey, 'vector-store-key');
      expect(config.embeddingModelBaseUrl, 'https://embedding.example');
      expect(config.embeddingModelApiKey, 'remote-model-key');
      expect(config.model, 'text-embedding-3-large');
      expect(locator.requestedEmbeddingModelId, isNull);
    },
  );

  test(
    'syncEmbeddingsFromServiceLocator selects a requested remote model by alias',
    () async {
      final kernel = _FakeKernelService();
      final result = KernelBootstrapResult(
        kernelService: kernel,
        liteAgentSdk: LiteAgentSDK(baseUrl: 'http://127.0.0.1:9527/api/v1'),
      );
      final locator = _FakeServiceLocator(
        models: const [
          LlmModelInfo(
            id: 'local-id',
            name: 'local-model',
            alias: 'local',
            description: '',
            parameters: 'embedding',
            paramsB: 0,
            quantization: '',
            sizeGB: 0,
            minRAMGB: 0,
            downloadUrl: '',
            tags: ['embedding'],
            repoId: '',
            type: 'embedding',
          ),
          LlmModelInfo(
            id: 'remote-id',
            name: 'remote-model',
            alias: 'preferred-remote',
            description: '',
            parameters: '',
            paramsB: 0,
            quantization: '',
            sizeGB: 0,
            minRAMGB: 0,
            downloadUrl: '',
            tags: ['remote'],
            repoId: '',
            type: 'embedding',
            baseUrl: 'https://remote.example/v1/',
            apiKey: 'remote-key',
          ),
        ],
      );

      final ok = await result.syncEmbeddingsFromServiceLocator(
        locator,
        embeddingsModel: 'preferred-remote',
      );

      expect(ok, isTrue);
      expect(kernel.updatedEmbeddings!.model, 'remote-model');
      expect(
        kernel.updatedEmbeddings!.embeddingModelBaseUrl,
        'https://remote.example',
      );
      expect(kernel.updatedEmbeddings!.embeddingModelApiKey, 'remote-key');
    },
  );

  test(
    'syncEmbeddingsFromServiceLocator does not use the vector store as a model endpoint',
    () async {
      final kernel = _FakeKernelService();
      final result = KernelBootstrapResult(
        kernelService: kernel,
        liteAgentSdk: LiteAgentSDK(baseUrl: 'http://127.0.0.1:9527/api/v1'),
      );
      final locator = _FakeServiceLocator(
        llmEmbeddingPort: null,
        models: const [
          LlmModelInfo(
            id: 'local-id',
            name: 'local-model',
            alias: '',
            description: '',
            parameters: 'embedding',
            paramsB: 0,
            quantization: '',
            sizeGB: 0,
            minRAMGB: 0,
            downloadUrl: '',
            tags: ['embedding'],
            repoId: '',
            type: 'embedding',
          ),
        ],
      );

      final ok = await result.syncEmbeddingsFromServiceLocator(locator);

      expect(ok, isFalse);
      expect(kernel.updatedEmbeddings, isNull);
    },
  );
}
