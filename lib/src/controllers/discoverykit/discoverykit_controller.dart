import 'dart:async';
import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../../locator.dart';
import '../../middleware.dart';
import '../../services/appkit/appkit_service.dart';
import '../../services/discoverykit/discoverykit_service.dart';

/// DiscoveryKit controller for nearby AgentOS device discovery.
class DiscoveryKitController {
  DiscoveryKitController({
    required DiscoveryKitService service,
    required AppKitService appKitService,
  }) : _service = service,
       _appKitService = appKitService;

  final DiscoveryKitService _service;
  final AppKitService _appKitService;

  Router get router {
    final router = Router();
    router.get('/peers', requireBearer()(_getPeers));
    router.get('/peers/stream', requireBearer()(_streamPeers));
    router.get('/self', requireBearer()(_getSelf));
    router.post('/register', requireBearer()(_register));
    router.post('/unregister', requireBearer()(_unregister));
    return router;
  }

  Future<Response> _register(Request request) async {
    final token = bearerTokenFrom(request);
    if (token == null) return unauthorizedResponse();

    final bundleId = _appKitService.bundleIdForToken(token);
    if (bundleId == null) return unauthorizedResponse('Invalid app token');

    final body = await request.readAsString();
    Map<String, dynamic> payload = {};
    if (body.isNotEmpty) {
      try {
        payload = jsonDecode(body) as Map<String, dynamic>;
      } catch (_) {
        return Response(400, body: 'Invalid JSON');
      }
    }

    final policyStr = payload['receivePolicy'] as String?;
    final receivePolicy = policyStr != null
        ? FileReceivePolicy.values.where((p) => p.name == policyStr).firstOrNull
        : null;

    final success = await _service.registerApp(
      bundleId: bundleId,
      receivePolicy: receivePolicy,
    );

    if (!success) {
      return Response(503,
        body: jsonEncode({'error': 'Discovery service not available'}),
        headers: {'content-type': 'application/json'},
      );
    }

    return Response.ok(
      jsonEncode({'status': 'registered', 'bundleId': bundleId}),
      headers: {'content-type': 'application/json'},
    );
  }

  Future<Response> _unregister(Request request) async {
    final token = bearerTokenFrom(request);
    if (token == null) return unauthorizedResponse();

    final bundleId = _appKitService.bundleIdForToken(token);
    if (bundleId == null) return unauthorizedResponse('Invalid app token');

    _service.unregisterApp(bundleId);

    return Response.ok(
      jsonEncode({'status': 'unregistered', 'bundleId': bundleId}),
      headers: {'content-type': 'application/json'},
    );
  }

  Future<Response> _getPeers(Request request) async {
    if (!_service.isAvailable) {
      return Response.ok(
        jsonEncode([]),
        headers: {'content-type': 'application/json'},
      );
    }

    final token = bearerTokenFrom(request);
    final callerBundleId =
        token != null ? _appKitService.bundleIdForToken(token) : null;

    final peers = _service.getPeers(callerBundleId: callerBundleId);
    return Response.ok(
      jsonEncode(peers.map((p) => p.toJson()).toList()),
      headers: {'content-type': 'application/json'},
    );
  }

  Response _streamPeers(Request request) {
    final peerStream = _service.getPeerEventStream();
    if (peerStream == null) {
      return Response.ok(
        const Stream<List<int>>.empty(),
        headers: {
          'content-type': 'text/event-stream',
          'cache-control': 'no-cache',
          'connection': 'keep-alive',
        },
      );
    }

    final token = bearerTokenFrom(request);
    final callerBundleId =
        token != null ? _appKitService.bundleIdForToken(token) : null;

    StreamSubscription<PeerDeviceEvent>? sub;
    final controller = StreamController<List<int>>(
      onCancel: () => sub?.cancel(),
    );

    sub = peerStream.listen(
      (event) {
        final device = event.device;
        // Apply same app-level filtering as getPeers
        final Map<String, dynamic> deviceJson;
        if (callerBundleId != null) {
          final filteredApps = device.apps
              .where((a) => !a.isDeviceLevel
                  && a.bundleId != null
                  && a.bundleId == callerBundleId)
              .toList();
          if (filteredApps.isEmpty && event.type != PeerDeviceEventType.left) {
            return;
          }
          deviceJson = device.toJson();
          deviceJson['apps'] = filteredApps.map((a) => a.toJson()).toList();
        } else {
          deviceJson = device.toJson();
          deviceJson['apps'] = <Map<String, dynamic>>[];
        }

        final data = jsonEncode({
          'type': event.type.name,
          'device': deviceJson,
        });
        controller.add(utf8.encode('event: peer.${event.type.name}\ndata: $data\n\n'));
      },
      onDone: () => controller.close(),
      onError: (e) => controller.close(),
    );

    return Response.ok(
      controller.stream,
      headers: {
        'content-type': 'text/event-stream',
        'cache-control': 'no-cache',
        'connection': 'keep-alive',
      },
    );
  }

  Future<Response> _getSelf(Request request) async {
    final token = bearerTokenFrom(request);
    final bundleId = token != null ? _appKitService.bundleIdForToken(token) : null;

    final selfInfo = _service.getSelfInfo(callerBundleId: bundleId);
    if (selfInfo == null) {
      return Response.ok(
        jsonEncode({'nearbyTransferEnabled': false}),
        headers: {'content-type': 'application/json'},
      );
    }

    return Response.ok(
      jsonEncode(selfInfo),
      headers: {'content-type': 'application/json'},
    );
  }
}
