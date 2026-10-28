import 'dart:async';
import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../../middleware.dart';
import '../../models/app/app_models.dart';
import '../../services/appkit/appkit_service.dart';
import '../../services/appkit/opentool_availability_service.dart';
import '../../services/appkit/opentool_provisioning_service.dart';

class AppKitController {
  AppKitController({
    AppKitService? service,
    OpenToolProvisioner? openToolProvisioner,
    OpenToolAvailabilityTracker? openToolAvailabilityTracker,
  }) : _service = service ?? AppKitService(),
       _openToolProvisioner = openToolProvisioner,
       _openToolAvailabilityTracker = openToolAvailabilityTracker;

  final AppKitService _service;
  final OpenToolProvisioner? _openToolProvisioner;
  final OpenToolAvailabilityTracker? _openToolAvailabilityTracker;

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
    late final AppBundleDto bundle;
    try {
      bundle = AppBundleDto.fromJson(payload);
    } on FormatException catch (error) {
      requestLogger.warning('AppKit register: ${error.message}');
      return Response(400, body: error.message);
    }
    if (bundle.bundleId.isEmpty) {
      requestLogger.warning('AppKit register: missing bundleId.');
      return Response(400, body: 'bundleId is required');
    }
    var token = _service.registerBundle(bundle);
    final availabilityGeneration = _openToolAvailabilityTracker
        ?.replaceBundleDeclarations(bundle.bundleId, bundle.opentoolServers);
    if (bundle.opentoolServers.isNotEmpty) {
      final results = await Future.wait(
        bundle.opentoolServers.map(
          (declaration) => _ensureOpenToolServer(
            bundle.bundleId,
            declaration,
            availabilityGeneration: availabilityGeneration,
          ),
        ),
      );
      token = token.withOpenToolServers(results);
    }
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
    final toolEventScope = request.url.queryParameters['toolEvents'];
    AppKitToolEventSubscription? toolEvents;
    if (toolEventScope != null) {
      if (toolEventScope == 'all') {
        toolEvents = AppKitToolEventSubscription(bundleId: '', all: true);
      } else if (toolEventScope == 'selected') {
        final toolIds = <String>{
          ...(request.url.queryParametersAll['toolId'] ?? const <String>[]),
          ...(request.url.queryParameters['toolIds']
                  ?.split(',')
                  .map((id) => id.trim()) ??
              const <String>[]),
        }..removeWhere((id) => id.isEmpty);
        toolEvents = AppKitToolEventSubscription(
          bundleId: '',
          all: false,
          toolIds: toolIds,
        );
      } else {
        return Response(400, body: 'toolEvents must be "all" or "selected"');
      }
    }
    final bundleId = _service.bundleIdForToken(token);
    requestLogger.info('AppKit subscribe: accepted bundleId=$bundleId');
    final source = _service.subscribe(token, toolEvents: toolEvents);
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
          final id = event.id == null ? '' : 'id: ${event.id}\n';
          final payload = '${id}event: ${event.event}\ndata: ${event.data}\n\n';
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

  Future<OpenToolRegistrationDto> _ensureOpenToolServer(
    String bundleId,
    OpenToolServerDeclarationDto declaration, {
    int? availabilityGeneration,
  }) async {
    final provisioner = _openToolProvisioner;
    if (provisioner == null) {
      _publishProvisionFailure(
        bundleId,
        OpenToolProvisioningFailure(
          declaration: declaration,
          code: 'daemonUnavailable',
          message: 'OpenTool provisioning is not configured',
        ),
      );
      return OpenToolRegistrationDto(
        ref: declaration.ref,
        name: declaration.name,
        status: OpenToolRegistrationStatus.starting,
      );
    }
    final result = await provisioner.ensureRunning(
      declaration,
      onSuccess: (success) {
        _publishProvisionSuccess(bundleId, success);
        _trackOpenTool(
          bundleId,
          availabilityGeneration,
          success.declaration,
          success.server,
          success.id,
        );
      },
      onFailure: (failure) => _publishProvisionFailure(bundleId, failure),
    );
    final server = result.server;
    final id = result.id;
    if (result.status == OpenToolRegistrationStatus.running &&
        server != null &&
        id != null) {
      _trackOpenTool(bundleId, availabilityGeneration, declaration, server, id);
    }
    return result;
  }

  void _trackOpenTool(
    String bundleId,
    int? generation,
    OpenToolServerDeclarationDto declaration,
    OpenToolResolvedServerDto server,
    String id,
  ) {
    final tracker = _openToolAvailabilityTracker;
    if (tracker == null || generation == null) {
      return;
    }
    tracker.track(
      bundleId: bundleId,
      generation: generation,
      declaration: declaration,
      server: server,
      toolId: id,
    );
  }

  void _publishProvisionSuccess(
    String bundleId,
    OpenToolProvisioningSuccess success,
  ) {
    _service.publishAppEvent(
      bundleId,
      _service.createAppEvent(
        type: AppEventType.toolkitProvisionSucceeded,
        source: 'toolkit',
        subject: success.declaration.ref,
        data: success.toEventData(),
      ),
    );
  }

  void _publishProvisionFailure(
    String bundleId,
    OpenToolProvisioningFailure failure,
  ) {
    _service.publishAppEvent(
      bundleId,
      _service.createAppEvent(
        type: AppEventType.toolkitProvisionFailed,
        source: 'toolkit',
        subject: failure.declaration.ref,
        data: failure.toEventData(),
      ),
    );
  }
}
