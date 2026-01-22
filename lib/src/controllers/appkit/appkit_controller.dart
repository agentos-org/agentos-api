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
      return Response(400, body: 'Invalid JSON payload.');
    }
    final bundle = AppBundleDto.fromJson(payload);
    if (bundle.bundleId.isEmpty) {
      return Response(400, body: 'bundleId is required');
    }
    final token = _service.registerBundle(bundle);
    final body = jsonEncode(token.toJson());
    return Response.ok(body, headers: {'content-type': 'application/json'});
  }

  Response _subscribe(Request request) {
    final token = bearerTokenFrom(request);
    if (token == null || token.isEmpty) {
      return unauthorizedResponse();
    }
    final stream = _service.subscribe(token).map((event) {
      final payload = 'event: ${event.event}\ndata: ${event.data}\n\n';
      return utf8.encode(payload);
    });
    return Response.ok(stream, headers: {'content-type': 'text/event-stream'});
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
