import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:agentos_api/src/controllers/agentkit/agentkit_controller.dart';
import 'package:liteagent_sdk_dart/liteagent_sdk_dart.dart';
import 'package:opentool_dart/opentool_client.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';

Future<void> main() async {
  final capturedForward = Completer<_ForwardedStreamCallback>();
  final liteAgentServer = await _startFakeLiteAgent(capturedForward);
  final gatewayServer = await _startAgentKitGateway(liteAgentServer.port);

  try {
    final sessionId = 'example-session';
    final eventToolReturn = EventToolReturn(
      eventType: EventType.DATA,
      toolReturn: ToolReturn(
        id: 'tool-call-1',
        result: {'chunk': 'hello from streamCallback', 'index': 1},
      ),
    );

    final gatewayResponse = await _postJson(
      Uri.parse(
        'http://127.0.0.1:${gatewayServer.port}'
        '/agentkit/streamCallback?sessionId=$sessionId',
      ),
      headers: const {'authorization': 'Bearer example-token'},
      body: eventToolReturn.toJson(),
    );

    if (gatewayResponse.statusCode != HttpStatus.ok) {
      throw StateError(
        'Gateway returned ${gatewayResponse.statusCode}: '
        '${gatewayResponse.body}',
      );
    }

    final forwarded = await capturedForward.future.timeout(
      const Duration(seconds: 3),
    );

    _expectEquals(sessionId, forwarded.sessionId, 'sessionId');
    _expectEquals(eventToolReturn.toJson(), forwarded.body, 'forwarded body');

    stdout.writeln('streamCallback forwarded successfully.');
    stdout.writeln('Gateway response: ${gatewayResponse.body}');
    stdout.writeln('Forwarded body: ${jsonEncode(forwarded.body)}');
  } finally {
    await gatewayServer.close(force: true);
    await liteAgentServer.close(force: true);
  }
}

Future<HttpServer> _startFakeLiteAgent(
  Completer<_ForwardedStreamCallback> capturedForward,
) async {
  final router = Router()
    ..post('/api/v1/streamCallback', (Request request) async {
      final sessionId = request.url.queryParameters['sessionId'];
      final body = jsonDecode(await request.readAsString());
      if (sessionId == null || body is! Map<String, dynamic>) {
        return Response.badRequest(
          body: jsonEncode({'error': 'invalid streamCallback request'}),
          headers: const {'content-type': 'application/json'},
        );
      }

      if (!capturedForward.isCompleted) {
        capturedForward.complete(
          _ForwardedStreamCallback(sessionId: sessionId, body: body),
        );
      }

      return Response.ok(
        jsonEncode({'status': 'ok'}),
        headers: const {'content-type': 'application/json'},
      );
    });

  return shelf_io.serve(router.call, InternetAddress.loopbackIPv4, 0);
}

Future<HttpServer> _startAgentKitGateway(int liteAgentPort) {
  final agentKitController = AgentKitController(
    sdk: LiteAgentSDK(baseUrl: 'http://127.0.0.1:$liteAgentPort/api/v1'),
    kernelFuture: Future.value(null),
  );
  final router = Router()..mount('/agentkit/', agentKitController.router.call);

  return shelf_io.serve(router.call, InternetAddress.loopbackIPv4, 0);
}

Future<_HttpJsonResponse> _postJson(
  Uri uri, {
  required Map<String, String> headers,
  required Map<String, dynamic> body,
}) async {
  final client = HttpClient();
  try {
    final request = await client.postUrl(uri);
    request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
    headers.forEach(request.headers.set);
    request.add(utf8.encode(jsonEncode(body)));

    final response = await request.close();
    final responseBody = await utf8.decodeStream(response);
    return _HttpJsonResponse(
      statusCode: response.statusCode,
      body: responseBody,
    );
  } finally {
    client.close(force: true);
  }
}

void _expectEquals(Object? expected, Object? actual, String label) {
  if (jsonEncode(expected) != jsonEncode(actual)) {
    throw StateError(
      '$label mismatch\n'
      'expected: ${jsonEncode(expected)}\n'
      'actual:   ${jsonEncode(actual)}',
    );
  }
}

class _ForwardedStreamCallback {
  const _ForwardedStreamCallback({required this.sessionId, required this.body});

  final String sessionId;
  final Map<String, dynamic> body;
}

class _HttpJsonResponse {
  const _HttpJsonResponse({required this.statusCode, required this.body});

  final int statusCode;
  final String body;
}
