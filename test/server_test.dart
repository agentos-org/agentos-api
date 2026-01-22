import 'dart:convert';
import 'dart:io';

import 'package:agentos_api/agentos_api.dart';
import 'package:http/http.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:test/test.dart';

void main() {
  late HttpServer server;
  late String host;

  setUp(() async {
    server = await shelf_io.serve(
      createHandler(),
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

  test('Root version', () async {
    final response = await get(Uri.parse('$host/version'));
    expect(response.statusCode, 200);
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    expect(payload['version'], _readPubspecVersion());
  });

  test('Intent preset-intents', () async {
    final response = await post(
      Uri.parse('$host/api/intent/preset-intents'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode(<String, String>{'appName': 'demo-app'}),
    );
    expect(response.statusCode, 200);
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    final presets = payload['presetIntents'] as List<dynamic>;
    expect(presets.length, inInclusiveRange(0, 5));
    if (presets.isNotEmpty) {
      final first = presets.first as Map<String, dynamic>;
      expect(first['source'], 'system');
      expect(first['title'], isNotEmpty);
    }
  }, skip: 'Intent module disabled');

  test('Intent suggestions', () async {
    final response = await post(
      Uri.parse('$host/api/intent/suggestions'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode(<String, String>{
        'appName': 'demo-app',
        'raw': 'draft status update',
      }),
    );
    expect(response.statusCode, 200);
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    final suggestions = payload['intentSuggestions'] as List<dynamic>;
    expect(suggestions.length, inInclusiveRange(0, 5));
    if (suggestions.isNotEmpty) {
      final first = suggestions.first as Map<String, dynamic>;
      expect(first['id'], isNotEmpty);
      expect(first['source'], isIn(<String>['system', 'model']));
    }
  }, skip: 'Intent module disabled');

  test('Intent candidates', () async {
    final response = await post(
      Uri.parse('$host/api/intent/candidates'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode(<String, String>{
        'appName': 'demo-app',
        'full': 'Send daily metrics report',
      }),
    );
    expect(response.statusCode, 200);
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    final candidates = payload['intentCandidates'] as List<dynamic>;
    expect(candidates.length, 5);
    for (final item in candidates) {
      final candidate = item as Map<String, dynamic>;
      expect(candidate['source'], 'model');
      expect((candidate['confidence'] as num), inInclusiveRange(0, 1));
      expect(candidate['title'], isNotEmpty);
      expect(candidate['description'], isNotEmpty);
    }
  }, skip: 'Intent module disabled');

  test('AgentKit create agent requires bearer', () async {
    final unauthorized = await post(
      Uri.parse('$host/api/agentkit/agent/create'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode(<String, dynamic>{'name': 'demo-agent'}),
    );
    expect(unauthorized.statusCode, 401);
  });

  test('AgentKit endpoints require bearer', () async {
    final initRes = await post(Uri.parse('$host/api/agentkit/initSession'));
    expect(initRes.statusCode, 401);

    final chatRes = await post(
      Uri.parse('$host/api/agentkit/chat'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode(<String, dynamic>{'content': []}),
    );
    expect(chatRes.statusCode, 401);
  });

  test('Toolkit tool list requires bearer', () async {
    final unauthorized = await get(Uri.parse('$host/api/toolkit/tools'));
    expect(unauthorized.statusCode, 401);

    final response = await get(
      Uri.parse('$host/api/toolkit/tools'),
      headers: {'authorization': 'Bearer token-123'},
    );
    expect(response.statusCode, 200);
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    final tools = payload['tools'] as List<dynamic>;
    expect(tools, isNotEmpty);
  });

  test('AppKit register bundle', () async {
    final registerRes = await post(
      Uri.parse('$host/api/appkit/register'),
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
