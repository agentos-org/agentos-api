import 'dart:convert';

import 'package:agentos_api/agentos_api.dart';
import 'package:agentos_kernel/agentos_kernel.dart' show KernelService;
import 'package:liteagent_sdk_dart/liteagent_sdk_dart.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

void main() {
  late _FakeHarness upstream;
  late Handler gateway;

  setUp(() {
    upstream = _FakeHarness();
    gateway = createGatewayHandler(
      serviceLocator: DefaultServiceLocator(),
      kernelFuture: Future<KernelService?>.value(null),
      liteAgentSdk: LiteAgentSDK(baseUrl: 'http://127.0.0.1:1/api/v1'),
      enableLogging: false,
      harnessKitClient: upstream,
    );
  });

  Future<String> register(String bundleId) async {
    final response = await gateway(
      Request(
        'POST',
        Uri.parse('http://localhost/appkit/register'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({'bundleId': bundleId}),
      ),
    );
    expect(response.statusCode, 200);
    return (jsonDecode(await response.readAsString()) as Map)['token']
        as String;
  }

  Future<(Response, Map<String, dynamic>)> call(
    String token,
    String method,
    String path, [
    Map<String, Object?>? body,
  ]) async {
    final response = await gateway(
      Request(
        method,
        Uri.parse('http://localhost/harnesskit$path'),
        headers: {
          'authorization': 'Bearer $token',
          'content-type': 'application/json',
        },
        body: body == null ? null : jsonEncode(body),
      ),
    );
    return (
      response,
      jsonDecode(await response.readAsString()) as Map<String, dynamic>,
    );
  }

  test('fork scopes both source and target for each app, but not the built-in host', () async {
    final a = await register('com.test.appA');
    final b = await register('com.test.appB');
    final host = await register('com.litevar.agentosHarness');
    final request = {
      'sourceThreadId': 'host-thread',
      'threadId': 'copy',
      'throughTurnId': 'turn-1',
      'title': 'copy',
    };
    await call(a, 'POST', '/v1/threads', request);
    final appA = Map<String, dynamic>.from(upstream.body!);
    await call(b, 'POST', '/v1/threads', request);
    final appB = Map<String, dynamic>.from(upstream.body!);
    expect(appA['sourceThreadId'], isNot('host-thread'));
    expect(appA['threadId'], isNot('copy'));
    expect(appA['sourceThreadId'], isNot(appB['sourceThreadId']));
    expect(appA['throughTurnId'], 'turn-1');
    await call(host, 'POST', '/v1/threads', request);
    expect(upstream.body, request);
  });

  test(
    'run IDs from receipts and snapshots round trip into steering',
    () async {
      final token = await register('com.test.appA');
      final (_, receipt) = await call(
        token,
        'POST',
        '/v1/threads/chat/commands',
        {'type': 'submit_turn', 'commandId': 'one', 'input': 'hello'},
      );
      final publicRunId = receipt['runId'] as String;
      expect(publicRunId, isNot('run-7'));
      await call(token, 'POST', '/v1/threads/chat/commands', {
        'type': 'submit_turn',
        'commandId': 'steer',
        'queueMode': 'steer',
        'runId': publicRunId,
      });
      expect(upstream.body!['runId'], 'run-7');
      final (_, snapshot) = await call(token, 'GET', '/v1/threads/chat');
      final summaries = snapshot['runSummaries'] as List;
      final metadata = (snapshot['messages'] as List).first['metadata'] as Map;
      expect(snapshot['threadId'], 'chat');
      expect(snapshot['activeRunId'], publicRunId);
      expect(summaries.single['runId'], publicRunId);
      expect(summaries.single['threadId'], 'chat');
      expect(metadata['harnessRunId'], publicRunId);
      expect((metadata['harnessOutcome'] as Map)['runId'], publicRunId);
      expect((metadata['custom'] as Map)['runId'], 'user-content');
    },
  );

  test('rejected command receipts expose the caller command ID', () async {
    final token = await register('com.test.appA');
    final (response, receipt) = await call(
      token,
      'POST',
      '/v1/threads/chat/commands',
      {'type': 'reject', 'commandId': 'original-command', 'threadId': 'chat'},
    );
    expect(response.statusCode, 400);
    expect(receipt['status'], 'rejected');
    expect(receipt['commandId'], 'original-command');
    expect(receipt['threadId'], 'chat');
  });

  test(
    'an app can fork its own thread but not a host or another app thread',
    () async {
      final a = await register('com.test.appA');
      final b = await register('com.test.appB');
      final original = {
        'sourceThreadId': 'owned',
        'threadId': 'branch',
        'throughTurnId': 'turn-1',
        'title': 'branch',
      };
      await call(a, 'POST', '/v1/threads', original);
      upstream.knownSources.add(upstream.body!['sourceThreadId'] as String);
      upstream.enforceForkOwnership = true;
      final (own, _) = await call(a, 'POST', '/v1/threads', original);
      expect(own.statusCode, 201);
      final (other, _) = await call(b, 'POST', '/v1/threads', original);
      expect(other.statusCode, 404);
      final (host, _) = await call(a, 'POST', '/v1/threads', {
        ...original,
        'sourceThreadId': 'host-thread',
      });
      expect(host.statusCode, 404);
    },
  );

  test('third-party apps cannot inspect or mutate host workspaces', () async {
    final token = await register('com.test.appA');
    final host = await register('com.litevar.agentosHarness');
    for (final (method, path, body)
        in <(String, String, Map<String, Object?>?)>[
          ('GET', '/v1/workspaces', null),
          (
            'POST',
            '/v1/workspaces',
            {
              'folderPaths': ['/private'],
            },
          ),
          ('POST', '/v1/workspaces/local/validate', {}),
          ('GET', '/admin/api/harness/skills', null),
          ('POST', '/v1/threads/chat/runs', {'workspaceId': 'local'}),
          (
            'POST',
            '/v1/threads/chat/commands',
            {'type': 'set_thread_workspace', 'workspaceId': null},
          ),
          (
            'POST',
            '/v1/threads/chat/commands',
            {'type': 'submit_turn', 'workspaceId': 'local'},
          ),
        ]) {
      final previousCalls = upstream.calls;
      final (response, value) = await call(token, method, path, body);
      expect(response.statusCode, 403, reason: '$method $path');
      expect((value['error'] as Map)['code'], 'harness_host_access_forbidden');
      expect(upstream.calls, previousCalls);
    }
    final (hostResponse, _) = await call(host, 'GET', '/v1/workspaces');
    expect(hostResponse.statusCode, 200);
  });

  test(
    'existing host workspace bindings cannot be used by third-party apps',
    () async {
      final token = await register('com.test.appA');
      upstream.workspaceBound = true;
      final (response, value) = await call(
        token,
        'POST',
        '/v1/threads/chat/commands',
        {'type': 'resume_run', 'commandId': 'resume', 'targetRunId': 'run-7'},
      );
      expect(response.statusCode, 403);
      expect((value['error'] as Map)['code'], 'harness_host_access_forbidden');
      // A running task can still be stopped even if its old binding is denied.
      final (stop, _) = await call(token, 'POST', '/v1/threads/chat/commands', {
        'type': 'stop_turn',
        'commandId': 'stop',
        'targetTurnId': 'turn-1',
      });
      expect(stop.statusCode, 202);
    },
  );
}

final class _FakeHarness extends HarnessKitClient {
  _FakeHarness()
    : super(
        baseUri: Uri.parse('http://127.0.0.1:1'),
        internalBearerToken: 'dummy',
      );
  Map<String, dynamic>? body;
  int calls = 0;
  final Set<String> knownSources = {'host-thread'};
  bool enforceForkOwnership = false;
  bool workspaceBound = false;
  @override
  Future<HarnessKitClientResponse> send({
    required String method,
    required String path,
    Map<String, String>? headers,
    Map<String, String>? queryParameters,
    List<int>? body,
    bool streamResponse = false,
    String? actorBundleId,
  }) async {
    calls++;
    this.body = body == null || body.isEmpty
        ? null
        : jsonDecode(utf8.decode(body)) as Map<String, dynamic>;
    Map<String, Object?> response;
    var status = 200;
    if (path == '/v1/threads' && method == 'POST') {
      final source = this.body!['sourceThreadId'] as String;
      status = enforceForkOwnership && !knownSources.contains(source)
          ? 404
          : 201;
      response = status == 201
          ? {'threadId': this.body!['threadId'], 'messages': []}
          : {
              'error': {'code': 'not_found'},
            };
    } else if (path.endsWith('/commands')) {
      status = this.body!['type'] == 'reject' ? 400 : 202;
      response = {
        'threadId': this.body!['threadId'],
        'commandId': this.body!['commandId'],
        'runId': 'run-7',
        'status': status == 400 ? 'rejected' : 'accepted',
      };
    } else {
      final threadId = Uri.decodeComponent(path.split('/').last);
      response = {
        'threadId': threadId,
        'activeRunId': 'run-7',
        if (workspaceBound)
          'workspaceContext': {'workspaceId': 'host-workspace'},
        'runSummaries': [
          {'threadId': threadId, 'runId': 'run-7'},
        ],
        'messages': [
          {
            'role': 'assistant',
            'content': 'unchanged',
            'metadata': {
              'harnessRunId': 'run-7',
              'harnessOutcome': {'status': 'failed', 'runId': 'run-7'},
              'custom': {'runId': 'user-content'},
            },
          },
        ],
      };
    }
    return HarnessKitClientResponse(
      statusCode: status,
      headers: {'content-type': 'application/json'},
      bodyBytes: utf8.encode(jsonEncode(response)),
    );
  }
}
