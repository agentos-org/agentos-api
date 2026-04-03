import 'dart:convert';

import 'package:agentos_kernel/agentos_kernel.dart';
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
    Future<KernelService?>? kernelFuture,
  }) : _gatewayPort = gatewayPort,
       _kernelFuture = kernelFuture ?? Future.value(null);

  final int _gatewayPort;
  final Future<KernelService?> _kernelFuture;

  Router get router {
    final router = Router();

    router.get('/', _rootHandler);
    router.get('/version', _versionHandler);
    router.get('/ready', _readyHandler);

    return router;
  }

  /// Root path handler - returns gateway info
  Future<Response> _rootHandler(Request request) async {
    final endpoints = <String, String>{
      '/version': 'Gateway version',
      '/ready': 'Gateway readiness',
      '${ApiConfig.agentkitPath}/*':
          'AgentKit API (Agent service, requires Token)',
      '${ApiConfig.cronkitPath}/*':
          'CronKit API (Cron task management, requires Token)',
      '${ApiConfig.appkitPath}/*': 'AppKit API (App registration/subscription)',
      '${ApiConfig.toolkitPath}/*': 'ToolKit API (${ApiConfig.opentoolName})',
      '${ApiConfig.llmTextPath}/*': ApiConfig.llmTextName,
      '${ApiConfig.llmVisionPath}/*': ApiConfig.llmVisionName,
      '${ApiConfig.llmEmbeddingPath}/*': ApiConfig.llmEmbeddingName,
      '${ApiConfig.llmTtsPath}/*': ApiConfig.llmTtsName,
      '${ApiConfig.llmAsrPath}/*': ApiConfig.llmAsrName,
    };
    final info = {
      'name': 'AgentOS API Gateway',
      'version': packageVersion,
      'description':
          'Unified API Gateway providing single access point for all local AI services',
      'baseUrl': ApiConfig.getBaseUrl(_gatewayPort),
      'endpoints': endpoints,
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

  Future<Response> _readyHandler(Request request) async {
    final kernel = await _kernelFuture;
    if (kernel == null) {
      return Response(
        503,
        body: jsonEncode({
          'ready': false,
          'reasons': ['Kernel service is not initialized.'],
        }),
        headers: {'Content-Type': 'application/json'},
      );
    }
    final readiness = kernel.getReadiness();
    return Response(
      readiness.ready ? 200 : 503,
      body: jsonEncode({
        'ready': readiness.ready,
        'llmConfigured': readiness.llmConfigured,
        'llmServicesReady': readiness.llmServicesReady,
        'liteAgentReady': readiness.liteAgentReady,
        'openToolDaemonReady': readiness.openToolDaemonReady,
        'embeddingsReady': readiness.embeddingsReady,
        'reasons': readiness.reasons,
      }),
      headers: {'Content-Type': 'application/json'},
    );
  }
}
