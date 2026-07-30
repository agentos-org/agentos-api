import 'package:agentos_kernel/agentos_kernel.dart' as kernel;
import 'package:liteagent_sdk_dart/liteagent_sdk_dart.dart';
import 'package:logging/logging.dart';

import '../../locator.dart';
import '../../config.dart';
import 'kernel_model_support.dart';

final Logger _kernelBootstrapLogger = Logger('agentos_server');

/// Result of kernel bootstrap containing both the kernel service and
/// the shared LiteAgentSDK instance.
class KernelBootstrapResult {
  final kernel.KernelService? kernelService;
  final LiteAgentSDK liteAgentSdk;

  const KernelBootstrapResult({this.kernelService, required this.liteAgentSdk});

  /// Updates LiteAgent SDK base URL from ServiceLocator at runtime.
  ///
  /// Returns true when the value is updated.
  Future<bool> syncLiteagentBaseUrlFromServiceLocator(
    AgentOSServiceLocator serviceLocator,
  ) async {
    final kernelService = this.kernelService;
    if (kernelService == null) {
      return false;
    }
    final baseUrl = serviceLocator.liteagentBaseUrl.trim();
    if (baseUrl.isEmpty) {
      return false;
    }
    liteAgentSdk.dio.options.baseUrl = baseUrl;
    liteAgentSdk.sseService.baseUrl = baseUrl;
    await kernelService.updateLiteAgentSdk(liteAgentSdk);
    return true;
  }

  /// Updates kernel LLM models from ServiceLocator at runtime.
  ///
  /// Returns true when models are successfully injected.
  Future<bool> syncLlmModelsFromServiceLocator(
    AgentOSServiceLocator serviceLocator, {
    String llmApiKey = '',
  }) async {
    final kernelService = this.kernelService;
    if (kernelService == null) {
      return false;
    }
    final llmPort = await serviceLocator.getServicePort(
      ApiConfig.serviceLlmChat,
    );
    final llmModelList = await serviceLocator.getLlmModelList();
    if (llmPort == null && !llmModelList.any((m) => m.isRemote)) {
      _kernelBootstrapLogger.info(
        'KernelBootstrap syncLlmModels: skipped because no local LLM port and no remote models are available.',
      );
      return false;
    }
    final llmModels = buildKernelLlmModels(
      llmModelList,
      llmBaseUrl: llmPort != null ? 'http://localhost:$llmPort' : null,
      llmApiKey: llmApiKey,
    );
    if (llmModels.isEmpty) {
      _kernelBootstrapLogger.info(
        'KernelBootstrap syncLlmModels: skipped because service locator returned 0 text-inference models.',
      );
      return false;
    }
    kernelService.updateLlmModels(llmModels, refreshServices: true);
    _kernelBootstrapLogger.info(
      'KernelBootstrap syncLlmModels: configured ${llmModels.length} model(s): ${llmModels.map((model) => '${model.model}[${model.type}]').join(",")}',
    );
    return true;
  }

  /// Updates OpenTool daemon address from ServiceLocator at runtime.
  ///
  /// Returns true when the value is updated.
  Future<bool> syncOpenToolDaemonFromServiceLocator(
    AgentOSServiceLocator serviceLocator,
  ) async {
    final kernelService = this.kernelService;
    if (kernelService == null) {
      return false;
    }
    final port = await serviceLocator.getServicePort(ApiConfig.serviceOpentool);
    if (port == null) {
      return false;
    }
    final host = serviceLocator.openToolDaemonHost.trim();
    kernelService.updateOpenToolDaemon(
      host: host.isEmpty ? ApiConfig.internalHost : host,
      port: port,
    );
    return true;
  }

  /// Updates embeddings service config from ServiceLocator at runtime.
  ///
  /// Returns true when embeddings config is successfully injected.
  Future<bool> syncEmbeddingsFromServiceLocator(
    AgentOSServiceLocator serviceLocator, {
    String embeddingsApiKey = '',
    String embeddingsDocsName = 'agentos_default_embeddings',
    String? embeddingsModel,
  }) async {
    final kernelService = this.kernelService;
    if (kernelService == null) {
      return false;
    }
    final embeddingsPort = await serviceLocator.getServicePort(
      ApiConfig.serviceEmbeddings,
    );
    if (embeddingsPort == null) {
      _kernelBootstrapLogger.info(
        'KernelBootstrap syncEmbeddings: skipped because embeddings service is not running.',
      );
      return false;
    }
    final llmModelList = await serviceLocator.getLlmModelList();
    _kernelBootstrapLogger.info(
      'KernelBootstrap syncEmbeddings: service locator returned ${llmModelList.length} model(s): ${llmModelList.map((model) => '${model.name}[type=${model.type},params=${model.parameters},tags=${model.tags.join("/")}]').join(",")}',
    );
    final availableEmbeddingModels = llmModelList
        .where(supportsEmbeddingInference)
        .toList();
    _kernelBootstrapLogger.info(
      'KernelBootstrap syncEmbeddings: detected ${availableEmbeddingModels.length} embedding model(s): ${availableEmbeddingModels.map((model) => model.name).join(",")}',
    );
    final requestedEmbeddingsModel = embeddingsModel?.trim();
    final selectedEmbeddingModel = _selectEmbeddingModel(
      availableEmbeddingModels,
      requestedEmbeddingsModel,
    );
    final resolvedEmbeddingsModel =
        selectedEmbeddingModel?.name.trim() ?? requestedEmbeddingsModel;
    if (resolvedEmbeddingsModel == null || resolvedEmbeddingsModel.isEmpty) {
      _kernelBootstrapLogger.warning(
        'KernelBootstrap syncEmbeddings: embeddings service is running on port $embeddingsPort, but no embeddings model is available from service locator.',
      );
      return false;
    }

    String? embeddingModelBaseUrl;
    String? embeddingModelApiKey;
    if (selectedEmbeddingModel?.isRemote ?? false) {
      embeddingModelBaseUrl = _normalizeEmbeddingsModelBaseUrl(
        selectedEmbeddingModel!.baseUrl ?? '',
      );
      // Passing an explicit empty key prevents Kernel's legacy compatibility
      // fallback from forwarding the vector-store key to a remote model.
      embeddingModelApiKey = selectedEmbeddingModel.apiKey ?? '';
    } else {
      final llmEmbeddingPort = await serviceLocator.getServicePort(
        ApiConfig.serviceLlmEmbedding,
        modelId: selectedEmbeddingModel?.id,
      );
      if (llmEmbeddingPort != null) {
        embeddingModelBaseUrl = 'http://localhost:$llmEmbeddingPort';
      }
    }
    if (embeddingModelBaseUrl == null || embeddingModelBaseUrl.isEmpty) {
      _kernelBootstrapLogger.warning(
        'KernelBootstrap syncEmbeddings: model=$resolvedEmbeddingsModel is available, but its inference endpoint is not.',
      );
      return false;
    }

    final modelRoute = selectedEmbeddingModel?.isRemote ?? false
        ? 'remote'
        : 'local';
    _kernelBootstrapLogger.info(
      'KernelBootstrap syncEmbeddings: configuring embeddings on port $embeddingsPort with model=$resolvedEmbeddingsModel route=$modelRoute.',
    );
    return kernelService.updateEmbeddingsConfig(
      kernel.EmbeddingsConfig(
        baseUrl: 'http://localhost:$embeddingsPort',
        embeddingModelBaseUrl: embeddingModelBaseUrl,
        apiKey: embeddingsApiKey,
        embeddingModelApiKey: embeddingModelApiKey,
        docsName: embeddingsDocsName,
        model: resolvedEmbeddingsModel,
      ),
    );
  }

  /// Syncs known runtime-updatable services from ServiceLocator.
  ///
  /// Returns true when at least one service setting is updated.
  Future<bool> syncServicesFromServiceLocator(
    AgentOSServiceLocator serviceLocator, {
    String llmApiKey = '',
    String embeddingsApiKey = '',
    String embeddingsDocsName = 'agentos_default_embeddings',
    String? embeddingsModel,
  }) async {
    final liteagentUpdated = await syncLiteagentBaseUrlFromServiceLocator(
      serviceLocator,
    );
    final llmUpdated = await syncLlmModelsFromServiceLocator(
      serviceLocator,
      llmApiKey: llmApiKey,
    );
    final openToolUpdated = await syncOpenToolDaemonFromServiceLocator(
      serviceLocator,
    );
    final embeddingsUpdated = await syncEmbeddingsFromServiceLocator(
      serviceLocator,
      embeddingsApiKey: embeddingsApiKey,
      embeddingsDocsName: embeddingsDocsName,
      embeddingsModel: embeddingsModel,
    );
    return liteagentUpdated ||
        llmUpdated ||
        openToolUpdated ||
        embeddingsUpdated;
  }

  kernel.KernelReadiness? getReadiness({
    bool requireLlm = true,
    bool requireLiteAgent = true,
    bool requireOpenToolDaemon = false,
    bool requireEmbeddings = false,
  }) {
    final kernelService = this.kernelService;
    if (kernelService == null) {
      return null;
    }
    return kernelService.getReadiness(
      requireLlm: requireLlm,
      requireLiteAgent: requireLiteAgent,
      requireOpenToolDaemon: requireOpenToolDaemon,
      requireEmbeddings: requireEmbeddings,
    );
  }
}

LlmModelInfo? _selectEmbeddingModel(
  List<LlmModelInfo> availableModels,
  String? requestedModel,
) {
  if (requestedModel == null || requestedModel.isEmpty) {
    return availableModels.isEmpty ? null : availableModels.first;
  }
  for (final model in availableModels) {
    if (model.id == requestedModel ||
        model.name == requestedModel ||
        (model.alias.isNotEmpty && model.alias == requestedModel)) {
      return model;
    }
  }
  return null;
}

String _normalizeEmbeddingsModelBaseUrl(String baseUrl) {
  final normalized = baseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
  // lite_embeddings_dart delegates to dart_openai_sdk, which appends its own
  // `/v1` version segment before `/embeddings`.
  if (normalized.toLowerCase().endsWith('/v1')) {
    return normalized.substring(0, normalized.length - 3);
  }
  return normalized;
}

class KernelBootstrap {
  KernelBootstrap._();

  /// Creates the kernel and a shared LiteAgentSDK instance.
  ///
  /// The returned [KernelBootstrapResult] contains both the kernel service
  /// (which may be null if LLM models are not configured) and the
  /// [LiteAgentSDK] instance that should be shared across the application.
  static Future<KernelBootstrapResult> createKernel(
    AgentOSServiceLocator serviceLocator, {
    kernel.KernelRuntimeConfig runtime = const kernel.KernelRuntimeConfig(),
  }) async {
    final liteagentBaseUrl = serviceLocator.liteagentBaseUrl;
    final liteAgentSdk = LiteAgentSDK(baseUrl: liteagentBaseUrl);
    final resolvedRuntime = await resolveRuntimeConfig(
      serviceLocator,
      baseRuntime: runtime,
    );
    final kernelService = await kernel.KernelService.create(
      runtime: resolvedRuntime,
    );
    final result = KernelBootstrapResult(
      kernelService: kernelService,
      liteAgentSdk: liteAgentSdk,
    );
    await result.syncServicesFromServiceLocator(serviceLocator);
    final readiness = result.getReadiness(requireEmbeddings: true);
    if (readiness != null) {
      _kernelBootstrapLogger.info(
        'KernelBootstrap createKernel: llmConfigured=${readiness.llmConfigured} llmServicesReady=${readiness.llmServicesReady} liteAgentReady=${readiness.liteAgentReady} openToolDaemonReady=${readiness.openToolDaemonReady} embeddingsReady=${readiness.embeddingsReady}',
      );
      if (readiness.reasons.isNotEmpty) {
        _kernelBootstrapLogger.info(
          'KernelBootstrap createKernel reasons: ${readiness.reasons.join(" | ")}',
        );
      }
    }
    return result;
  }

  static Future<kernel.KernelRuntimeConfig> resolveRuntimeConfig(
    AgentOSServiceLocator serviceLocator, {
    kernel.KernelRuntimeConfig baseRuntime = const kernel.KernelRuntimeConfig(),
  }) async {
    final openToolPort = await serviceLocator.getServicePort(
      ApiConfig.serviceOpentool,
    );
    final openToolHost = serviceLocator.openToolDaemonHost.trim();

    return kernel.KernelRuntimeConfig(
      memoryDbPath: baseRuntime.memoryDbPath,
      preferenceDbPath: baseRuntime.preferenceDbPath,
      modelProfilerDbPath: baseRuntime.modelProfilerDbPath,
      cronDbPath: baseRuntime.cronDbPath,
      ttftThreshold: baseRuntime.ttftThreshold,
      tpsThreshold: baseRuntime.tpsThreshold,
      maxConcurrency: baseRuntime.maxConcurrency,
      memorySummaryRecentWindow: baseRuntime.memorySummaryRecentWindow,
      memorySummaryMaxRecords: baseRuntime.memorySummaryMaxRecords,
      memorySummaryMinRecords: baseRuntime.memorySummaryMinRecords,
      memorySummaryEnabled: baseRuntime.memorySummaryEnabled,
      memorySummaryInterval: baseRuntime.memorySummaryInterval,
      memorySummaryMaxScopesPerRun: baseRuntime.memorySummaryMaxScopesPerRun,
      opentoolDaemonHost: openToolHost.isEmpty
          ? baseRuntime.opentoolDaemonHost
          : openToolHost,
      opentoolDaemonPort: openToolPort ?? baseRuntime.opentoolDaemonPort,
      mode: baseRuntime.mode,
      profileSuccessRateThreshold: baseRuntime.profileSuccessRateThreshold,
    );
  }
}
