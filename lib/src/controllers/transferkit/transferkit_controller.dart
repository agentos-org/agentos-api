import 'dart:async';
import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../../locator.dart';
import '../../middleware.dart';
import '../../services/appkit/appkit_service.dart';
import '../../services/authkit/authkit_service.dart';
import '../../services/transferkit/transferkit_service.dart';

/// TransferKit controller for file transfer between AgentOS devices.
class TransferKitController {
  TransferKitController({
    required TransferKitService transferKitService,
    required AppKitService appKitService,
    AuthKitService? authKitService,
    String Function(String bundleId)? dataDirResolver,
  }) : _service = transferKitService,
       _appKitService = appKitService,
       _authKitService = authKitService,
       _dataDirResolver = dataDirResolver;

  final TransferKitService _service;
  final AppKitService _appKitService;
  final AuthKitService? _authKitService;
  final String Function(String bundleId)? _dataDirResolver;

  Router get router {
    final router = Router();
    router.post('/send', requireBearer()(_send));
    router.get('/transfers', requireBearer()(_listTransfers));
    router.get('/transfers/<transferId>/status', _getStatusHandler);
    router.get('/transfers/<transferId>/stream', _streamProgressHandler);
    router.post('/transfers/<transferId>/cancel', _cancelHandler);
    router.get('/receive/stream', requireBearer()(_receiveStream));
    router.put('/receive/policy', requireBearer()(_setPolicy));
    router.get('/receive/policy', requireBearer()(_getPolicy));
    router.post('/history', requireBearer()(_addHistory));
    router.get('/history', requireBearer()(_getHistory));
    router.delete('/history/<recordId>', _deleteHistoryHandler);
    router.delete('/history', requireBearer()(_clearHistory));
    return router;
  }

  Future<Response> _getStatusHandler(Request request, String transferId) async {
    final token = extractBearerToken(request);
    if (token == null || token.isEmpty) return unauthorizedResponse();
    if (!_appKitService.isTokenValid(token)) return unauthorizedResponse();
    return _getStatus(request, transferId);
  }

  Response _streamProgressHandler(Request request, String transferId) {
    final token = extractBearerToken(request);
    if (token == null || token.isEmpty) return unauthorizedResponse();
    if (!_appKitService.isTokenValid(token)) return unauthorizedResponse();
    return _streamProgress(request, transferId);
  }

  Future<Response> _cancelHandler(Request request, String transferId) async {
    final token = extractBearerToken(request);
    if (token == null || token.isEmpty) return unauthorizedResponse();
    if (!_appKitService.isTokenValid(token)) return unauthorizedResponse();
    return _cancel(request, transferId);
  }

  Future<Response> _send(Request request) async {
    final token = bearerTokenFrom(request);
    if (token == null) return unauthorizedResponse();

    final bundleId = _appKitService.bundleIdForToken(token);
    if (bundleId == null) return unauthorizedResponse('Invalid app token');

    if (!_service.isAvailable) {
      return Response(503,
        body: jsonEncode({'error': 'Nearby transfer is not available'}),
        headers: {'content-type': 'application/json'},
      );
    }

    final body = await request.readAsString();
    Map<String, dynamic> payload;
    try {
      payload = jsonDecode(body) as Map<String, dynamic>;
    } catch (_) {
      return Response(400, body: 'Invalid JSON');
    }

    final targetDeviceId = payload['targetDeviceId'] as String?;
    if (targetDeviceId == null || targetDeviceId.isEmpty) {
      return Response(400, body: 'targetDeviceId is required');
    }

    final targetBundleId = payload['targetBundleId'] as String?;

    final rawFiles = payload['files'] as List?;
    if (rawFiles == null || rawFiles.isEmpty) {
      return Response(400, body: 'files is required and must not be empty');
    }

    final files = rawFiles.map((f) {
      final m = f as Map<String, dynamic>;
      return TransferFileInfo(
        fileName: m['fileName'] as String? ?? '',
        size: m['size'] as int? ?? 0,
        filePath: m['filePath'] as String? ?? '',
        mimeType: m['mimeType'] as String?,
      );
    }).toList();

    final dataDir = _dataDirResolver?.call(bundleId);

    // Resolve userId from the app grant for this bundleId
    final grant = await _authKitService?.getGrantForBundle(bundleId);
    final userId = grant?.userId;

    final session = await _service.sendFiles(
      targetDeviceId: targetDeviceId,
      bundleId: bundleId,
      files: files,
      dataDir: dataDir,
      userId: userId,
      targetBundleId: targetBundleId,
    );

    if (session == null) {
      return Response(400,
        body: jsonEncode({'error': 'Transfer failed or path validation error'}),
        headers: {'content-type': 'application/json'},
      );
    }

    if (session.state == TransferState.failed) {
      return Response(502,
        body: jsonEncode({
          'error': session.errorMessage ?? 'Target device unreachable',
          'transferId': session.transferId,
          'state': 'failed',
        }),
        headers: {'content-type': 'application/json'},
      );
    }

    return Response.ok(
      jsonEncode(session.toJson()),
      headers: {'content-type': 'application/json'},
    );
  }

  Future<Response> _listTransfers(Request request) async {
    final token = bearerTokenFrom(request);
    if (token == null) return unauthorizedResponse();

    final bundleId = _appKitService.bundleIdForToken(token);
    if (bundleId == null) return unauthorizedResponse('Invalid app token');

    final transfers = _service.getTransfersForBundle(bundleId);
    return Response.ok(
      jsonEncode(transfers.map((t) => t.toJson()).toList()),
      headers: {'content-type': 'application/json'},
    );
  }

  Future<Response> _getStatus(Request request, String transferId) async {
    final session = _service.getTransferStatus(transferId);
    if (session == null) {
      return Response.notFound(
        jsonEncode({'error': 'Transfer not found'}),
        headers: {'content-type': 'application/json'},
      );
    }

    return Response.ok(
      jsonEncode(session.toJson()),
      headers: {'content-type': 'application/json'},
    );
  }

  Response _streamProgress(Request request, String transferId) {
    final session = _service.getTransferStatus(transferId);
    if (session == null) {
      return Response.notFound('Transfer not found');
    }

    StreamSubscription<TransferSession>? sub;
    Timer? keepAlive;
    final controller = StreamController<List<int>>(
      onCancel: () {
        sub?.cancel();
        keepAlive?.cancel();
      },
    );

    sub = _service.transferProgressStream
        .where((s) => s.transferId == transferId)
        .listen(
      (s) {
        final data = jsonEncode(s.toJson());
        controller.add(utf8.encode('data: $data\n\n'));
        if (s.state == TransferState.completed ||
            s.state == TransferState.failed) {
          keepAlive?.cancel();
          controller.close();
        }
      },
      onDone: () {
        keepAlive?.cancel();
        controller.close();
      },
      onError: (e) {
        keepAlive?.cancel();
        controller.close();
      },
    );

    keepAlive = Timer.periodic(
      const Duration(seconds: 15),
      (_) => controller.add(utf8.encode(': keep-alive\n\n')),
    );

    return Response.ok(
      controller.stream,
      headers: {
        'content-type': 'text/event-stream',
        'cache-control': 'no-cache',
        'connection': 'keep-alive',
      },
      context: {'shelf.io.buffer_output': false},
    );
  }

  Future<Response> _cancel(Request request, String transferId) async {
    final success = _service.cancelTransfer(transferId);
    if (!success) {
      return Response(400,
        body: jsonEncode({'error': 'Cannot cancel transfer'}),
        headers: {'content-type': 'application/json'},
      );
    }

    return Response.ok(
      jsonEncode({'status': 'cancelled'}),
      headers: {'content-type': 'application/json'},
    );
  }

  Response _receiveStream(Request request) {
    final token = bearerTokenFrom(request);
    if (token == null) return unauthorizedResponse();
    final callerBundleId = _appKitService.bundleIdForToken(token);
    if (callerBundleId == null) return unauthorizedResponse('Invalid app token');

    final incomingStream = _service.getIncomingStream();
    if (incomingStream == null) {
      return Response.ok(
        const Stream<List<int>>.empty(),
        headers: {
          'content-type': 'text/event-stream',
          'cache-control': 'no-cache',
          'connection': 'keep-alive',
        },
        context: {'shelf.io.buffer_output': false},
      );
    }

    StreamSubscription<IncomingTransferEvent>? sub;
    Timer? keepAlive;
    final controller = StreamController<List<int>>(
      onCancel: () {
        sub?.cancel();
        keepAlive?.cancel();
      },
    );

    sub = incomingStream
        .where((event) =>
            event.targetBundleId == null ||
            event.targetBundleId == callerBundleId)
        .listen(
      (event) {
        final data = jsonEncode(event.toJson());
        controller.add(utf8.encode('event: file.received\ndata: $data\n\n'));
      },
      onDone: () {
        keepAlive?.cancel();
        controller.close();
      },
      onError: (e) {
        keepAlive?.cancel();
        controller.close();
      },
    );

    keepAlive = Timer.periodic(
      const Duration(seconds: 15),
      (_) => controller.add(utf8.encode(': keep-alive\n\n')),
    );

    return Response.ok(
      controller.stream,
      headers: {
        'content-type': 'text/event-stream',
        'cache-control': 'no-cache',
        'connection': 'keep-alive',
      },
      context: {'shelf.io.buffer_output': false},
    );
  }

  Future<Response> _setPolicy(Request request) async {
    final body = await request.readAsString();
    Map<String, dynamic> payload;
    try {
      payload = jsonDecode(body) as Map<String, dynamic>;
    } catch (_) {
      return Response(400, body: 'Invalid JSON');
    }

    final policyStr = payload['policy'] as String?;
    if (policyStr == null) {
      return Response(400, body: 'policy is required');
    }

    final policy = FileReceivePolicy.values.firstWhere(
      (p) => p.name == policyStr,
      orElse: () => FileReceivePolicy.autoAccept,
    );

    final bundleId = payload['bundleId'] as String?;
    await _service.setPolicy(policy, bundleId: bundleId);

    return Response.ok(
      jsonEncode({'policy': policy.name, 'bundleId': bundleId}),
      headers: {'content-type': 'application/json'},
    );
  }

  Future<Response> _getPolicy(Request request) async {
    final token = bearerTokenFrom(request);
    final bundleId = token != null ? _appKitService.bundleIdForToken(token) : null;

    final policy = await _service.getPolicy(bundleId: bundleId);
    return Response.ok(
      jsonEncode({'policy': policy.name, 'bundleId': bundleId}),
      headers: {'content-type': 'application/json'},
    );
  }

  // --- History ---

  Future<Response> _addHistory(Request request) async {
    final token = bearerTokenFrom(request);
    if (token == null) return unauthorizedResponse();
    final bundleId = _appKitService.bundleIdForToken(token);
    if (bundleId == null) return unauthorizedResponse('Invalid app token');

    final body = await request.readAsString();
    Map<String, dynamic> payload;
    try {
      payload = jsonDecode(body) as Map<String, dynamic>;
    } catch (_) {
      return Response(400, body: 'Invalid JSON');
    }

    final deviceId = payload['deviceId'] as String? ?? '';
    final userId = payload['userId'] as String?;

    final record = TransferHistoryRecord(
      id: payload['id'] as String? ?? '',
      direction: TransferDirection.values.firstWhere(
        (d) => d.name == (payload['direction'] as String? ?? 'send'),
        orElse: () => TransferDirection.send,
      ),
      peerDeviceId: payload['peerDeviceId'] as String? ?? '',
      peerName: payload['peerName'] as String? ?? '',
      peerAvatarUrl: payload['peerAvatarUrl'] as String?,
      files: ((payload['files'] as List?) ?? [])
          .map((f) => TransferHistoryFile.fromJson(f as Map<String, dynamic>))
          .toList(),
      totalSize: payload['totalSize'] as int? ?? 0,
      state: TransferState.values.firstWhere(
        (s) => s.name == (payload['state'] as String? ?? 'completed'),
        orElse: () => TransferState.completed,
      ),
      timestamp: payload['timestamp'] != null
          ? DateTime.tryParse(payload['timestamp'] as String) ?? DateTime.now()
          : DateTime.now(),
      savedDir: payload['savedDir'] as String?,
    );

    await _service.addHistory(record, deviceId: deviceId, userId: userId);

    return Response.ok(
      jsonEncode({'status': 'added', 'id': record.id}),
      headers: {'content-type': 'application/json'},
    );
  }

  Future<Response> _deleteHistoryHandler(Request request, String recordId) async {
    final token = extractBearerToken(request);
    if (token == null || token.isEmpty) return unauthorizedResponse();
    if (!_appKitService.isTokenValid(token)) return unauthorizedResponse();
    return _deleteHistory(request, recordId);
  }

  Future<Response> _getHistory(Request request) async {
    final token = bearerTokenFrom(request);
    if (token == null) return unauthorizedResponse();
    final bundleId = _appKitService.bundleIdForToken(token);
    if (bundleId == null) return unauthorizedResponse('Invalid app token');

    final deviceId = request.url.queryParameters['deviceId'] ?? '';
    final userId = request.url.queryParameters['userId'];

    final records = await _service.getHistory(
      deviceId: deviceId,
      userId: userId,
    );
    return Response.ok(
      jsonEncode(records.map((r) => r.toJson()).toList()),
      headers: {'content-type': 'application/json'},
    );
  }

  Future<Response> _deleteHistory(Request request, String recordId) async {
    final token = bearerTokenFrom(request);
    if (token == null) return unauthorizedResponse();
    final bundleId = _appKitService.bundleIdForToken(token);
    if (bundleId == null) return unauthorizedResponse('Invalid app token');

    final deviceId = request.url.queryParameters['deviceId'] ?? '';
    final userId = request.url.queryParameters['userId'];

    final deleted = await _service.deleteHistory(
      recordId,
      deviceId: deviceId,
      userId: userId,
    );
    if (!deleted) {
      return Response.notFound(
        jsonEncode({'error': 'Record not found'}),
        headers: {'content-type': 'application/json'},
      );
    }
    return Response.ok(
      jsonEncode({'status': 'deleted'}),
      headers: {'content-type': 'application/json'},
    );
  }

  Future<Response> _clearHistory(Request request) async {
    final token = bearerTokenFrom(request);
    if (token == null) return unauthorizedResponse();
    final bundleId = _appKitService.bundleIdForToken(token);
    if (bundleId == null) return unauthorizedResponse('Invalid app token');

    final deviceId = request.url.queryParameters['deviceId'] ?? '';
    final userId = request.url.queryParameters['userId'];

    await _service.clearHistory(deviceId: deviceId, userId: userId);
    return Response.ok(
      jsonEncode({'status': 'cleared'}),
      headers: {'content-type': 'application/json'},
    );
  }
}
