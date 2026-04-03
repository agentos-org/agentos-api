import 'package:agentos_kernel/agentos_kernel.dart' as kernel;
import 'package:liteagent_sdk_dart/liteagent_sdk_dart.dart';

import '../../locator.dart';
import '../../config.dart';
import 'kernel_model_support.dart';

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
    final llmPort =
        await serviceLocator.getServicePort(ApiConfig.serviceLlmText) ??
        await serviceLocator.getServicePort(ApiConfig.serviceLlmVision);
    final llmModelList = await serviceLocator.getLlmModelList();
    if (llmPort == null && !llmModelList.any((m) => m.isRemote)) {
      return false;
    }
    final llmModels = buildKernelLlmModels(
      llmModelList,
      llmBaseUrl: llmPort != null ? 'http://localhost:$llmPort' : null,
      llmApiKey: llmApiKey,
    );
    if (llmModels.isEmpty) {
      return false;
    }
    kernelService.updateLlmModels(llmModels, refreshServices: true);
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
    String? embeddingsLlmModel,
  }) async {
    final kernelService = this.kernelService;
    if (kernelService == null) {
      return false;
    }
    final embeddingsPort = await serviceLocator.getServicePort(
      ApiConfig.serviceEmbeddings,
    );
    if (embeddingsPort == null) {
      return false;
    }
    final llmModelList = await serviceLocator.getLlmModelList();
    final inferenceModels = llmModelList.where(supportsTextInference).toList();
    final preferredLlmModel =
        embeddingsLlmModel ??
        (inferenceModels.isEmpty ? null : inferenceModels.first.id);
    return kernelService.updateEmbeddingsConfig(
      kernel.EmbeddingsConfig(
        baseUrl: 'http://localhost:$embeddingsPort',
        apiKey: embeddingsApiKey,
        docsName: embeddingsDocsName,
        model: embeddingsModel,
        llmModel: preferredLlmModel,
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
    String? embeddingsLlmModel,
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
      embeddingsLlmModel: embeddingsLlmModel,
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
