import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:agentos_api/agentos_api.dart';
import 'package:agentos_kernel/agentos_kernel.dart' show KernelService;
import 'package:http/http.dart';
import 'package:liteagent_sdk_dart/liteagent_sdk_dart.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:test/test.dart';

const String _validLaunchUri =
    'agentos://oauth2/authorize?request_id=ar_83d94c';

void main() {
  late HttpServer server;
  late String host;
  late AuthKitBridge bridge;
  late String appToken;

  setUp(() async {
    AuthKitBridge? captured;
    final handler = createGatewayHandler(
      serviceLocator: DefaultServiceLocator(),
      kernelFuture: Future<KernelService?>.value(null),
      liteAgentSdk: LiteAgentSDK(baseUrl: 'http://127.0.0.1:9527/api/v1'),
      enableLogging: false,
      onAuthKitBridgeReady: (b) => captured = b,
    );
    bridge = captured!;

    server = await shelf_io.serve(handler, InternetAddress.loopbackIPv4, 0);
    host = 'http://${server.address.host}:${server.port}';
    appToken = await _registerBundle(host, 'com.demo.appauth');
  });

  tearDown(() => server.close(force: true));

  group('POST /authkit/open', () {
    test('rejects requests without a valid app token', () async {
      final missing = await post(
        Uri.parse('$host/authkit/open'),
        body: jsonEncode({'launchUri': _validLaunchUri}),
      );
      expect(missing.statusCode, 401);

      final bogus = await post(
        Uri.parse('$host/authkit/open'),
        headers: {'authorization': 'Bearer sk-not-registered'},
        body: jsonEncode({'launchUri': _validLaunchUri}),
      );
      expect(bogus.statusCode, 401);
    });

    test('returns desktop_not_ready when no handler is registered', () async {
      final response = await _open(host, appToken, _validLaunchUri);

      expect(response.statusCode, 503);
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      expect(body['status'], 'failed');
      expect(body['errorCode'], 'desktop_not_ready');
    });

    test('delivers the launchUri untouched and reports opened', () async {
      AuthKitDelivery? delivered;
      bridge.registerHandler((delivery) async {
        delivered = delivery;
        return AuthKitPresentationHandle.opened();
      });

      final response = await _open(host, appToken, _validLaunchUri);

      expect(response.statusCode, 200);
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      expect(body['status'], 'opened');
      expect(delivered?.launchUri, _validLaunchUri);
      expect(delivered?.requestId, 'ar_83d94c');
      // bundleId 只用于本机识别，授权主体是 Server 侧的 client_id
      expect(delivered?.bundleId, 'com.demo.appauth');
    });

    test('does not wait for a decision by default', () async {
      final decision = Completer<AuthKitPresentation>();
      bridge.registerHandler((_) async {
        return AuthKitPresentationHandle.opened(
          decision: decision.future,
        );
      });

      final response = await _open(host, appToken, _validLaunchUri);

      // 用户还没操作，但请求已经返回
      expect(decision.isCompleted, isFalse);
      expect(jsonDecode(response.body)['status'], 'opened');
      decision.complete(
        const AuthKitPresentation(
          status: AuthKitPresentationStatus.submitted,
        ),
      );
    });

    test('waits for the decision when asked', () async {
      final decision = Completer<AuthKitPresentation>();
      bridge.registerHandler((_) async {
        return AuthKitPresentationHandle.opened(
          decision: decision.future,
        );
      });

      final pending = _open(
        host,
        appToken,
        _validLaunchUri,
        waitForDecision: true,
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      decision.complete(
        const AuthKitPresentation(
          status: AuthKitPresentationStatus.denied,
        ),
      );

      final body = jsonDecode((await pending).body) as Map<String, dynamic>;
      expect(body['status'], 'denied');
    });

    test('falls back to opened when the decision wait times out', () async {
      bridge.registerHandler((_) async {
        return AuthKitPresentationHandle.opened(
          decision: Completer<AuthKitPresentation>().future,
        );
      });

      final response = await _open(
        host,
        appToken,
        _validLaunchUri,
        waitForDecision: true,
        timeoutMs: 60,
      );

      expect(jsonDecode(response.body)['status'], 'opened');
    });

    test('surfaces a failed presentation from the host', () async {
      bridge.registerHandler((_) async {
        return const AuthKitPresentationHandle(
          presentation: AuthKitPresentation.failed(
            errorCode: 'desktop_not_logged_in',
          ),
        );
      });

      final response = await _open(host, appToken, _validLaunchUri);

      expect(response.statusCode, 200);
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      expect(body['status'], 'failed');
      expect(body['errorCode'], 'desktop_not_logged_in');
    });

    test('converts a throwing host handler into delivery_failed', () async {
      bridge.registerHandler((_) async => throw StateError('boom'));

      final response = await _open(host, appToken, _validLaunchUri);

      expect(response.statusCode, 200);
      expect(jsonDecode(response.body)['errorCode'], 'delivery_failed');
    });

    test('rejects launch URIs that AgentOS Server would not issue', () async {
      bridge.registerHandler((_) async {
        fail('handler must not be reached for a malformed launchUri');
      });

      const malformed = <String?>[
        null,
        '',
        'https://oauth2/authorize?request_id=ar_1',
        'agentos://open?request_id=ar_1',
        'agentos://oauth2/token?request_id=ar_1',
        'agentos://oauth2/authorize',
      ];

      for (final launchUri in malformed) {
        final response = await post(
          Uri.parse('$host/authkit/open'),
          headers: _authHeaders(appToken),
          body: jsonEncode(
            launchUri == null
                ? <String, dynamic>{}
                : <String, dynamic>{'launchUri': launchUri},
          ),
        );
        expect(
          response.statusCode,
          400,
          reason: 'should reject launchUri=$launchUri',
        );
        expect(
          jsonDecode(response.body)['errorCode'],
          'invalid_launch_uri',
          reason: 'should reject launchUri=$launchUri',
        );
      }
    });
  });

  group('GET /authkit/status', () {
    test('reports handler availability', () async {
      final before = await get(
        Uri.parse('$host/authkit/status'),
        headers: _authHeaders(appToken),
      );
      expect(jsonDecode(before.body)['ready'], isFalse);

      bridge.registerHandler(
        (_) async => AuthKitPresentationHandle.opened(),
      );

      final after = await get(
        Uri.parse('$host/authkit/status'),
        headers: _authHeaders(appToken),
      );
      expect(jsonDecode(after.body)['ready'], isTrue);

      bridge.unregisterHandler();
      final cleared = await get(
        Uri.parse('$host/authkit/status'),
        headers: _authHeaders(appToken),
      );
      expect(jsonDecode(cleared.body)['ready'], isFalse);
    });

    test('requires a valid app token', () async {
      final response = await get(Uri.parse('$host/authkit/status'));
      expect(response.statusCode, 401);
    });
  });

  group('AuthKitLaunchUri', () {
    test('treats request_id as an opaque value', () {
      final parsed = AuthKitLaunchUri.tryParse(
        'agentos://oauth2/authorize?request_id=%20ar_with_space%20&extra=keep',
      );
      expect(parsed?.requestId, 'ar_with_space');
    });

    test('is case-insensitive on scheme and host', () {
      expect(
        AuthKitLaunchUri.tryParse(
          'AgentOS://OAuth2/authorize?request_id=ar_1',
        )?.requestId,
        'ar_1',
      );
    });
  });
}

Map<String, String> _authHeaders(String token) => {
      'authorization': 'Bearer $token',
      'content-type': 'application/json',
    };

Future<Response> _open(
  String host,
  String token,
  String launchUri, {
  bool? waitForDecision,
  int? timeoutMs,
}) {
  return post(
    Uri.parse('$host/authkit/open'),
    headers: _authHeaders(token),
    body: jsonEncode(<String, dynamic>{
      'launchUri': launchUri,
      if (waitForDecision != null) 'waitForDecision': waitForDecision,
      if (timeoutMs != null) 'timeoutMs': timeoutMs,
    }),
  );
}

Future<String> _registerBundle(String host, String bundleId) async {
  final response = await post(
    Uri.parse('$host/appkit/register'),
    headers: {'content-type': 'application/json'},
    body: jsonEncode(<String, dynamic>{'bundleId': bundleId}),
  );
  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw StateError('registerBundle failed: ${response.statusCode}');
  }
  return (jsonDecode(response.body) as Map<String, dynamic>)['token'] as String;
}
