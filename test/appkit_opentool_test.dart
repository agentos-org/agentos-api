import 'dart:async';
import 'dart:convert';

import 'package:agentos_api/agentos_api.dart';
import 'package:opentool_daemon/opentool_daemon_client.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

void main() {
  group('AppKit OpenTool registration', () {
    test(
      'returns running, starting, and notFound declaration results',
      () async {
        final service = AppKitService();
        final provisioner = _FakeProvisioner({
          'running': const OpenToolRegistrationDto(
            ref: 'running',
            name: 'opentool-server-running',
            server: OpenToolResolvedServerDto(
              repo: 'native',
              name: 'opentool-server-running',
              tag: '1.2.0',
            ),
            status: OpenToolRegistrationStatus.running,
            id: 'tool-running',
          ),
          'starting': const OpenToolRegistrationDto(
            ref: 'starting',
            name: 'opentool-server-starting',
            server: OpenToolResolvedServerDto(
              repo: 'native',
              name: 'opentool-server-starting',
              tag: '2.0.0',
            ),
            status: OpenToolRegistrationStatus.starting,
          ),
          'missing': const OpenToolRegistrationDto(
            ref: 'missing',
            name: 'opentool-server-missing',
            status: OpenToolRegistrationStatus.notFound,
          ),
        });
        final availabilityTracker = _FakeAvailabilityTracker();
        final controller = AppKitController(
          service: service,
          openToolProvisioner: provisioner,
          openToolAvailabilityTracker: availabilityTracker,
        );

        final response = await controller.router.call(
          Request(
            'POST',
            Uri.parse('http://localhost/register'),
            body: jsonEncode({
              'bundleId': 'com.demo.app',
              'opentoolServers': [
                {'ref': 'running', 'name': 'opentool-server-running'},
                {'ref': 'starting', 'name': 'opentool-server-starting'},
                {'ref': 'missing', 'name': 'opentool-server-missing'},
              ],
            }),
          ),
        );

        expect(response.statusCode, 200);
        final payload = jsonDecode(await response.readAsString()) as Map;
        final servers = payload['opentoolServers'] as List;
        expect(servers, hasLength(3));
        expect(servers[0], {
          'ref': 'running',
          'server': {
            'repo': 'native',
            'name': 'opentool-server-running',
            'tag': '1.2.0',
          },
          'status': 'running',
          'id': 'tool-running',
        });
        expect(servers[1], {
          'ref': 'starting',
          'server': {
            'repo': 'native',
            'name': 'opentool-server-starting',
            'tag': '2.0.0',
          },
          'status': 'starting',
        });
        expect(servers[2], {
          'ref': 'missing',
          'name': 'opentool-server-missing',
          'status': 'notFound',
        });
        expect(availabilityTracker.declarationRefs, [
          'running',
          'starting',
          'missing',
        ]);
        expect(availabilityTracker.trackedRefs, ['running']);
      },
    );

    test('rejects duplicate declaration refs', () async {
      final controller = AppKitController(
        service: AppKitService(),
        openToolProvisioner: _FakeProvisioner(const {}),
      );

      final response = await controller.router.call(
        Request(
          'POST',
          Uri.parse('http://localhost/register'),
          body: jsonEncode({
            'bundleId': 'com.demo.app',
            'opentoolServers': [
              {'ref': 'websearch', 'name': 'one'},
              {'ref': 'websearch', 'name': 'two'},
            ],
          }),
        ),
      );

      expect(response.statusCode, 400);
      expect(await response.readAsString(), contains('must be unique'));
    });

    test('rejects attempts to pin a server tag', () async {
      final controller = AppKitController(
        service: AppKitService(),
        openToolProvisioner: _FakeProvisioner(const {}),
      );

      final response = await controller.router.call(
        Request(
          'POST',
          Uri.parse('http://localhost/register'),
          body: jsonEncode({
            'bundleId': 'com.demo.app',
            'opentoolServers': [
              {
                'ref': 'websearch',
                'name': 'opentool-server-websearch',
                'tag': '1.2.0',
              },
            ],
          }),
        ),
      );

      expect(response.statusCode, 400);
      expect(await response.readAsString(), contains('tag is not supported'));
    });

    test('queues provisioning failures until the app subscribes', () async {
      final service = AppKitService();
      final provisioner = _FakeProvisioner(
        const {
          'websearch': OpenToolRegistrationDto(
            ref: 'websearch',
            name: 'opentool-server-websearch',
            server: OpenToolResolvedServerDto(
              repo: 'native',
              name: 'opentool-server-websearch',
              tag: '1.2.0',
            ),
            status: OpenToolRegistrationStatus.starting,
          ),
        },
        failure: const OpenToolProvisioningFailure(
          declaration: OpenToolServerDeclarationDto(
            ref: 'websearch',
            name: 'opentool-server-websearch',
          ),
          server: OpenToolResolvedServerDto(
            repo: 'native',
            name: 'opentool-server-websearch',
            tag: '1.2.0',
          ),
          code: 'startFailed',
          message: 'process exited',
        ),
      );
      final controller = AppKitController(
        service: service,
        openToolProvisioner: provisioner,
      );

      final registerResponse = await controller.router.call(
        Request(
          'POST',
          Uri.parse('http://localhost/register'),
          body: jsonEncode({
            'bundleId': 'com.demo.app',
            'opentoolServers': [
              {'ref': 'websearch', 'name': 'opentool-server-websearch'},
            ],
          }),
        ),
      );
      final registration =
          jsonDecode(await registerResponse.readAsString()) as Map;
      await Future<void>.delayed(Duration.zero);

      final subscribeResponse = await controller.router.call(
        Request(
          'GET',
          Uri.parse('http://localhost/subscribe'),
          headers: {'authorization': 'Bearer ${registration['token']}'},
        ),
      );
      final chunks = await subscribeResponse
          .read()
          .take(2)
          .toList()
          .timeout(const Duration(seconds: 2));
      final body = utf8.decode(chunks.expand((chunk) => chunk).toList());

      expect(body, contains('event: welcome'));
      expect(body, contains('event: appEvent'));
      expect(body, contains('"type":"toolkit.provision.failed"'));
      expect(body, contains('"source":"toolkit"'));
      expect(body, contains('"subject":"websearch"'));
      expect(body, contains('"code":"startFailed"'));
      expect(body, isNot(contains('event: callApp')));
    });

    test('queues provisioning success until the app subscribes', () async {
      final service = AppKitService();
      const declaration = OpenToolServerDeclarationDto(
        ref: 'websearch',
        name: 'opentool-server-websearch',
      );
      const server = OpenToolResolvedServerDto(
        repo: 'native',
        name: 'opentool-server-websearch',
        tag: '1.2.0',
      );
      final provisioner = _FakeProvisioner(
        const {
          'websearch': OpenToolRegistrationDto(
            ref: 'websearch',
            name: 'opentool-server-websearch',
            server: server,
            status: OpenToolRegistrationStatus.starting,
          ),
        },
        success: const OpenToolProvisioningSuccess(
          declaration: declaration,
          server: server,
          id: 'tool-websearch',
        ),
      );
      final controller = AppKitController(
        service: service,
        openToolProvisioner: provisioner,
      );

      final registerResponse = await controller.router.call(
        Request(
          'POST',
          Uri.parse('http://localhost/register'),
          body: jsonEncode({
            'bundleId': 'com.demo.app',
            'opentoolServers': [declaration.toJson()],
          }),
        ),
      );
      final registration =
          jsonDecode(await registerResponse.readAsString()) as Map;
      await Future<void>.delayed(Duration.zero);

      final subscribeResponse = await controller.router.call(
        Request(
          'GET',
          Uri.parse('http://localhost/subscribe'),
          headers: {'authorization': 'Bearer ${registration['token']}'},
        ),
      );
      final chunks = await subscribeResponse
          .read()
          .take(2)
          .toList()
          .timeout(const Duration(seconds: 2));
      final body = utf8.decode(chunks.expand((chunk) => chunk).toList());

      expect(body, contains('event: welcome'));
      expect(body, contains('event: appEvent'));
      expect(body, contains('"type":"toolkit.provision.succeeded"'));
      expect(body, contains('"source":"toolkit"'));
      expect(body, contains('"subject":"websearch"'));
      expect(body, contains('"status":"running"'));
      expect(body, contains('"id":"tool-websearch"'));
    });
  });

  group('OpenToolProvisioningService', () {
    test(
      'selects the highest semantic version and ignores an older ready tool',
      () async {
        final gateway = _FakeDaemonGateway(
          servers: [
            _server(id: 'server-old', tag: '0.1.0'),
            _server(id: 'server-new', tag: '0.1.1'),
          ],
          tools: [
            _tool(
              status: 'running',
              id: 'tool-old',
              serverId: 'server-old',
              serverTag: '0.1.0',
            ),
          ],
          ready: true,
          createdToolId: 'tool-new',
        );
        final service = _provisioningService(gateway);
        final success = Completer<OpenToolProvisioningSuccess>();

        final result = await service.ensureRunning(
          const OpenToolServerDeclarationDto(
            ref: 'markitdown',
            name: 'opentool-server-websearch',
          ),
          onSuccess: success.complete,
          onFailure: (_) => fail('No failure expected'),
        );

        expect(result.status, OpenToolRegistrationStatus.starting);
        expect(result.server?.tag, '0.1.1');
        expect((await success.future).id, 'tool-new');
        expect(gateway.createdServerIds, ['server-new']);
        expect(gateway.startCalls, 0);
      },
    );

    test('returns an id only when the existing tool is ready', () async {
      final gateway = _FakeDaemonGateway(
        servers: [_server()],
        tools: [_tool(status: 'running')],
        ready: true,
      );
      final service = _provisioningService(gateway);

      final result = await service.ensureRunning(
        const OpenToolServerDeclarationDto(
          ref: 'websearch',
          name: 'opentool-server-websearch',
        ),
        onSuccess: (_) => fail('No asynchronous success expected'),
        onFailure: (_) => fail('No failure expected'),
      );

      expect(result.status, OpenToolRegistrationStatus.running);
      expect(result.id, 'tool-1');
      expect(gateway.startCalls, 0);
      expect(gateway.createCalls, 0);
    });

    test('trusts readiness when daemon status is stale', () async {
      final gateway = _FakeDaemonGateway(
        servers: [_server()],
        tools: [_tool(status: 'notRunning')],
        ready: true,
      );
      final service = _provisioningService(gateway);

      final result = await service.ensureRunning(
        const OpenToolServerDeclarationDto(
          ref: 'websearch',
          name: 'opentool-server-websearch',
        ),
        onSuccess: (_) => fail('No asynchronous success expected'),
        onFailure: (_) => fail('No failure expected'),
      );

      expect(result.status, OpenToolRegistrationStatus.running);
      expect(result.id, 'tool-1');
      expect(gateway.startCalls, 0);
      expect(gateway.createCalls, 0);
    });

    test('returns notFound when no native server matches the name', () async {
      final gateway = _FakeDaemonGateway(servers: const [], tools: const []);
      final service = _provisioningService(gateway);

      final result = await service.ensureRunning(
        const OpenToolServerDeclarationDto(
          ref: 'missing',
          name: 'opentool-server-missing',
        ),
        onSuccess: (_) => fail('No asynchronous success expected'),
        onFailure: (_) => fail('No failure expected'),
      );

      expect(result.status, OpenToolRegistrationStatus.notFound);
      expect(result.id, isNull);
    });

    test(
      'returns starting and reports an asynchronous create failure',
      () async {
        final gateway = _FakeDaemonGateway(
          servers: [_server()],
          tools: const [],
          createError: StateError('cannot start'),
        );
        final service = _provisioningService(gateway);
        final failure = Completer<OpenToolProvisioningFailure>();

        final result = await service.ensureRunning(
          const OpenToolServerDeclarationDto(
            ref: 'websearch',
            name: 'opentool-server-websearch',
          ),
          onSuccess: (_) => fail('No success expected'),
          onFailure: failure.complete,
        );

        expect(result.status, OpenToolRegistrationStatus.starting);
        expect(result.id, isNull);
        expect((await failure.future).code, 'createFailed');
        expect(gateway.createCalls, 1);
      },
    );

    test('returns starting and reports the ready tool id on success', () async {
      final gateway = _FakeDaemonGateway(
        servers: [_server()],
        tools: const [],
        createdToolId: 'tool-created',
      );
      final service = _provisioningService(gateway);
      final success = Completer<OpenToolProvisioningSuccess>();

      final result = await service.ensureRunning(
        const OpenToolServerDeclarationDto(
          ref: 'websearch',
          name: 'opentool-server-websearch',
        ),
        onSuccess: success.complete,
        onFailure: (_) => fail('No failure expected'),
      );

      expect(result.status, OpenToolRegistrationStatus.starting);
      expect(result.id, isNull);
      expect((await success.future).id, 'tool-created');
      expect(gateway.createCalls, 1);
    });

    test('restarts a tool reported running but not ready', () async {
      final gateway = _FakeDaemonGateway(
        servers: [_server()],
        tools: [_tool(status: 'running')],
        ready: false,
      );
      final service = _provisioningService(gateway);
      final success = Completer<OpenToolProvisioningSuccess>();

      final result = await service.ensureRunning(
        const OpenToolServerDeclarationDto(
          ref: 'websearch',
          name: 'opentool-server-websearch',
        ),
        onSuccess: success.complete,
        onFailure: (_) => fail('No failure expected'),
      );

      expect(result.status, OpenToolRegistrationStatus.starting);
      expect((await success.future).id, 'tool-1');
      expect(gateway.startCalls, 1);
      expect(gateway.createCalls, 0);
    });

    test('restarts a stopped tool without creating a new tool id', () async {
      final gateway = _FakeDaemonGateway(
        servers: [_server()],
        tools: [_tool(status: 'notRunning')],
        ready: false,
      );
      final service = _provisioningService(gateway);
      final success = Completer<OpenToolProvisioningSuccess>();

      final result = await service.ensureRunning(
        const OpenToolServerDeclarationDto(
          ref: 'websearch',
          name: 'opentool-server-websearch',
        ),
        onSuccess: success.complete,
        onFailure: (_) => fail('No failure expected'),
      );

      expect(result.status, OpenToolRegistrationStatus.starting);
      expect((await success.future).id, 'tool-1');
      expect(gateway.startCalls, 1);
      expect(gateway.createCalls, 0);
    });
  });

  group('OpenToolAvailabilityService', () {
    test('pushes tool unavailable and recovered transitions once', () async {
      final appKitService = AppKitService();
      final registration = appKitService.registerBundle(
        AppBundleDto(bundleId: 'com.demo.app'),
      );
      final received = <EventDto>[];
      final subscription = appKitService
          .subscribe(registration.token)
          .listen(received.add);
      await Future<void>.delayed(Duration.zero);

      final locator = _ControllableServiceLocator();
      final gateway = _FakeDaemonGateway(
        servers: [_server()],
        tools: [_tool(status: OpenToolRegistrationStatus.running)],
        ready: true,
      );
      final monitor = OpenToolAvailabilityService(
        serviceLocator: locator,
        appKitService: appKitService,
        gatewayFactory: () async => gateway,
        checkInterval: Duration.zero,
      );
      const declaration = OpenToolServerDeclarationDto(
        ref: 'websearch',
        name: 'opentool-server-websearch',
      );
      const server = OpenToolResolvedServerDto(
        repo: 'native',
        name: 'opentool-server-websearch',
        tag: '1.2.0',
      );
      final generation = monitor.replaceBundleDeclarations(
        'com.demo.app',
        const [declaration],
      );
      monitor.track(
        bundleId: 'com.demo.app',
        generation: generation,
        declaration: declaration,
        server: server,
        toolId: 'tool-1',
      );

      await monitor.checkNow();
      expect(received, hasLength(1));

      gateway.tools = [_tool(status: 'notRunning')];
      await monitor.checkNow();
      await Future<void>.delayed(Duration.zero);
      expect(received, hasLength(1));

      gateway.tools = [_tool(status: OpenToolRegistrationStatus.running)];
      gateway.ready = false;
      await monitor.checkNow();
      await Future<void>.delayed(Duration.zero);
      expect(received, hasLength(2));
      final unavailable = _appEventData(received.last);
      expect(unavailable['type'], AppEventType.toolkitToolUnavailable);
      expect(unavailable['subject'], 'websearch');
      expect(unavailable['data'], containsPair('id', 'tool-1'));
      expect(unavailable['data'], containsPair('scope', 'tool'));
      expect(unavailable['data'], containsPair('reason', 'healthcheckFailed'));

      await monitor.checkNow();
      await Future<void>.delayed(Duration.zero);
      expect(received, hasLength(2));

      gateway.ready = true;
      await monitor.checkNow();
      await Future<void>.delayed(Duration.zero);
      expect(received, hasLength(3));
      final available = _appEventData(received.last);
      expect(available['type'], AppEventType.toolkitToolAvailable);
      expect(available['data'], containsPair('status', 'running'));
      expect(available['data'], containsPair('scope', 'tool'));
      expect(available['data'], containsPair('reason', 'recovered'));

      await monitor.dispose();
      await subscription.cancel();
      await locator.dispose();
    });

    test('pushes daemon loss and recovery for each tracked ref', () async {
      final appKitService = AppKitService();
      final registration = appKitService.registerBundle(
        AppBundleDto(bundleId: 'com.demo.app'),
      );
      final received = <EventDto>[];
      final subscription = appKitService
          .subscribe(registration.token)
          .listen(received.add);
      await Future<void>.delayed(Duration.zero);

      final locator = _ControllableServiceLocator();
      final gateway = _FakeDaemonGateway(
        servers: [_server()],
        tools: [_tool(status: OpenToolRegistrationStatus.running)],
        ready: true,
      );
      final monitor = OpenToolAvailabilityService(
        serviceLocator: locator,
        appKitService: appKitService,
        gatewayFactory: () async => gateway,
        checkInterval: Duration.zero,
      );
      const declaration = OpenToolServerDeclarationDto(
        ref: 'websearch',
        name: 'opentool-server-websearch',
      );
      final generation = monitor.replaceBundleDeclarations(
        'com.demo.app',
        const [declaration],
      );
      monitor.track(
        bundleId: 'com.demo.app',
        generation: generation,
        declaration: declaration,
        server: const OpenToolResolvedServerDto(
          repo: 'native',
          name: 'opentool-server-websearch',
          tag: '1.2.0',
        ),
        toolId: 'tool-1',
      );

      locator.addStatus(
        const ServiceStatusEvent(
          serviceKey: ApiConfig.serviceOpentool,
          state: ServiceState.stopped,
          message: 'daemon exited',
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(received, hasLength(2));
      final unavailable = _appEventData(received.last);
      expect(unavailable['type'], AppEventType.toolkitToolUnavailable);
      expect(unavailable['data'], containsPair('scope', 'daemon'));
      expect(unavailable['data'], containsPair('reason', 'daemonStopped'));
      expect(unavailable['data'], containsPair('message', 'daemon exited'));

      locator.addStatus(
        const ServiceStatusEvent(
          serviceKey: ApiConfig.serviceOpentool,
          state: ServiceState.stopped,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(received, hasLength(2));

      locator.addStatus(
        const ServiceStatusEvent(
          serviceKey: ApiConfig.serviceOpentool,
          state: ServiceState.running,
        ),
      );
      await _waitForEventCount(received, 3);
      final available = _appEventData(received.last);
      expect(available['type'], AppEventType.toolkitToolAvailable);
      expect(available['data'], containsPair('scope', 'daemon'));
      expect(available['data'], containsPair('reason', 'daemonRecovered'));

      await monitor.dispose();
      await subscription.cancel();
      await locator.dispose();
    });
  });

  group('DaemonOpenToolGateway readiness', () {
    test('allows notRunning during the startup transition', () async {
      final gateway = _SequencedReadinessGateway(
        readyResults: [false, true],
        toolStatuses: ['notRunning'],
      );

      expect(await gateway.waitUntilReady('tool-1'), 'tool-1');
    });

    test('fails after a running tool becomes stopped', () async {
      final gateway = _SequencedReadinessGateway(
        readyResults: [false, false],
        toolStatuses: [OpenToolRegistrationStatus.running, 'notRunning'],
      );

      await expectLater(
        gateway.waitUntilReady('tool-1'),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('stopped before becoming ready'),
          ),
        ),
      );
    });
  });
}

Map<String, dynamic> _appEventData(EventDto event) {
  expect(event.event, 'appEvent');
  return jsonDecode(event.data) as Map<String, dynamic>;
}

Future<void> _waitForEventCount(List<EventDto> events, int count) async {
  final deadline = DateTime.now().add(const Duration(seconds: 1));
  while (events.length < count && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  expect(events, hasLength(count));
}

OpenToolProvisioningService _provisioningService(
  OpenToolDaemonGateway gateway,
) {
  return OpenToolProvisioningService(
    serviceLocator: _UnusedServiceLocator(),
    gatewayFactory: () async => gateway,
  );
}

OpenToolServerDto _server({String id = 'server-1', String tag = '1.2.0'}) {
  return OpenToolServerDto(
    id: id,
    alias: 'websearch',
    registry: 'native',
    repo: 'native',
    name: 'opentool-server-websearch',
    tag: tag,
  );
}

ToolDto _tool({
  required String status,
  String id = 'tool-1',
  String serverId = 'server-1',
  String serverTag = '1.2.0',
}) {
  return ToolDto(
    id: id,
    alias: 'websearch',
    host: '127.0.0.1',
    port: 19640,
    status: status,
    serverId: serverId,
    server: ToolServerDto(
      repo: 'native',
      name: 'opentool-server-websearch',
      tag: serverTag,
    ),
  );
}

class _FakeProvisioner implements OpenToolProvisioner {
  _FakeProvisioner(this.results, {this.success, this.failure});

  final Map<String, OpenToolRegistrationDto> results;
  final OpenToolProvisioningSuccess? success;
  final OpenToolProvisioningFailure? failure;

  @override
  Future<OpenToolRegistrationDto> ensureRunning(
    OpenToolServerDeclarationDto declaration, {
    required OpenToolProvisionSuccessHandler onSuccess,
    required OpenToolProvisionFailureHandler onFailure,
  }) async {
    final pendingSuccess = success;
    if (pendingSuccess != null) {
      scheduleMicrotask(() => onSuccess(pendingSuccess));
    }
    final pendingFailure = failure;
    if (pendingFailure != null) {
      scheduleMicrotask(() => onFailure(pendingFailure));
    }
    return results[declaration.ref]!;
  }
}

class _FakeDaemonGateway implements OpenToolDaemonGateway {
  _FakeDaemonGateway({
    required this.servers,
    required this.tools,
    this.ready = false,
    this.createError,
    this.createdToolId = 'tool-1',
  });

  final List<OpenToolServerDto> servers;
  List<ToolDto> tools;
  bool ready;
  final Object? createError;
  final String createdToolId;
  int startCalls = 0;
  int createCalls = 0;
  final List<String> createdServerIds = [];

  @override
  Future<String> createAndWait(String serverId) async {
    createCalls += 1;
    createdServerIds.add(serverId);
    if (createError != null) {
      throw createError!;
    }
    return createdToolId;
  }

  @override
  Future<bool> isReady(String toolId) async => ready;

  @override
  Future<List<OpenToolServerDto>> listServers() async => servers;

  @override
  Future<List<ToolDto>> listTools() async => tools;

  @override
  Future<String> startAndWait(String toolId) async {
    startCalls += 1;
    return toolId;
  }

  @override
  Future<String> waitUntilReady(String toolId) async => toolId;
}

class _SequencedReadinessGateway extends DaemonOpenToolGateway {
  _SequencedReadinessGateway({
    required List<bool> readyResults,
    required List<String> toolStatuses,
  }) : _readyResults = List.of(readyResults),
       _toolStatuses = List.of(toolStatuses),
       super(
         DaemonClient(host: '127.0.0.1', port: 1),
         readinessTimeout: const Duration(seconds: 1),
         pollInterval: Duration.zero,
         startupGracePeriod: const Duration(seconds: 1),
       );

  final List<bool> _readyResults;
  final List<String> _toolStatuses;

  @override
  Future<bool> isReady(String toolId) async {
    if (_readyResults.length == 1) {
      return _readyResults.first;
    }
    return _readyResults.removeAt(0);
  }

  @override
  Future<List<ToolDto>> listTools() async {
    final status = _toolStatuses.length == 1
        ? _toolStatuses.first
        : _toolStatuses.removeAt(0);
    return [_tool(status: status)];
  }
}

class _UnusedServiceLocator implements AgentOSServiceLocator {
  @override
  String get liteagentBaseUrl => 'http://127.0.0.1:9527/api/v1';

  @override
  Future<List<AppInfo>> getAppInfoList() async => const [];

  @override
  Future<List<LlmModelInfo>> getLlmModelList() async => const [];

  @override
  Future<int?> getServicePort(String serviceKey, {String? modelId}) async =>
      null;

  @override
  Stream<ServiceStatusEvent> get serviceStatusStream => const Stream.empty();
}

class _ControllableServiceLocator extends _UnusedServiceLocator {
  final _statuses = StreamController<ServiceStatusEvent>.broadcast();

  @override
  Stream<ServiceStatusEvent> get serviceStatusStream => _statuses.stream;

  void addStatus(ServiceStatusEvent event) => _statuses.add(event);

  Future<void> dispose() => _statuses.close();
}

class _FakeAvailabilityTracker implements OpenToolAvailabilityTracker {
  int _generation = 0;
  List<String> declarationRefs = const [];
  final List<String> trackedRefs = [];

  @override
  int replaceBundleDeclarations(
    String bundleId,
    Iterable<OpenToolServerDeclarationDto> declarations,
  ) {
    declarationRefs = declarations
        .map((declaration) => declaration.ref)
        .toList();
    return ++_generation;
  }

  @override
  void track({
    required String bundleId,
    required int generation,
    required OpenToolServerDeclarationDto declaration,
    required OpenToolResolvedServerDto server,
    required String toolId,
  }) {
    trackedRefs.add(declaration.ref);
  }

  @override
  Future<void> checkNow() async {}

  @override
  Future<void> dispose() async {}
}
