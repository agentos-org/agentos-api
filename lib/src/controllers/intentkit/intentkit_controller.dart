import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../../middleware.dart';
import '../../models/intentkit/intentkit_models.dart';
import '../../services/intentkit/intentkit_service.dart';

class IntentKitController {
  IntentKitController({required IntentKitService service}) : _service = service;

  final IntentKitService _service;

  Router get router {
    final router = Router();
    final guard = requireBearer();
    router.post('/submitRaw', guard(_submitRaw));
    router.post('/submitIntent', guard(_submitIntent));
    router.post('/confirmJob', guard(_confirmJob));
    router.post('/suggestNextAction', guard(_suggestNextAction));
    return router;
  }

  Future<Response> _submitRaw(Request request) async {
    final kernel = await _service.resolveKernel();
    if (kernel == null) {
      requestLogger.warning('IntentKit submitRaw: missing kernel config.');
      return Response(503, body: 'IntentKit not configured.');
    }
    final payload = await _readJsonBody(request);
    if (payload == null) {
      requestLogger.warning('IntentKit submitRaw: invalid JSON payload.');
      return Response(400, body: 'Invalid JSON payload.');
    }
    IntentKitSubmitRawRequest parsed;
    try {
      parsed = IntentKitSubmitRawRequest.fromJson(payload);
    } on FormatException catch (error) {
      requestLogger.warning('IntentKit submitRaw: $error');
      return Response(400, body: error.message);
    }
    try {
      final handle = await _service.submitRaw(
        source: parsed.source,
        content: parsed.content,
        data: parsed.data,
      );
      final body = jsonEncode(IntentKitJobHandleDto.fromHandle(handle).toJson());
      return Response.ok(body, headers: {'content-type': 'application/json'});
    } on ArgumentError catch (error) {
      requestLogger.warning('IntentKit submitRaw: $error');
      return Response(400, body: error.message ?? error.toString());
    } on StateError catch (error) {
      requestLogger.warning('IntentKit submitRaw: $error');
      return Response(503, body: error.message);
    } on Exception catch (error) {
      requestLogger.severe('IntentKit submitRaw error: $error');
      return Response(502, body: 'IntentKit submitRaw error: $error');
    }
  }

  Future<Response> _submitIntent(Request request) async {
    final kernel = await _service.resolveKernel();
    if (kernel == null) {
      requestLogger.warning('IntentKit submitIntent: missing kernel config.');
      return Response(503, body: 'IntentKit not configured.');
    }
    final payload = await _readJsonBody(request);
    if (payload == null) {
      requestLogger.warning('IntentKit submitIntent: invalid JSON payload.');
      return Response(400, body: 'Invalid JSON payload.');
    }
    IntentKitSubmitIntentRequest parsed;
    try {
      parsed = IntentKitSubmitIntentRequest.fromJson(payload);
    } on FormatException catch (error) {
      requestLogger.warning('IntentKit submitIntent: $error');
      return Response(400, body: error.message);
    }
    try {
      final handle = await _service.submitIntent(
        source: parsed.source,
        intent: parsed.intent,
      );
      final body = jsonEncode(IntentKitJobHandleDto.fromHandle(handle).toJson());
      return Response.ok(body, headers: {'content-type': 'application/json'});
    } on ArgumentError catch (error) {
      requestLogger.warning('IntentKit submitIntent: $error');
      return Response(400, body: error.message ?? error.toString());
    } on StateError catch (error) {
      requestLogger.warning('IntentKit submitIntent: $error');
      return Response(503, body: error.message);
    } on Exception catch (error) {
      requestLogger.severe('IntentKit submitIntent error: $error');
      return Response(502, body: 'IntentKit submitIntent error: $error');
    }
  }

  Future<Response> _confirmJob(Request request) async {
    final kernel = await _service.resolveKernel();
    if (kernel == null) {
      requestLogger.warning('IntentKit confirmJob: missing kernel config.');
      return Response(503, body: 'IntentKit not configured.');
    }
    final payload = await _readJsonBody(request);
    if (payload == null) {
      requestLogger.warning('IntentKit confirmJob: invalid JSON payload.');
      return Response(400, body: 'Invalid JSON payload.');
    }
    IntentKitConfirmJobRequest parsed;
    try {
      parsed = IntentKitConfirmJobRequest.fromJson(payload);
    } on FormatException catch (error) {
      requestLogger.warning('IntentKit confirmJob: $error');
      return Response(400, body: error.message);
    }
    try {
      final handle = await _service.confirmJob(
        jobId: parsed.jobId,
        confirmed: parsed.confirmed,
      );
      final body = jsonEncode(IntentKitJobHandleDto.fromHandle(handle).toJson());
      return Response.ok(body, headers: {'content-type': 'application/json'});
    } on ArgumentError catch (error) {
      requestLogger.warning('IntentKit confirmJob: $error');
      return Response(400, body: error.message ?? error.toString());
    } on StateError catch (error) {
      requestLogger.warning('IntentKit confirmJob: $error');
      return Response(503, body: error.message);
    } on Exception catch (error) {
      requestLogger.severe('IntentKit confirmJob error: $error');
      return Response(502, body: 'IntentKit confirmJob error: $error');
    }
  }

  Future<Response> _suggestNextAction(Request request) async {
    final kernel = await _service.resolveKernel();
    if (kernel == null) {
      requestLogger.warning('IntentKit suggestNextAction: missing kernel config.');
      return Response(503, body: 'IntentKit not configured.');
    }
    final payload = await _readJsonBody(request);
    if (payload == null) {
      requestLogger.warning('IntentKit suggestNextAction: invalid JSON payload.');
      return Response(400, body: 'Invalid JSON payload.');
    }
    IntentKitSuggestNextActionRequest parsed;
    try {
      parsed = IntentKitSuggestNextActionRequest.fromJson(payload);
    } on FormatException catch (error) {
      requestLogger.warning('IntentKit suggestNextAction: $error');
      return Response(400, body: error.message);
    }
    try {
      final response = await _service.suggestNextAction(
        source: parsed.source,
        allowedActions: parsed.allowedActions,
        memoryLimit: parsed.memoryLimit,
      );
      final body = jsonEncode(response.toJson());
      return Response.ok(body, headers: {'content-type': 'application/json'});
    } on ArgumentError catch (error) {
      requestLogger.warning('IntentKit suggestNextAction: $error');
      return Response(400, body: error.message ?? error.toString());
    } on StateError catch (error) {
      requestLogger.warning('IntentKit suggestNextAction: $error');
      return Response(503, body: error.message);
    } on Exception catch (error) {
      requestLogger.severe('IntentKit suggestNextAction error: $error');
      return Response(502, body: 'IntentKit suggestNextAction error: $error');
    }
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
