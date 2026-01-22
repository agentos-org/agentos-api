import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'contracts/service_locator.dart';
import 'controllers/agentkit/agentkit_controller.dart';
import 'controllers/appkit/appkit_controller.dart';
import 'controllers/llmkit/llmkit_controller.dart';
import 'controllers/root_controller.dart';
import 'controllers/system_controller.dart';
import 'controllers/toolkit/toolkit_controller.dart';
import 'gateway/gateway_config.dart';
import 'middleware.dart';
import 'services/agentkit/liteagent_client.dart';
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
  bool enableLogging = true,
  int gatewayPort = GatewayConfig.defaultPort,
}) {
  final router = createGatewayRouter(
    serviceLocator: serviceLocator,
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
  bool enableLogging = true,
  String pathPrefix = '',
}) {
  // Create LiteagentClient with ServiceLocator
  final liteagentClient = LiteagentClient(serviceLocator: serviceLocator);

  final router = Router()
    ..mount('$pathPrefix/', RootController().router.call)
    ..mount('$pathPrefix/agentkit/', AgentKitController(client: liteagentClient).router.call)
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
  String pathPrefix = '',
}) {
  final liteagentClient = LiteagentClient(serviceLocator: serviceLocator);

  return Router()
    ..mount('$pathPrefix/', RootController().router.call)
    ..mount('$pathPrefix/agentkit/', AgentKitController(client: liteagentClient).router.call)
    ..mount('$pathPrefix/appkit/', AppKitController().router.call);
}
