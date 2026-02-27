import 'package:agentos_kernel/agentos_kernel.dart' as kernel;
import 'package:liteagent_sdk_dart/liteagent_sdk_dart.dart';

import '../../locator.dart';

class IntentKitInitializer {
  IntentKitInitializer._();

  static Future<kernel.KernelServiceConfig?> buildKernelConfig({
    required AgentOSServiceLocator serviceLocator,
    required LiteAgentSDK liteAgentSdk,
    String? llmBaseUrl,
    String llmApiKey = '',
    String? fallbackModel,
    required String embeddingsBaseUrl,
    String? embeddingsApiKey,
    required String embeddingsDocsName,
    String? embeddingsModel,
    String hivePath = '.hive',
    Duration ttftThreshold = const Duration(milliseconds: 5000),
    double tpsThreshold = 5.0,
    int maxConcurrency = 8,
    double maxPreferenceDistance = 0.35,
    int vectorQueryLimit = 5,
    int maxPreferenceResults = 3,
  }) async {
    final llmModelList = await serviceLocator.getLlmModelList();
    final llmModels = buildKernelModels(
      llmModelList,
      llmBaseUrl: llmBaseUrl,
      llmApiKey: llmApiKey,
      fallbackModel: fallbackModel,
    );

    return kernel.KernelServiceConfig(
      liteAgentSdk: liteAgentSdk,
      llm: llmModels.isEmpty ? null : kernel.LlmConfigGroup(models: llmModels),
      embeddings: kernel.EmbeddingsConfig(
        baseUrl: embeddingsBaseUrl,
        apiKey: embeddingsApiKey,
        docsName: embeddingsDocsName,
        model: embeddingsModel,
      ),
      runtime: kernel.KernelRuntimeConfig(
        hivePath: hivePath,
        ttftThreshold: ttftThreshold,
        tpsThreshold: tpsThreshold,
        maxConcurrency: maxConcurrency,
        maxPreferenceDistance: maxPreferenceDistance,
        vectorQueryLimit: vectorQueryLimit,
        maxPreferenceResults: maxPreferenceResults,
      ),
    );
  }

  static List<kernel.KernelLlmModel> buildKernelModels(
    List<LlmModelInfo> models, {
    String? llmBaseUrl,
    String? llmApiKey,
    String? fallbackModel,
  }) {
    final mapped = models
        .where((model) {
          if (model.isRemote) return true;
          return llmBaseUrl != null && llmBaseUrl.isNotEmpty;
        })
        .map(
          (model) => kernel.KernelLlmModel(
            baseUrl: model.baseUrl ?? llmBaseUrl!,
            apiKey: model.apiKey ?? llmApiKey ?? '',
            model: model.isRemote ? model.name : model.id,
            description: model.description,
            parameters: model.parameters,
            paramsB: model.paramsB,
            quantization: model.quantization,
            sizeGB: model.sizeGB,
            contextWindowSize: model.contextWindowSize,
          ),
        )
        .toList();
    if (mapped.isNotEmpty) {
      return mapped;
    }
    final fallback = fallbackModel?.trim();
    if (fallback == null || fallback.isEmpty || llmBaseUrl == null) {
      return const [];
    }
    return [
      kernel.KernelLlmModel(
        baseUrl: llmBaseUrl,
        apiKey: llmApiKey ?? '',
        model: fallback,
        description: 'Configured model',
        parameters: fallback,
        paramsB: 0,
        quantization: 'unknown',
        sizeGB: 0,
      ),
    ];
  }
}
