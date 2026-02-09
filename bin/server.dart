import 'dart:io';

import 'package:agentos_api/agentos_api.dart';
import 'package:logging/logging.dart';
import 'package:shelf/shelf_io.dart';
import 'package:agentos_api/src/services/kernel/kernel_bootstrap.dart';

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
  final bootstrapResult = await KernelBootstrap.createKernel(serviceLocator);
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
}
