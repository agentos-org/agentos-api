import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../gateway/gateway_config.dart';
import '../version.dart';

/// System Controller
///
/// Handles gateway info, version, and other system-level endpoints
class SystemController {
  SystemController({
    required int gatewayPort,
  }) : _gatewayPort = gatewayPort;

  final int _gatewayPort;

  Router get router {
    final router = Router();

    router.get('/', _rootHandler);
    router.get('/version', _versionHandler);

    return router;
  }

  /// Root path handler - returns gateway info
  Future<Response> _rootHandler(Request request) async {
    final info = {
      'name': 'AgentOS API Gateway',
      'version': packageVersion,
      'description': 'Unified API Gateway providing single access point for all local AI services',
      'baseUrl': GatewayConfig.getBaseUrl(_gatewayPort),
      'endpoints': {
        '/version': 'Gateway version',
        '${GatewayConfig.agentkitPath}/*': 'AgentKit API (Agent service, requires Token)',
        '${GatewayConfig.intentkitPath}/*': 'IntentKit API (Intent detection, requires Token)',
        '${GatewayConfig.appkitPath}/*': 'AppKit API (App registration/subscription)',
        '${GatewayConfig.toolkitPath}/*': 'ToolKit API (${ServiceDisplayNames.opentool})',
        '${GatewayConfig.llmTextPath}/*': ServiceDisplayNames.llmText,
        '${GatewayConfig.llmVisionPath}/*': ServiceDisplayNames.llmVision,
        '${GatewayConfig.llmEmbeddingPath}/*': ServiceDisplayNames.llmEmbedding,
        '${GatewayConfig.llmTtsPath}/*': ServiceDisplayNames.llmTts,
        '${GatewayConfig.llmAsrPath}/*': ServiceDisplayNames.llmAsr,
      },
    };

    return Response.ok(
      jsonEncode(info),
      headers: {'Content-Type': 'application/json'},
    );
  }

  /// Version handler
  Response _versionHandler(Request request) {
    return Response.ok(
      jsonEncode({'version': packageVersion}),
      headers: {'Content-Type': 'application/json'},
    );
  }
}
