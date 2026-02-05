import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../config.dart';
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
      'baseUrl': ApiConfig.getBaseUrl(_gatewayPort),
      'endpoints': {
        '/version': 'Gateway version',
        '${ApiConfig.agentkitPath}/*': 'AgentKit API (Agent service, requires Token)',
        '${ApiConfig.intentkitPath}/*': 'IntentKit API (Intent detection, requires Token)',
        '${ApiConfig.appkitPath}/*': 'AppKit API (App registration/subscription)',
        '${ApiConfig.toolkitPath}/*': 'ToolKit API (${ApiConfig.opentoolName})',
        '${ApiConfig.llmTextPath}/*': ApiConfig.llmTextName,
        '${ApiConfig.llmVisionPath}/*': ApiConfig.llmVisionName,
        '${ApiConfig.llmEmbeddingPath}/*': ApiConfig.llmEmbeddingName,
        '${ApiConfig.llmTtsPath}/*': ApiConfig.llmTtsName,
        '${ApiConfig.llmAsrPath}/*': ApiConfig.llmAsrName,
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
