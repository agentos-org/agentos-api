import 'dart:convert';
import 'dart:io';

import 'package:agentos_api/agentos_api.dart';
import 'package:agentos_kernel/agentos_kernel.dart' show KernelService;
import 'package:http/http.dart' as http;
import 'package:liteagent_sdk_dart/liteagent_sdk_dart.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:test/test.dart';

void main() {
  late HttpServer upstream;
  late HttpServer gateway;
  late String gatewayUrl;
  const internalToken = 'harness-sidecar-token';

  setUp(() async {
    upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    upstream.listen((request) async {
      final body = await request.fold<List<int>>(<int>[], (buffer, data) {
        buffer.addAll(data);
        return buffer;
      });
      final auth = request.headers.value(HttpHeaders.authorizationHeader);
      request.response.headers.set('content-type', 'application/json');
      request.response.write(
        jsonEncode({
          'path': request.uri.path,
          'query': request.uri.query,
          'authorization': auth,
          'body': utf8.decode(body),
        }),
      );
      await request.response.close();
    });

    final handler = createGatewayHandler(
      serviceLocator: DefaultServiceLocator(),
      kernelFuture: Future<KernelService?>.value(null),
      liteAgentSdk: LiteAgentSDK(baseUrl: 'http://127.0.0.1:9527/api/v1'),
      enableLogging: false,
      harnessKitClient: HarnessKitClient(
        baseUri: Uri.parse('http://127.0.0.1:${upstream.port}'),
        internalBearerToken: internalToken,
      ),
    );
    gateway = await shelf_io.serve(handler, InternetAddress.loopbackIPv4, 0);
    gatewayUrl = 'http://127.0.0.1:${gateway.port}';
  });

  tearDown(() async {
    await gateway.close(force: true);
    await upstream.close(force: true);
  });

  test(
    'HarnessKit accepts every AppKit token and forwards the sidecar token',
    () async {
      final missing = await http.get(
        Uri.parse('$gatewayUrl/harnesskit/healthz'),
      );
      expect(missing.statusCode, 401);

      final otherRegistration = await http.post(
        Uri.parse('$gatewayUrl/appkit/register'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({'bundleId': 'com.test.otherApp'}),
      );
      final otherToken =
          (jsonDecode(otherRegistration.body) as Map<String, dynamic>)['token'];
      final other = await http.get(
        Uri.parse('$gatewayUrl/harnesskit/healthz'),
        headers: {'authorization': 'Bearer $otherToken'},
      );
      expect(other.statusCode, 200);
      final otherPayload = jsonDecode(other.body) as Map<String, dynamic>;
      expect(otherPayload['path'], '/healthz');
      expect(otherPayload['authorization'], 'Bearer $internalToken');

      final registration = await http.post(
        Uri.parse('$gatewayUrl/appkit/register'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({'bundleId': 'com.litevar.agentosHarness'}),
      );
      expect(registration.statusCode, 200);
      final token =
          (jsonDecode(registration.body) as Map<String, dynamic>)['token'];
      expect(token, isA<String>());

      final response = await http.post(
        Uri.parse('$gatewayUrl/harnesskit/echo?runId=42'),
        headers: {
          'authorization': 'Bearer $token',
          'content-type': 'application/json',
        },
        body: jsonEncode({'hello': 'harness'}),
      );
      expect(response.statusCode, 200);
      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      expect(payload['path'], '/echo');
      expect(payload['query'], 'runId=42');
      expect(payload['authorization'], 'Bearer $internalToken');
      expect(payload['body'], jsonEncode({'hello': 'harness'}));
    },
  );
}
