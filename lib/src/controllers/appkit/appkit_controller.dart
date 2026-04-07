import 'dart:async';
import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../../middleware.dart';
import '../../models/app/app_models.dart';
import '../../services/appkit/appkit_service.dart';

class AppKitController {
  AppKitController({AppKitService? service})
    : _service = service ?? AppKitService();

  final AppKitService _service;

  Router get router {
    final router = Router();
    router.post('/register', _registerBundle);
    router.get('/subscribe', requireBearer()(_subscribe));
    return router;
  }

  Future<Response> _registerBundle(Request request) async {
    final payload = await _readJsonBody(request);
    if (payload == null) {
      requestLogger.warning('AppKit register: invalid JSON payload.');
      return Response(400, body: 'Invalid JSON payload.');
    }
    final bundle = AppBundleDto.fromJson(payload);
    if (bundle.bundleId.isEmpty) {
      requestLogger.warning('AppKit register: missing bundleId.');
      return Response(400, body: 'bundleId is required');
    }
    final token = _service.registerBundle(bundle);
    requestLogger.info('AppKit register: bundleId=${bundle.bundleId}');
    final body = jsonEncode(token.toJson());
    return Response.ok(body, headers: {'content-type': 'application/json'});
  }

  Response _subscribe(Request request) {
    final token = bearerTokenFrom(request);
    if (token == null || token.isEmpty) {
      requestLogger.warning('AppKit subscribe: missing bearer token.');
      return unauthorizedResponse();
    }
    if (!_service.isTokenValid(token)) {
      requestLogger.warning('AppKit subscribe: invalid bearer token.');
      return unauthorizedResponse();
    }
    final bundleId = _service.bundleIdForToken(token);
    requestLogger.info('AppKit subscribe: accepted bundleId=$bundleId');
    final source = _service.subscribe(token);
    final controller = StreamController<List<int>>();
    StreamSubscription<EventDto>? subscription;
    Timer? keepAlive;

    void stop() {
      keepAlive?.cancel();
      keepAlive = null;
      subscription?.cancel();
      subscription = null;
      if (!controller.isClosed) {
        controller.close();
      }
    }

    controller.onListen = () {
      subscription = source.listen(
        (event) {
          final payload = 'event: ${event.event}\ndata: ${event.data}\n\n';
          controller.add(utf8.encode(payload));
        },
        onError: controller.addError,
        onDone: stop,
      );
      keepAlive = Timer.periodic(
        const Duration(seconds: 15),
        (_) => controller.add(utf8.encode(': keep-alive\n\n')),
      );
    };
    controller.onCancel = stop;

    return Response.ok(
      controller.stream,
      headers: const {
        'content-type': 'text/event-stream',
        'cache-control': 'no-cache',
        'connection': 'keep-alive',
      },
      context: const {'shelf.io.buffer_output': false},
    );
  }

  Future<Map<String, dynamic>?> _readJsonBody(Request request) async {
    try {
      final rawBody = await request.readAsString();
      if (rawBody.isEmpty) {
        return <String, dynamic>{};
      }
      final decoded = jsonDecode(rawBody);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
      return null;
    } catch (_) {
      return null;
    }
  }
}
