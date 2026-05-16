import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:agentos_api/src/controllers/agentkit/agentkit_controller.dart';
import 'package:liteagent_sdk_dart/liteagent_sdk_dart.dart';
import 'package:opentool_dart/opentool_client.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';

const _bearerToken = 'example-token';
const _prompt =
    'Use tool function `sequentiallyRead` to read all items from storage, '
    'then summarize the items.';

Future<void> main() async {
  final env = await _loadExampleEnv();
  final liteAgentBaseUrl =
      env['liteAgentBaseUrl'] ?? 'http://127.0.0.1:9527/api/v1';

  final gatewayServer = await _startAgentKitGateway(liteAgentBaseUrl);
  final gatewayBaseUrl = 'http://127.0.0.1:${gatewayServer.port}/agentkit';

  try {
    final sessionId = await _initSession(gatewayBaseUrl, env);
    stdout.writeln('[session] $sessionId');
    stdout.writeln('[prompt] $_prompt');

    final done = Completer<void>();
    final sseStream = await _chat(gatewayBaseUrl, sessionId, _prompt);
    final subscription = _decodeSse(sseStream).listen(
      (event) async {
        await _onSseEvent(
          gatewayBaseUrl: gatewayBaseUrl,
          sessionId: sessionId,
          event: event,
        );
      },
      onDone: () {
        stdout.writeln('[sseDone]');
        if (!done.isCompleted) done.complete();
      },
      onError: (Object error, StackTrace stackTrace) {
        stderr.writeln('[sseError] $error');
        if (!done.isCompleted) done.completeError(error, stackTrace);
      },
    );

    try {
      await done.future.timeout(const Duration(seconds: 120));
    } on TimeoutException {
      stderr.writeln('[timeout] chat did not finish within 120 seconds.');
      await _getJson('$gatewayBaseUrl/stop?sessionId=$sessionId');
    } finally {
      await subscription.cancel();
      await _getJson('$gatewayBaseUrl/clear?sessionId=$sessionId');
    }
  } finally {
    await gatewayServer.close(force: true);
  }
}

Future<HttpServer> _startAgentKitGateway(String liteAgentBaseUrl) {
  final agentKitController = AgentKitController(
    sdk: LiteAgentSDK(baseUrl: liteAgentBaseUrl),
    kernelFuture: Future.value(null),
  );
  final router = Router()..mount('/agentkit/', agentKitController.router.call);
  return shelf_io.serve(router.call, InternetAddress.loopbackIPv4, 0);
}

Future<String> _initSession(
  String gatewayBaseUrl,
  Map<String, String> env,
) async {
  final openToolJson = await File(
    'example/mock/driver/mock-tool.json',
  ).readAsString();

  final response = await _postJson('$gatewayBaseUrl/initSession', {
    'systemPrompt':
        'You are a tools caller. When the user asks to read storage items, '
        'call the stream tool sequentiallyRead and then summarize its data.',
    'llmConfig': {
      'baseUrl': _requiredEnv(env, 'baseUrl'),
      'apiKey': _requiredEnv(env, 'apiKey'),
      'model': _requiredEnv(env, 'model'),
    },
    'callbackOpenTool': {'opentool': openToolJson, 'timeout': 120},
    'timeoutSeconds': 120,
  });

  if (response.statusCode != HttpStatus.ok) {
    throw StateError('initSession failed: ${response.body}');
  }
  final json = jsonDecode(response.body) as Map<String, dynamic>;
  return json['sessionId'] as String;
}

Future<Stream<String>> _chat(
  String gatewayBaseUrl,
  String sessionId,
  String prompt,
) async {
  final uri = Uri.parse('$gatewayBaseUrl/chat?sessionId=$sessionId');
  final client = HttpClient();
  final request = await client.postUrl(uri);
  request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $_bearerToken');
  request.headers.set(HttpHeaders.acceptHeader, 'text/event-stream');
  request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
  request.add(
    utf8.encode(
      jsonEncode({
        'content': [
          {'type': ContentType.text, 'message': prompt},
        ],
        'isChunk': true,
      }),
    ),
  );
  final response = await request.close();
  if (response.statusCode != HttpStatus.ok) {
    final body = await utf8.decodeStream(response);
    client.close(force: true);
    throw StateError('chat failed: ${response.statusCode} $body');
  }
  return response
      .transform(utf8.decoder)
      .transform(
        StreamTransformer.fromHandlers(
          handleDone: (sink) {
            client.close(force: true);
            sink.close();
          },
        ),
      );
}

Future<void> _onSseEvent({
  required String gatewayBaseUrl,
  required String sessionId,
  required _SseEvent event,
}) async {
  final eventName = event.event ?? SSEEventType.MESSAGE;
  final json = jsonDecode(event.data);

  if (eventName == SSEEventType.CHUNK) {
    stdout.writeln('[chunk] $json');
    return;
  }

  if (eventName == SSEEventType.MESSAGE) {
    stdout.writeln('[message] $json');
    return;
  }

  if (eventName != SSEEventType.FUNCTION_CALL) {
    stdout.writeln('[$eventName] $json');
    return;
  }

  final payload = Map<String, dynamic>.from(json as Map);
  final functionCall = FunctionCall.fromJson(
    Map<String, dynamic>.from(payload['functionCall'] as Map),
  );
  final isStream =
      payload['stream'] == true || functionCall.name == 'sequentiallyRead';
  stdout.writeln('[functionCall] ${functionCall.toJson()} stream=$isStream');

  if (!isStream) {
    await _postJson('$gatewayBaseUrl/callback?sessionId=$sessionId', {
      'id': functionCall.id,
      'result': {'error': 'This example only handles stream tools.'},
    });
    return;
  }

  await _runSequentiallyRead(functionCall, (event, toolReturn) async {
    stdout.writeln('[streamCallback:$event] ${toolReturn.toJson()}');
    final response = await _postJson(
      '$gatewayBaseUrl/streamCallback?sessionId=$sessionId',
      {'event': event, 'toolReturn': toolReturn.toJson()},
    );
    if (response.statusCode != HttpStatus.ok) {
      throw StateError('streamCallback failed: ${response.body}');
    }
  });
}

Future<void> _runSequentiallyRead(
  FunctionCall functionCall,
  Future<void> Function(String event, ToolReturn toolReturn) onStream,
) async {
  if (functionCall.name != 'sequentiallyRead') {
    await onStream(
      EventType.ERROR,
      ToolReturn(
        id: functionCall.id,
        result: {'error': 'Unsupported stream tool: ${functionCall.name}'},
      ),
    );
    return;
  }

  for (final item in const ['Hello', 'World']) {
    await onStream(
      EventType.DATA,
      ToolReturn(id: functionCall.id, result: {'data': item}),
    );
    await Future<void>.delayed(const Duration(seconds: 2));
  }
  await onStream(EventType.DONE, ToolReturn(id: functionCall.id, result: {}));
}

Future<_HttpJsonResponse> _postJson(
  String url,
  Map<String, dynamic> body,
) async {
  final client = HttpClient();
  try {
    final request = await client.postUrl(Uri.parse(url));
    request.headers.set(
      HttpHeaders.authorizationHeader,
      'Bearer $_bearerToken',
    );
    request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
    request.add(utf8.encode(jsonEncode(body)));
    final response = await request.close();
    return _HttpJsonResponse(
      statusCode: response.statusCode,
      body: await utf8.decodeStream(response),
    );
  } finally {
    client.close(force: true);
  }
}

Future<_HttpJsonResponse> _getJson(String url) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(Uri.parse(url));
    request.headers.set(
      HttpHeaders.authorizationHeader,
      'Bearer $_bearerToken',
    );
    final response = await request.close();
    return _HttpJsonResponse(
      statusCode: response.statusCode,
      body: await utf8.decodeStream(response),
    );
  } finally {
    client.close(force: true);
  }
}

Future<Map<String, String>> _loadExampleEnv() async {
  final file = File('example/.env');
  if (!await file.exists()) {
    throw StateError(
      'Missing example/.env. Run: cp example/.env.example example/.env',
    );
  }

  final result = <String, String>{};
  for (final line in await file.readAsLines()) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
    final separator = trimmed.indexOf('=');
    if (separator == -1) continue;
    final key = trimmed.substring(0, separator).trim();
    final value = trimmed.substring(separator + 1).trim();
    result[key] = value;
  }
  return result;
}

String _requiredEnv(Map<String, String> env, String key) {
  final value = env[key]?.trim();
  if (value == null || value.isEmpty || value.startsWith('sk-your-')) {
    throw StateError('Please set `$key` in example/.env.');
  }
  return value;
}

class _SseEvent {
  const _SseEvent({required this.event, required this.data});

  final String? event;
  final String data;
}

Stream<_SseEvent> _decodeSse(Stream<String> input) async* {
  var buffer = '';
  await for (final chunk in input) {
    buffer += chunk;

    while (true) {
      final separatorIndex = buffer.indexOf('\n\n');
      if (separatorIndex == -1) break;

      final frame = buffer.substring(0, separatorIndex);
      buffer = buffer.substring(separatorIndex + 2);

      final parsed = _parseSseFrame(frame);
      if (parsed != null) yield parsed;
    }
  }

  final trailing = _parseSseFrame(buffer);
  if (trailing != null) yield trailing;
}

_SseEvent? _parseSseFrame(String frame) {
  if (frame.trim().isEmpty) return null;

  final lines = frame.split(RegExp(r'\r?\n'));
  String? eventName;
  final dataLines = <String>[];

  for (final line in lines) {
    if (line.startsWith('event:')) {
      eventName = line.substring('event:'.length).trim();
      continue;
    }
    if (line.startsWith('data:')) {
      var value = line.substring('data:'.length);
      if (value.startsWith(' ')) value = value.substring(1);
      dataLines.add(value);
    }
  }

  if (dataLines.isEmpty) return null;
  return _SseEvent(event: eventName, data: dataLines.join('\n'));
}

class _HttpJsonResponse {
  const _HttpJsonResponse({required this.statusCode, required this.body});

  final int statusCode;
  final String body;
}
