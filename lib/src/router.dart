import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:agentos_kernel/agentos_kernel.dart';
import 'package:liteagent_sdk_dart/liteagent_sdk_dart.dart';
import 'locator.dart';
import 'controllers/agentkit/agentkit_controller.dart';
import 'controllers/appkit/appkit_controller.dart';
import 'controllers/intentkit/intentkit_controller.dart';
import 'controllers/llmkit/llmkit_controller.dart';
import 'controllers/system_controller.dart';
import 'controllers/toolkit/toolkit_controller.dart';
import 'config.dart';
import 'middleware.dart';
import 'services/appkit/app_called_handler_impl.dart';
import 'services/appkit/appkit_service.dart';
import 'services/intentkit/intentkit_service.dart';
import 'services/llmkit/llm_client.dart';
import 'services/toolkit/opentool_client.dart';

/// Creates the complete API Gateway request handler
///
/// Includes all routes: system endpoints, AgentKit, AppKit, proxy routes
///
/// [serviceLocator] Service locator for dynamic backend service discovery
/// [kernelFuture] Future that resolves to KernelService for intent detection and metrics
/// [enableLogging] Whether to enable request logging (default: true)
/// [enableCors] Whether to enable CORS middleware (default: true)
/// [gatewayPort] Gateway port (used for service discovery response)
Handler createGatewayHandler({
  required AgentOSServiceLocator serviceLocator,
  required Future<KernelService?> kernelFuture,
  required LiteAgentSDK liteAgentSdk,
  bool enableLogging = true,
  bool enableCors = true,
  int gatewayPort = ApiConfig.defaultPort,
}) {
  final router = createGatewayRouter(
    serviceLocator: serviceLocator,
    kernelFuture: kernelFuture,
    liteAgentSdk: liteAgentSdk,
    gatewayPort: gatewayPort,
  );

  var pipeline = const Pipeline();

  if (enableCors) {
    pipeline = pipeline.addMiddleware(cors());
  }

  if (enableLogging) {
    pipeline = pipeline.addMiddleware(
      logRequests(
        logger: (String message, bool isError) {
          if (isError) {
            requestLogger.severe(message);
          } else {
            requestLogger.info(message);
          }
        },
      ),
    );
  }

  return pipeline.addHandler(router.call);
}

/// Creates the complete API Gateway Router
///
/// Includes all routes: system endpoints, AgentKit, AppKit, proxy routes
Router createGatewayRouter({
  required AgentOSServiceLocator serviceLocator,
  required Future<KernelService?> kernelFuture,
  required LiteAgentSDK liteAgentSdk,
  int gatewayPort = ApiConfig.defaultPort,
}) {
  final router = Router();

  // System endpoints (version)
  final systemController = SystemController(
    gatewayPort: gatewayPort,
    kernelFuture: kernelFuture,
  );
  router.mount('/', systemController.router.call);

  // AppKit service (shared instance for token-bundleId resolution)
  final appKitService = AppKitService();

  // register AppCalledHandler to KernelService
  kernelFuture.then((kernelService) {
    if (kernelService != null) {
      final handler = AppCalledHandlerImpl(appKitService: appKitService);
      kernelService.setAppCalledHandler(handler);
    }
  });

  // AgentKit API (LiteAgent SDK, requires Token)
  final agentKitController = AgentKitController(
    sdk: liteAgentSdk,
    appKitService: appKitService,
    kernelFuture: kernelFuture,
  );
  router.mount('${ApiConfig.agentkitPath}/', agentKitController.router.call);

  // IntentKit API (intent detection, requires Token)
  final intentKitService = IntentKitService(kernelFuture: kernelFuture);
  final intentKitController = IntentKitController(service: intentKitService);
  router.mount('${ApiConfig.intentkitPath}/', intentKitController.router.call);

  // AppKit API (app registration/subscription)
  final appKitController = AppKitController(service: appKitService);
  router.mount('${ApiConfig.appkitPath}/', appKitController.router.call);

  // ToolKit API (proxy to OpenTool, requires Token)
  final openToolClient = OpenToolClient(serviceLocator: serviceLocator);
  final toolKitController = ToolKitController(client: openToolClient);
  router.mount('${ApiConfig.toolkitPath}/', toolKitController.router.call);

  // LLMKit API (proxy to LLM services, requires Token)
  final llmClient = LLMClient(
    serviceLocator: serviceLocator,
    kernelFuture: kernelFuture,
  );
  final llmKitController = LLMKitController(
    kernelFuture: kernelFuture,
    client: llmClient,
  );
  router.mount('${ApiConfig.llmkitPath}/', llmKitController.router.call);

  return router;
}
