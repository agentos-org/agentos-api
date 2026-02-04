import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:agentos_kernel/agentos_kernel.dart';
import 'contracts/default_service_locator.dart';
import 'contracts/service_locator.dart';
import 'controllers/agentkit/agentkit_controller.dart';
import 'controllers/appkit/appkit_controller.dart';
import 'controllers/intentkit/intentkit_controller.dart';
import 'controllers/llmkit/llmkit_controller.dart';
import 'controllers/root_controller.dart';
import 'controllers/system_controller.dart';
import 'controllers/toolkit/toolkit_controller.dart';
import 'gateway/gateway_config.dart';
import 'middleware.dart';
import 'services/agentkit/liteagent_client.dart';
import 'services/intentkit/intentkit_service.dart';
import 'services/llmkit/llm_client.dart';
import 'services/toolkit/opentool_client.dart';

/// Creates the complete API Gateway request handler
///
/// Includes all routes: system endpoints, AgentKit, AppKit, proxy routes
///
/// [serviceLocator] Service locator for dynamic backend service discovery
/// [enableLogging] Whether to enable request logging (default: true)
/// [gatewayPort] Gateway port (used for service discovery response)
Handler createGatewayHandler({
  required AgentOSServiceLocator serviceLocator,
  KernelService? kernelService,
  bool enableLogging = true,
  int gatewayPort = GatewayConfig.defaultPort,
}) {
  final router = createGatewayRouter(
    serviceLocator: serviceLocator,
    kernelService: kernelService,
    gatewayPort: gatewayPort,
  );

  var pipeline = const Pipeline();

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
  KernelService? kernelService,
  int gatewayPort = GatewayConfig.defaultPort,
}) {
  final router = Router();

  // System endpoints (version)
  final systemController = SystemController(
    gatewayPort: gatewayPort,
  );
  router.mount('/', systemController.router.call);

  // AgentKit API (proxy to LiteAgent, requires Token)
  final liteagentClient = LiteagentClient(serviceLocator: serviceLocator);
  final agentKitController = AgentKitController(client: liteagentClient);
  router.mount('${GatewayConfig.agentkitPath}/', agentKitController.router.call);

  // IntentKit API (intent detection, requires Token)
  final intentKitService = IntentKitService(
    kernelFuture: Future.value(kernelService),
  );
  final intentKitController = IntentKitController(service: intentKitService);
  router.mount('${GatewayConfig.intentkitPath}/', intentKitController.router.call);

  // AppKit API (app registration/subscription)
  final appKitController = AppKitController();
  router.mount('${GatewayConfig.appkitPath}/', appKitController.router.call);

  // ToolKit API (proxy to OpenTool, requires Token)
  final openToolClient = OpenToolClient(serviceLocator: serviceLocator);
  final toolKitController = ToolKitController(client: openToolClient);
  router.mount('${GatewayConfig.toolkitPath}/', toolKitController.router.call);

  // LLMKit API (proxy to LLM services, requires Token)
  final llmClient = LLMClient(serviceLocator: serviceLocator);
  final llmKitController = LLMKitController(client: llmClient);
  router.mount('${GatewayConfig.llmkitPath}/', llmKitController.router.call);

  return router;
}

// ============ Legacy API below, deprecated ============

/// Creates AgentOS API request handler
///
/// @deprecated Use [createGatewayHandler] instead
@Deprecated('Use createGatewayHandler instead')
Handler createHandler({
  AgentOSServiceLocator? serviceLocator,
  KernelService? kernelService,
  bool enableLogging = true,
  String pathPrefix = '',
}) {
  // Create LiteagentClient with ServiceLocator
  final resolvedLocator = serviceLocator ?? DefaultServiceLocator();
  final liteagentClient = LiteagentClient(serviceLocator: resolvedLocator);
  final resolvedKernel = kernelService;

  final router = Router()
    ..mount('$pathPrefix/', RootController().router.call)
    ..mount('$pathPrefix/agentkit/', AgentKitController(client: liteagentClient).router.call)
    ..mount(
      '$pathPrefix/intentkit/',
      IntentKitController(
        service: IntentKitService(
          kernelFuture: Future.value(resolvedKernel),
        ),
      ).router.call,
    )
    ..mount('$pathPrefix/appkit/', AppKitController().router.call);

  var pipeline = const Pipeline();

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

/// Gets the AgentOS API Router (without middleware)
///
/// @deprecated Use [createGatewayRouter] instead
@Deprecated('Use createGatewayRouter instead')
Router createRouter({
  AgentOSServiceLocator? serviceLocator,
  KernelService? kernelService,
  String pathPrefix = '',
}) {
  final resolvedLocator = serviceLocator ?? DefaultServiceLocator();
  final liteagentClient = LiteagentClient(serviceLocator: resolvedLocator);
  final resolvedKernel = kernelService;

  return Router()
    ..mount('$pathPrefix/', RootController().router.call)
    ..mount('$pathPrefix/agentkit/', AgentKitController(client: liteagentClient).router.call)
    ..mount(
      '$pathPrefix/intentkit/',
      IntentKitController(
        service: IntentKitService(
          kernelFuture: Future.value(resolvedKernel),
        ),
      ).router.call,
    )
    ..mount('$pathPrefix/appkit/', AppKitController().router.call);
}
