import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:agentos_api/agentos_api.dart';
import 'package:agentos_kernel/agentos_kernel.dart';
import 'package:http/http.dart';
import 'package:liteagent_sdk_dart/liteagent_sdk_dart.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:test/test.dart';

void main() {
  late HttpServer server;
  late String host;

  setUp(() async {
    // Use new Gateway API
    final serviceLocator = DefaultServiceLocator();
    // Create a Future that resolves to null (no kernel in tests)
    final kernelFuture = Future<KernelService?>.value(null);
    // Create SDK with dummy baseUrl (no real backend in tests)
    final liteAgentSdk = LiteAgentSDK(baseUrl: 'http://127.0.0.1:9527/api/v1');
    final handler = createGatewayHandler(
      serviceLocator: serviceLocator,
      kernelFuture: kernelFuture,
      liteAgentSdk: liteAgentSdk,
      enableLogging: false,
    );
    server = await shelf_io.serve(
      handler,
      InternetAddress.loopbackIPv4,
      0,
    );
    host = 'http://${server.address.host}:${server.port}';
  });

  tearDown(() => server.close(force: true));

  test('404', () async {
    final response = await get(Uri.parse('$host/foobar'));
    expect(response.statusCode, 404);
  });

  test('Root endpoint', () async {
    final response = await get(Uri.parse('$host/'));
    expect(response.statusCode, 200);
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    expect(payload['name'], 'AgentOS API Gateway');
    expect(payload['endpoints'], isNotEmpty);
  });

  test('Root version', () async {
    final response = await get(Uri.parse('$host/version'));
    expect(response.statusCode, 200);
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    expect(payload['version'], _readPubspecVersion());
  });

  test('IntentKit submitRaw requires bearer', () async {
    final response = await post(
      Uri.parse('$host/intentkit/submitRaw'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode(<String, dynamic>{
        'content': [
          {'type': 'text', 'message': 'hello'},
        ],
      }),
    );
    expect(response.statusCode, 401);
  });

  test('AgentKit create agent requires bearer', () async {
    final unauthorized = await post(
      Uri.parse('$host/agentkit/agent/create'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode(<String, dynamic>{'name': 'demo-agent'}),
    );
    expect(unauthorized.statusCode, 401);
  });

  test('AgentKit endpoints require bearer', () async {
    final initRes = await post(Uri.parse('$host/agentkit/initSession'));
    expect(initRes.statusCode, 401);

    final chatRes = await post(
      Uri.parse('$host/agentkit/chat'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode(<String, dynamic>{'content': []}),
    );
    expect(chatRes.statusCode, 401);
  });

  test('Toolkit no auth required', () async {
    // ToolKit no longer requires authentication, direct access allowed
    final response = await get(Uri.parse('$host/toolkit/tools'));
    // Should not return 401 (would return 401 when auth was required)
    // May return 404 (path not found), 502 (proxy error), 503 (service unavailable) or 200 (ok)
    expect(response.statusCode, isNot(401));
  });

  test('LLMKit no auth required', () async {
    // LLMKit no longer requires authentication, direct access allowed
    final response = await post(
      Uri.parse('$host/llmkit/text/v1/chat/completions'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({'messages': []}),
    );
    // Should not return 401 (would return 401 when auth was required)
    // May return 502 (proxy error), 503 (service unavailable) or 200 (ok)
    expect(response.statusCode, isNot(401));
  });

  test('AppKit register bundle', () async {
    final registerRes = await post(
      Uri.parse('$host/appkit/register'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode(<String, String>{'bundleId': 'com.demo.app'}),
    );
    expect(registerRes.statusCode, 200);
    final registerPayload =
        jsonDecode(registerRes.body) as Map<String, dynamic>;
    final token = registerPayload['token'] as String;
    expect(token, startsWith('sk-'));
  });
}

String _readPubspecVersion() {
  final pubspec = File('pubspec.yaml').readAsStringSync();
  final match = RegExp(
    r'^version:\s*([^\s#]+)',
    multiLine: true,
  ).firstMatch(pubspec);
  if (match == null) {
    throw StateError('version not found in pubspec.yaml');
  }
  return match.group(1)!;
}
