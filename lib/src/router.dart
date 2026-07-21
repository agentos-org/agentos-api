import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:agentos_kernel/agentos_kernel.dart';
import 'package:liteagent_sdk_dart/liteagent_sdk_dart.dart';
import 'locator.dart';
import 'controllers/agentkit/agentkit_controller.dart';
import 'controllers/appkit/appkit_controller.dart';
import 'controllers/cronkit/cronkit_controller.dart';
import 'controllers/modelkit/modelkit_controller.dart';
import 'controllers/ragkit/ragkit_controller.dart';
import 'controllers/system_controller.dart';
import 'controllers/toolkit/toolkit_controller.dart';
import 'config.dart';
import 'middleware.dart';
import 'services/appkit/appkit_service.dart';
import 'services/appkit/opentool_availability_service.dart';
import 'services/appkit/opentool_provisioning_service.dart';
import 'services/cronkit/cronkit_model_ref_store.dart';
import 'services/modelkit/model_client.dart';
import 'services/toolkit/opentool_client.dart';

String _createGatewayInstanceId() {
  final now = DateTime.now().toUtc().microsecondsSinceEpoch.toRadixString(16);
  return 'gw-$now';
}

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
  OpenToolProvisioner? openToolProvisioner,
  OpenToolAvailabilityTracker? openToolAvailabilityTracker,
}) {
  final router = createGatewayRouter(
    serviceLocator: serviceLocator,
    kernelFuture: kernelFuture,
    liteAgentSdk: liteAgentSdk,
    gatewayPort: gatewayPort,
    openToolProvisioner: openToolProvisioner,
    openToolAvailabilityTracker: openToolAvailabilityTracker,
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
  OpenToolProvisioner? openToolProvisioner,
  OpenToolAvailabilityTracker? openToolAvailabilityTracker,
}) {
  final instanceId = _createGatewayInstanceId();
  requestLogger.info('Creating gateway router instanceId=$instanceId');
  final router = Router();

  // System endpoints (version)
  final systemController = SystemController(
    gatewayPort: gatewayPort,
    kernelFuture: kernelFuture,
  );
  router.mount('/', systemController.router.call);

  // AppKit service (shared instance for token-bundleId resolution)
  final appKitService = AppKitService();

  // AgentKit API (LiteAgent SDK, requires Token)
  final agentKitController = AgentKitController(
    sdk: liteAgentSdk,
    appKitService: appKitService,
    kernelFuture: kernelFuture,
    serviceLocator: serviceLocator,
  );
  router.mount('${ApiConfig.agentkitPath}/', agentKitController.router.call);

  // AppKit API (app registration/subscription)
  final resolvedOpenToolProvisioner =
      openToolProvisioner ??
      OpenToolProvisioningService(serviceLocator: serviceLocator);
  final resolvedOpenToolAvailabilityTracker =
      openToolAvailabilityTracker ??
      OpenToolAvailabilityService(
        serviceLocator: serviceLocator,
        appKitService: appKitService,
      );
  final appKitController = AppKitController(
    service: appKitService,
    openToolProvisioner: resolvedOpenToolProvisioner,
    openToolAvailabilityTracker: resolvedOpenToolAvailabilityTracker,
  );
  router.mount('${ApiConfig.appkitPath}/', appKitController.router.call);

  // CronKit API (cron task management, requires Token)
  final cronKitModelRefStore = HiveCronKitModelRefStore();
  final cronKitController = CronKitController(
    kernelFuture: kernelFuture,
    appKitService: appKitService,
    serviceLocator: serviceLocator,
    modelRefStore: cronKitModelRefStore,
    liteAgentBaseUrl: serviceLocator.liteagentBaseUrl,
  );
  router.mount('${ApiConfig.cronkitPath}/', cronKitController.router.call);

  final ragKitController = RagKitController(
    kernelFuture: kernelFuture,
    appKitService: appKitService,
  );
  router.mount('${ApiConfig.ragkitPath}/', ragKitController.router.call);

  // ToolKit API (proxy to OpenTool, requires Token)
  final openToolClient = OpenToolClient(serviceLocator: serviceLocator);
  final toolKitController = ToolKitController(
    client: openToolClient,
    appKitService: appKitService,
  );
  router.mount('${ApiConfig.toolkitPath}/', toolKitController.router.call);

  // ModelKit API (task-oriented model proxy: chat / embedding / asr / tts).
  final modelClient = ModelClient(
    serviceLocator: serviceLocator,
    kernelFuture: kernelFuture,
  );
  final modelKitController = ModelKitController(
    kernelFuture: kernelFuture,
    client: modelClient,
  );
  router.mount(
    '${ApiConfig.modelkitPath}/',
    modelKitController.router.call,
  );

  return router;
}
