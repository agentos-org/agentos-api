import 'dart:async';
import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';

import 'package:agentos_kernel/agentos_kernel.dart';
import '../contracts/service_locator.dart';
import '../controllers/agentkit/agentkit_controller.dart';
import '../controllers/appkit/appkit_controller.dart';
import '../controllers/intentkit/intentkit_controller.dart';
import '../controllers/llmkit/llmkit_controller.dart';
import '../controllers/system_controller.dart';
import '../controllers/toolkit/toolkit_controller.dart';
import '../services/agentkit/liteagent_client.dart';
import '../services/intentkit/intentkit_service.dart';
import '../services/llmkit/llm_client.dart';
import '../services/toolkit/opentool_client.dart';
import 'gateway_config.dart';

/// Gateway server state
enum GatewayServerState {
  stopped,
  starting,
  running,
  error,
}

/// Gateway server status information
class GatewayServerStatus {
  final GatewayServerState state;
  final String message;
  final int? port;

  const GatewayServerStatus({
    required this.state,
    required this.message,
    this.port,
  });
}

/// AgentOS API Gateway Server
///
/// Unified HTTP server integrating all routes:
/// - System endpoints (version)
/// - AgentKit API (agent proxy)
/// - AppKit API (app registration/subscription)
/// - Proxy routes (direct forwarding to backend services)
class GatewayServer {
  GatewayServer({
    required AgentOSServiceLocator serviceLocator,
    KernelService? kernelService,
    int? port,
  })  : _serviceLocator = serviceLocator,
        _kernelService = kernelService,
        _port = port ?? GatewayConfig.defaultPort;

  final AgentOSServiceLocator _serviceLocator;
  final KernelService? _kernelService;
  final int _port;

  HttpServer? _server;
  bool _isRunning = false;
  final _statusController = StreamController<GatewayServerStatus>.broadcast();

  /// Service status stream
  Stream<GatewayServerStatus> get statusStream => _statusController.stream;

  /// Whether currently running
  bool get isRunning => _isRunning;

  /// Current port
  int get currentPort => _port;

  /// API base URL
  String get baseUrl => GatewayConfig.getBaseUrl(_port);

  /// Starts the gateway server
  Future<bool> start() async {
    if (_isRunning) {
      return true;
    }

    _statusController.add(const GatewayServerStatus(
      state: GatewayServerState.starting,
      message: 'Starting API Gateway...',
    ));

    try {
      // Check if port is available
      final portAvailable = await _checkPortAvailable();
      if (!portAvailable) {
        _statusController.add(GatewayServerStatus(
          state: GatewayServerState.error,
          message: 'Port $_port is already in use',
        ));
        return false;
      }

      // Create router
      final router = _createRouter();

      // Create middleware pipeline
      final handler = const Pipeline()
          .addMiddleware(_corsMiddleware())
          .addMiddleware(_loggingMiddleware())
          .addHandler(router.call);

      // Start server
      _server = await shelf_io.serve(
        handler,
        InternetAddress.anyIPv4,
        _port,
      );

      _isRunning = true;

      _statusController.add(GatewayServerStatus(
        state: GatewayServerState.running,
        message: 'API Gateway running',
        port: _port,
      ));

      return true;
    } catch (e) {
      _statusController.add(GatewayServerStatus(
        state: GatewayServerState.error,
        message: 'Failed to start: $e',
      ));
      return false;
    }
  }

  /// Stops the gateway server
  Future<void> stop() async {
    if (_server != null) {
      await _server!.close(force: true);
      _server = null;
    }

    _isRunning = false;

    _statusController.add(const GatewayServerStatus(
      state: GatewayServerState.stopped,
      message: 'API Gateway stopped',
    ));
  }

  /// Creates router
  Router _createRouter() {
    final router = Router();

    // System endpoints
    final systemController = SystemController(
      gatewayPort: _port,
    );
    router.mount('/', systemController.router.call);

    // AgentKit API
    final liteagentClient = LiteagentClient(serviceLocator: _serviceLocator);
    final agentKitController = AgentKitController(client: liteagentClient);
    router.mount('${GatewayConfig.agentkitPath}/', agentKitController.router.call);

    // IntentKit API
    final intentKitService = IntentKitService(
      kernelFuture: Future.value(_kernelService),
    );
    final intentKitController = IntentKitController(service: intentKitService);
    router.mount('${GatewayConfig.intentkitPath}/', intentKitController.router.call);

    // AppKit API
    final appKitController = AppKitController();
    router.mount('${GatewayConfig.appkitPath}/', appKitController.router.call);

    // ToolKit API (proxy to OpenTool, requires Token)
    final openToolClient = OpenToolClient(serviceLocator: _serviceLocator);
    final toolKitController = ToolKitController(client: openToolClient);
    router.mount('${GatewayConfig.toolkitPath}/', toolKitController.router.call);

    // LLMKit API (proxy to LLM services, requires Token)
    final llmClient = LLMClient(serviceLocator: _serviceLocator);
    final llmKitController = LLMKitController(client: llmClient);
    router.mount('${GatewayConfig.llmkitPath}/', llmKitController.router.call);

    return router;
  }

  /// CORS middleware
  Middleware _corsMiddleware() {
    const corsHeaders = {
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
      'Access-Control-Allow-Headers':
          'Origin, Content-Type, Accept, Authorization',
      'Access-Control-Max-Age': '86400',
    };

    return (Handler innerHandler) {
      return (Request request) async {
        // Handle OPTIONS preflight request
        if (request.method == 'OPTIONS') {
          return Response.ok('', headers: corsHeaders);
        }

        // Handle normal request, add CORS headers
        final response = await innerHandler(request);
        return response.change(headers: corsHeaders);
      };
    };
  }

  /// Logging middleware
  Middleware _loggingMiddleware() {
    return logRequests(
      logger: (String message, bool isError) {
        final prefix = isError ? '[Gateway ERROR]' : '[Gateway]';
        // ignore: avoid_print
        print('$prefix $message');
      },
    );
  }

  /// Checks if port is available
  Future<bool> _checkPortAvailable() async {
    try {
      final socket = await ServerSocket.bind('0.0.0.0', _port);
      await socket.close();
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Releases resources
  void dispose() {
    stop();
    _statusController.close();
  }
}
