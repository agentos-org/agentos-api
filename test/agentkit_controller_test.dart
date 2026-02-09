import 'dart:convert';

import 'package:agentos_api/src/controllers/agentkit/agentkit_controller.dart';
import 'package:agentos_api/src/services/agentkit/liteagent_client.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

class _FakeLiteagentClient extends LiteagentClient {
  _FakeLiteagentClient({this.availableConfig});

  final Map<String, dynamic>? availableConfig;
  List<int>? capturedBody;

  @override
  Future<Map<String, dynamic>?> getAvailableLlmConfigJson() async {
    return availableConfig;
  }

  @override
  Future<LiteagentClientResponse> send({
    required String method,
    required String path,
    Map<String, String>? headers,
    Map<String, String>? queryParameters,
    List<int>? body,
    bool streamResponse = false,
    String? userId,
    String? bundleId,
  }) async {
    capturedBody = body;
    return LiteagentClientResponse(
      statusCode: 200,
      headers: {'content-type': 'application/json'},
      bodyBytes: utf8.encode('{}'),
    );
  }
}

void main() {
  test(
    'injects llmConfig fallback for /chat when request llmConfig is absent',
    () async {
      final fakeClient = _FakeLiteagentClient(
        availableConfig: <String, dynamic>{
          'baseUrl': 'http://127.0.0.1:52010',
          'apiKey': '',
          'model': 'qwen',
        },
      );
      final controller = AgentKitController(client: fakeClient);

      final response = await controller.router.call(
        Request(
          'POST',
          Uri.parse('http://localhost/chat'),
          headers: <String, String>{
            'authorization': 'Bearer user-token',
            'content-type': 'application/json',
          },
          body: jsonEncode(<String, dynamic>{'content': <dynamic>[]}),
        ),
      );

      expect(response.statusCode, 200);
      final forwarded =
          jsonDecode(utf8.decode(fakeClient.capturedBody!))
              as Map<String, dynamic>;
      expect(forwarded['llmConfig'], isNotNull);
      expect(forwarded['llmConfig']['baseUrl'], 'http://127.0.0.1:52010');
      expect(forwarded['llmConfig']['model'], 'qwen');
    },
  );

  test('keeps provided llmConfig for /chat without overriding', () async {
    final fakeClient = _FakeLiteagentClient(
      availableConfig: <String, dynamic>{
        'baseUrl': 'http://127.0.0.1:52010',
        'apiKey': '',
        'model': 'fallback-model',
      },
    );
    final controller = AgentKitController(client: fakeClient);

    final response = await controller.router.call(
      Request(
        'POST',
        Uri.parse('http://localhost/chat'),
        headers: <String, String>{
          'authorization': 'Bearer user-token',
          'content-type': 'application/json',
        },
        body: jsonEncode(<String, dynamic>{
          'content': <dynamic>[],
          'llmConfig': <String, dynamic>{
            'baseUrl': 'http://127.0.0.1:60000',
            'apiKey': 'k',
            'model': 'explicit-model',
          },
        }),
      ),
    );

    expect(response.statusCode, 200);
    final forwarded =
        jsonDecode(utf8.decode(fakeClient.capturedBody!))
            as Map<String, dynamic>;
    expect(forwarded['llmConfig']['baseUrl'], 'http://127.0.0.1:60000');
    expect(forwarded['llmConfig']['model'], 'explicit-model');
  });
}
