import 'dart:io';

import 'package:agentos_api/agentos_api.dart';
import 'package:agentos_kernel/agentos_kernel.dart';
import 'package:logging/logging.dart';
import 'package:shelf/shelf_io.dart';

void main(List<String> args) async {
  Logger.root.level = Level.INFO;
  Logger.root.onRecord.listen((rec) {
    // Basic stdout logger to mirror Shelf logging.
    stdout.writeln(
      '${rec.time.toIso8601String()} ${rec.level.name} ${rec.loggerName}: ${rec.message}',
    );
  });

  // Use any available host or container IP (usually `0.0.0.0`).
  final ip = InternetAddress.anyIPv4;

  final serviceLocator = DefaultServiceLocator();
  const runtime = KernelRuntimeConfig();
  final bootstrapResult = await KernelBootstrap.createKernel(
    serviceLocator,
    runtime: runtime,
  );
  final kernelFuture = Future.value(bootstrapResult.kernelService);
  final liteAgentSdk = bootstrapResult.liteAgentSdk;

  final handler = createGatewayHandler(
    serviceLocator: serviceLocator,
    kernelFuture: kernelFuture,
    liteAgentSdk: liteAgentSdk,
  );

  // For running in containers, we respect the PORT environment variable.
  final port = int.parse(Platform.environment['PORT'] ?? '20261');
  final baseUrl =
      Platform.environment['AGENTOS_BASEURL'] ?? 'http://127.0.0.1:20261';
  final server = await serve(handler, ip, port);
  print('Server listening on port ${server.port}');
  print('AGENTOS_BASEURL=$baseUrl');
  print('KERNEL_CWD=${Directory.current.path}');
  print('KERNEL_MEMORY_DB_PATH=${runtime.memoryDbPath}');
  print('KERNEL_PREFERENCE_DB_PATH=${runtime.preferenceDbPath}');
  print('KERNEL_MODEL_PROFILER_DB_PATH=${runtime.modelProfilerDbPath}');
  print('KERNEL_CRON_DB_PATH=${runtime.cronDbPath}');
}
