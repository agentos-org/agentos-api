import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../../middleware.dart';
import '../../models/notify/notify_models.dart';
import '../../services/appkit/appkit_service.dart';
import '../../services/notifykit/notifykit_service.dart';

/// App-facing NotifyKit API.
///
/// The AppKit bearer token identifies the source App. The request deliberately
/// has no priority, grouping or deduplication fields.
class NotifyKitController {
  NotifyKitController({required this.service, required this.appKitService});

  final NotifyKitService service;
  final AppKitService appKitService;

  Router get router {
    final router = Router();
    router.post('/notifications', requireBearer()(_publish));
    return router;
  }

  Future<Response> _publish(Request request) async {
    final token = bearerTokenFrom(request);
    final bundleId = token == null
        ? null
        : appKitService.bundleIdForToken(token);
    if (bundleId == null) return unauthorizedResponse();

    final body = await _readJsonBody(request);
    if (body == null) return _jsonError(400, 'invalid JSON payload');
    try {
      final event = NotifyKitAppEvent(
        eventType: _string(body['eventType']) ?? '',
        subjectId: _string(body['subjectId']),
        title: _string(body['title']) ?? '',
        message: _string(body['message']) ?? '',
      );
      final notification = service.publishApp(bundleId: bundleId, event: event);
      return _json({'accepted': true, 'notification': notification.toJson()});
    } on NotifyKitRateLimitException catch (error) {
      return Response(
        429,
        body: jsonEncode({
          'error': 'notification rate limit exceeded',
          'retryAfterSeconds': error.retryAfterSeconds,
        }),
        headers: {
          'content-type': 'application/json',
          'retry-after': '${error.retryAfterSeconds}',
        },
      );
    } on FormatException catch (error) {
      return _jsonError(400, error.message);
    }
  }

  Future<Map<String, dynamic>?> _readJsonBody(Request request) async {
    try {
      final decoded = jsonDecode(await request.readAsString());
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } on Object {
      return null;
    }
    return null;
  }

  static String? _string(Object? value) {
    if (value is! String) return null;
    final normalized = value.trim();
    return normalized.isEmpty ? null : normalized;
  }

  static Response _json(Object data) => Response.ok(
    jsonEncode(data),
    headers: const {'content-type': 'application/json'},
  );

  static Response _jsonError(int status, String message) => Response(
    status,
    body: jsonEncode({'error': message}),
    headers: const {'content-type': 'application/json'},
  );
}
