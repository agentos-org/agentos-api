import 'package:agentos_kernel/agentos_kernel.dart' as kernel;
import 'package:liteagent_sdk_dart/liteagent_sdk_dart.dart';

import '../../locator.dart';
import '../intentkit/intentkit_initializer.dart';
import '../../config.dart';

/// Result of kernel bootstrap containing both the kernel service and
/// the shared LiteAgentSDK instance.
class KernelBootstrapResult {
  final kernel.KernelService? kernelService;
  final LiteAgentSDK liteAgentSdk;

  const KernelBootstrapResult({
    this.kernelService,
    required this.liteAgentSdk,
  });
}

class KernelBootstrap {
  KernelBootstrap._();

  /// Creates the kernel and a shared LiteAgentSDK instance.
  ///
  /// The returned [KernelBootstrapResult] contains both the kernel service
  /// (which may be null if LLM models are not configured) and the
  /// [LiteAgentSDK] instance that should be shared across the application.
  static Future<KernelBootstrapResult> createKernel(
    AgentOSServiceLocator serviceLocator,
  ) async {
    final liteagentBaseUrl = serviceLocator.liteagentBaseUrl;
    final liteAgentSdk = LiteAgentSDK(baseUrl: liteagentBaseUrl);

    final kernelConfig = await _buildKernelConfigFromServiceLocator(
      serviceLocator,
      liteAgentSdk,
    );
    if (kernelConfig == null) {
      return KernelBootstrapResult(liteAgentSdk: liteAgentSdk);
    }
    final kernelService = await kernel.KernelService.create(kernelConfig);
    await applyAppInfoList(serviceLocator, kernelService);
    return KernelBootstrapResult(
      kernelService: kernelService,
      liteAgentSdk: liteAgentSdk,
    );
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
    LiteAgentSDK liteAgentSdk,
  ) async {
    final llmPort =
        await serviceLocator.getServicePort(ApiConfig.serviceLlmText);
    final embeddingsPort =
        await serviceLocator.getServicePort(ApiConfig.serviceLlmEmbedding);
    if (llmPort == null || embeddingsPort == null) {
      return null;
    }
    final llmBaseUrl = 'http://localhost:$llmPort';
    final embeddingsBaseUrl = 'http://localhost:$embeddingsPort';
    const embeddingsDocsName = 'agentos_default_embeddings';

    return IntentKitInitializer.buildKernelConfig(
      serviceLocator: serviceLocator,
      liteAgentSdk: liteAgentSdk,
      llmBaseUrl: llmBaseUrl,
      llmApiKey: '',
      embeddingsBaseUrl: embeddingsBaseUrl,
      embeddingsDocsName: embeddingsDocsName,
    );
  }
}
