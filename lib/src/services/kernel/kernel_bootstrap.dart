import 'package:agentos_kernel/agentos_kernel.dart' as kernel;

import '../../locator.dart';
import '../intentkit/intentkit_initializer.dart';
import '../../config.dart';

class KernelBootstrap {
  KernelBootstrap._();

  static Future<kernel.KernelService?> createKernel(
    AgentOSServiceLocator serviceLocator,
  ) async {
    final kernelConfig =
        await _buildKernelConfigFromServiceLocator(serviceLocator);
    if (kernelConfig == null) {
      return null;
    }
    final kernelService = await kernel.KernelService.create(kernelConfig);
    await applyAppInfoList(serviceLocator, kernelService);
    return kernelService;
  }

  static Future<void> applyAppInfoList(
    AgentOSServiceLocator serviceLocator,
    kernel.KernelService kernelService,
  ) async {
    final apps = await serviceLocator.getAppInfoList();
    if (apps.isEmpty) {
      return;
    }
    final mapped = apps
        .map(
          (app) => kernel.AppInfo(
            bundleId: app.bundleId,
            version: app.version,
            description: app.description,
            name: app.name,
          ),
        )
        .toList();
    kernelService.updateAppInfoList(mapped);
  }

  static Future<kernel.KernelServiceConfig?>
      _buildKernelConfigFromServiceLocator(
    AgentOSServiceLocator serviceLocator,
  ) async {
    final liteagentPort =
        await serviceLocator.getServicePort(ApiConfig.serviceLiteagent);
    final llmPort =
        await serviceLocator.getServicePort(ApiConfig.serviceLlmText);
    final embeddingsPort =
        await serviceLocator.getServicePort(ApiConfig.serviceLlmEmbedding);
    if (liteagentPort == null || llmPort == null || embeddingsPort == null) {
      return null;
    }
    final liteAgentBaseUrl = 'http://localhost:$liteagentPort/api/v1';
    final llmBaseUrl = 'http://localhost:$llmPort';
    final embeddingsBaseUrl = 'http://localhost:$embeddingsPort';
    const embeddingsDocsName = 'agentos_default_embeddings';

    return IntentKitInitializer.buildKernelConfig(
      serviceLocator: serviceLocator,
      liteAgentBaseUrl: liteAgentBaseUrl,
      llmBaseUrl: llmBaseUrl,
      llmApiKey: '',
      embeddingsBaseUrl: embeddingsBaseUrl,
      embeddingsDocsName: embeddingsDocsName,
    );
  }
}
