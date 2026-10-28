import 'dart:async';

import 'package:opentool_daemon/opentool_daemon_client.dart';

import '../../config.dart';
import '../../locator.dart';
import '../../models/app/app_models.dart';
import 'appkit_service.dart';
import 'opentool_provisioning_service.dart';

abstract interface class OpenToolAvailabilityTracker {
  int replaceBundleDeclarations(
    String bundleId,
    Iterable<OpenToolServerDeclarationDto> declarations,
  );

  void track({
    required String bundleId,
    required int generation,
    required OpenToolServerDeclarationDto declaration,
    required OpenToolResolvedServerDto server,
    required String toolId,
  });

  Future<void> checkNow();

  Future<void> dispose();
}

class OpenToolAvailabilityService implements OpenToolAvailabilityTracker {
  OpenToolAvailabilityService({
    required AgentOSServiceLocator serviceLocator,
    required AppKitService appKitService,
    OpenToolDaemonGatewayFactory? gatewayFactory,
    this.checkInterval = const Duration(seconds: 5),
    this.lookupTimeout = const Duration(seconds: 2),
  }) : _serviceLocator = serviceLocator,
       _appKitService = appKitService,
       _gatewayFactory = gatewayFactory {
    _serviceStatusSubscription = serviceLocator.serviceStatusStream.listen(
      _handleServiceStatus,
    );
    _toolEventSubscription = appKitService.toolEventSubscriptionChanges.listen(
      _handleToolEventSubscription,
    );
  }

  final AgentOSServiceLocator _serviceLocator;
  final AppKitService _appKitService;
  final OpenToolDaemonGatewayFactory? _gatewayFactory;
  final Duration checkInterval;
  final Duration lookupTimeout;

  final Map<String, int> _bundleGenerations = {};
  final Map<String, Map<String, OpenToolServerDeclarationDto>>
  _bundleDeclarations = {};
  final Map<_TrackedToolKey, _TrackedTool> _trackedTools = {};
  final Map<String, AppKitToolEventSubscription> _toolEventSubscribers = {};
  final Map<String, _ObservedTool> _observedTools = {};

  StreamSubscription<ServiceStatusEvent>? _serviceStatusSubscription;
  StreamSubscription<AppKitToolEventSubscriptionChange>? _toolEventSubscription;
  Timer? _timer;
  ServiceState? _daemonState;
  bool _checking = false;
  bool _disposed = false;

  @override
  int replaceBundleDeclarations(
    String bundleId,
    Iterable<OpenToolServerDeclarationDto> declarations,
  ) {
    final generation = (_bundleGenerations[bundleId] ?? 0) + 1;
    _bundleGenerations[bundleId] = generation;
    _bundleDeclarations[bundleId] = {
      for (final declaration in declarations) declaration.ref: declaration,
    };
    _trackedTools.removeWhere((key, _) => key.bundleId == bundleId);
    _stopTimerIfIdle();
    return generation;
  }

  @override
  void track({
    required String bundleId,
    required int generation,
    required OpenToolServerDeclarationDto declaration,
    required OpenToolResolvedServerDto server,
    required String toolId,
  }) {
    if (_disposed || _bundleGenerations[bundleId] != generation) {
      return;
    }
    final currentDeclaration = _bundleDeclarations[bundleId]?[declaration.ref];
    if (currentDeclaration == null ||
        currentDeclaration.name != declaration.name) {
      return;
    }
    final key = _TrackedToolKey(bundleId, declaration.ref);
    _trackedTools[key] = _TrackedTool(
      declaration: declaration,
      server: server,
      toolId: toolId,
    );
    _ensureTimer();

    final daemonState = _daemonState;
    if (daemonState == ServiceState.starting ||
        daemonState == ServiceState.stopped ||
        daemonState == ServiceState.error) {
      _markUnavailable(
        key,
        _trackedTools[key]!,
        scope: 'daemon',
        reason: _daemonUnavailableReason(daemonState!),
      );
    }
  }

  @override
  Future<void> checkNow() async {
    if (_disposed ||
        _checking ||
        (_trackedTools.isEmpty && _toolEventSubscribers.isEmpty)) {
      return;
    }
    _checking = true;
    try {
      if (_toolEventSubscribers.isNotEmpty) {
        await _publishSubscribedAppToolChanges();
      }
      final daemonState = _daemonState;
      if (daemonState == ServiceState.starting ||
          daemonState == ServiceState.stopped ||
          daemonState == ServiceState.error) {
        _markAllUnavailable(
          scope: 'daemon',
          reason: _daemonUnavailableReason(daemonState!),
        );
        _markSubscribedToolsUnavailable(
          _daemonUnavailableReason(daemonState),
          source: 'daemon',
        );
        return;
      }

      final gateway = await _createGateway().timeout(lookupTimeout);
      if (gateway == null) {
        _markAllUnavailable(scope: 'daemon', reason: 'daemonUnavailable');
        _markSubscribedToolsUnavailable('daemonUnavailable', source: 'daemon');
        return;
      }

      late final List<ToolDto> tools;
      try {
        tools = await gateway.listTools().timeout(lookupTimeout);
      } catch (_) {
        _markAllUnavailable(scope: 'daemon', reason: 'daemonUnavailable');
        _markSubscribedToolsUnavailable('daemonUnavailable', source: 'daemon');
        return;
      }

      final toolsById = {for (final tool in tools) tool.id: tool};
      await _publishSubscribedToolChanges(gateway, toolsById);
      final readiness = <String, Future<bool>>{};
      final trackedSnapshot = Map<_TrackedToolKey, _TrackedTool>.from(
        _trackedTools,
      );
      for (final entry in trackedSnapshot.entries) {
        final key = entry.key;
        final tracked = entry.value;
        if (!identical(_trackedTools[key], tracked)) {
          continue;
        }
        final tool = toolsById[tracked.toolId];
        if (tool == null) {
          _markUnavailable(key, tracked, scope: 'tool', reason: 'removed');
          continue;
        }
        final readyFuture = readiness.putIfAbsent(
          tracked.toolId,
          () => _isReady(gateway, tracked.toolId),
        );
        final ready = await readyFuture;
        if (!identical(_trackedTools[key], tracked)) {
          continue;
        }
        if (ready) {
          _markAvailable(key, tracked);
        } else if (tool.status != OpenToolRegistrationStatus.running) {
          _markUnavailable(key, tracked, scope: 'tool', reason: 'stopped');
        } else {
          _markUnavailable(
            key,
            tracked,
            scope: 'tool',
            reason: 'healthcheckFailed',
          );
        }
      }
    } catch (_) {
      _markAllUnavailable(scope: 'daemon', reason: 'daemonUnavailable');
      _markSubscribedToolsUnavailable('daemonUnavailable', source: 'daemon');
    } finally {
      _checking = false;
    }
  }

  void _handleToolEventSubscription(AppKitToolEventSubscriptionChange change) {
    final subscription = change.subscription;
    if (subscription == null) {
      _toolEventSubscribers.remove(change.bundleId);
    } else {
      _toolEventSubscribers[change.bundleId] = subscription;
      unawaited(checkNow());
    }
    _ensureTimer();
    _stopTimerIfIdle();
  }

  Future<void> _publishSubscribedToolChanges(
    OpenToolDaemonGateway gateway,
    Map<String, ToolDto> currentTools,
  ) async {
    if (_toolEventSubscribers.isEmpty) return;
    final watchedIds = <String>{
      for (final subscription in _toolEventSubscribers.values)
        if (subscription.all) ...currentTools.keys else ...subscription.toolIds,
    };
    watchedIds.addAll(
      _observedTools.keys.where(
        (toolId) =>
            _observedTools[toolId]!.source == 'daemon' &&
            _toolEventSubscribers.values.any(
              (subscription) => subscription.matches(toolId),
            ),
      ),
    );

    for (final toolId in _observedTools.keys.toList()) {
      if (_observedTools[toolId]!.source != 'daemon') continue;
      if (currentTools.containsKey(toolId)) continue;
      final previous = _observedTools.remove(toolId)!;
      if (!watchedIds.contains(toolId)) continue;
      if (previous.status == 'available') {
        _publishSubscribedToolEvent(
          toolId: previous.toolId,
          data: previous.data,
          type: AppEventType.toolkitToolUnavailable,
          status: 'unavailable',
          reason: 'removed',
        );
      }
    }

    for (final toolId in watchedIds) {
      final tool = currentTools[toolId];
      if (tool == null) continue;
      final ready =
          tool.status == OpenToolRegistrationStatus.running &&
          await _isReady(gateway, toolId);
      final nextStatus = ready ? 'available' : 'unavailable';
      final previous = _observedTools[toolId];
      final reason = previous == null
          ? (ready ? 'registered' : 'notReady')
          : previous.status == nextStatus
          ? null
          : (ready ? 'recovered' : 'stopped');
      _observedTools[toolId] = _ObservedTool(
        toolId: toolId,
        data: tool.toJson(),
        source: 'daemon',
        status: nextStatus,
      );
      if (reason == null) continue;
      _publishSubscribedToolEvent(
        toolId: toolId,
        data: tool.toJson(),
        type: ready
            ? AppEventType.toolkitToolAvailable
            : AppEventType.toolkitToolUnavailable,
        status: nextStatus,
        reason: reason,
      );
    }
  }

  Future<void> _publishSubscribedAppToolChanges() async {
    final provider = _serviceLocator.appOpenToolProvider;
    if (provider == null) return;

    late final List<Map<String, Object?>> listedTools;
    try {
      listedTools = await provider.listTools(all: true).timeout(lookupTimeout);
    } catch (_) {
      // A temporary provider outage must not look like all App tools vanished.
      return;
    }
    final currentTools = <String, Map<String, Object?>>{
      for (final tool in listedTools)
        if (tool['id'] is String && (tool['id'] as String).isNotEmpty)
          tool['id'] as String: tool,
    };
    final watchedIds = <String>{
      for (final subscription in _toolEventSubscribers.values)
        if (subscription.all) ...currentTools.keys else ...subscription.toolIds,
    };
    watchedIds.addAll(
      _observedTools.keys.where(
        (toolId) =>
            _observedTools[toolId]!.source == 'app' &&
            _toolEventSubscribers.values.any(
              (subscription) => subscription.matches(toolId),
            ),
      ),
    );

    for (final toolId in _observedTools.keys.toList()) {
      if (_observedTools[toolId]!.source != 'app' ||
          currentTools.containsKey(toolId)) {
        continue;
      }
      final previous = _observedTools.remove(toolId)!;
      if (!watchedIds.contains(toolId)) continue;
      if (previous.status == 'available') {
        _publishSubscribedToolEvent(
          toolId: toolId,
          data: previous.data,
          type: AppEventType.toolkitToolUnavailable,
          status: 'unavailable',
          reason: 'removed',
        );
      }
    }

    for (final toolId in watchedIds) {
      final tool = currentTools[toolId];
      if (tool == null) continue;
      final rawStatus = tool['status']?.toString().trim().toLowerCase();
      final ready =
          rawStatus == null ||
          rawStatus.isEmpty ||
          rawStatus == 'running' ||
          rawStatus == 'available';
      final nextStatus = ready ? 'available' : 'unavailable';
      final previous = _observedTools[toolId];
      final reason = previous == null
          ? (ready ? 'registered' : 'notReady')
          : previous.status == nextStatus
          ? null
          : (ready ? 'recovered' : 'stopped');
      _observedTools[toolId] = _ObservedTool(
        toolId: toolId,
        data: tool,
        source: 'app',
        status: nextStatus,
      );
      if (reason == null) continue;
      _publishSubscribedToolEvent(
        toolId: toolId,
        data: tool,
        type: ready
            ? AppEventType.toolkitToolAvailable
            : AppEventType.toolkitToolUnavailable,
        status: nextStatus,
        reason: reason,
      );
    }
  }

  void _markSubscribedToolsUnavailable(
    String reason, {
    required String source,
  }) {
    for (final entry in _observedTools.entries.toList()) {
      if (entry.value.source != source || entry.value.status != 'available') {
        continue;
      }
      _observedTools[entry.key] = _ObservedTool(
        toolId: entry.value.toolId,
        data: entry.value.data,
        source: source,
        status: 'unavailable',
      );
      _publishSubscribedToolEvent(
        toolId: entry.value.toolId,
        data: entry.value.data,
        type: AppEventType.toolkitToolUnavailable,
        status: 'unavailable',
        reason: reason,
      );
    }
  }

  void _publishSubscribedToolEvent({
    required String toolId,
    required Map<String, Object?> data,
    required String type,
    required String status,
    required String reason,
  }) {
    _appKitService.publishToolLifecycleEvent(
      type: type,
      toolId: toolId,
      status: status,
      reason: reason,
      tool: data,
    );
  }

  Future<bool> _isReady(OpenToolDaemonGateway gateway, String toolId) async {
    try {
      return await gateway.isReady(toolId).timeout(lookupTimeout);
    } catch (_) {
      return false;
    }
  }

  void _handleServiceStatus(ServiceStatusEvent event) {
    if (_disposed || event.serviceKey != ApiConfig.serviceOpentool) {
      return;
    }
    _daemonState = event.state;
    switch (event.state) {
      case ServiceState.stopped:
        _markAllUnavailable(
          scope: 'daemon',
          reason: 'daemonStopped',
          message: event.message,
        );
        _markSubscribedToolsUnavailable('daemonStopped', source: 'daemon');
      case ServiceState.error:
        _markAllUnavailable(
          scope: 'daemon',
          reason: 'daemonError',
          message: event.message,
        );
        _markSubscribedToolsUnavailable('daemonError', source: 'daemon');
      case ServiceState.running:
        unawaited(checkNow());
      case ServiceState.starting:
        _markAllUnavailable(
          scope: 'daemon',
          reason: 'daemonStarting',
          message: event.message,
        );
        _markSubscribedToolsUnavailable('daemonStarting', source: 'daemon');
    }
  }

  String _daemonUnavailableReason(ServiceState state) {
    return switch (state) {
      ServiceState.starting => 'daemonStarting',
      ServiceState.stopped => 'daemonStopped',
      ServiceState.error => 'daemonError',
      ServiceState.running => 'daemonUnavailable',
    };
  }

  void _markAllUnavailable({
    required String scope,
    required String reason,
    String? message,
  }) {
    final snapshot = Map<_TrackedToolKey, _TrackedTool>.from(_trackedTools);
    for (final entry in snapshot.entries) {
      if (identical(_trackedTools[entry.key], entry.value)) {
        _markUnavailable(
          entry.key,
          entry.value,
          scope: scope,
          reason: reason,
          message: message,
        );
      }
    }
  }

  void _markUnavailable(
    _TrackedToolKey key,
    _TrackedTool tracked, {
    required String scope,
    required String reason,
    String? message,
  }) {
    if (!tracked.available) {
      return;
    }
    tracked.available = false;
    tracked.unavailableScope = scope;
    _publish(
      key.bundleId,
      type: AppEventType.toolkitToolUnavailable,
      tracked: tracked,
      status: 'unavailable',
      scope: scope,
      reason: reason,
      message: message,
    );
  }

  void _markAvailable(_TrackedToolKey key, _TrackedTool tracked) {
    if (tracked.available) {
      return;
    }
    final previousScope = tracked.unavailableScope;
    tracked.available = true;
    tracked.unavailableScope = null;
    _publish(
      key.bundleId,
      type: AppEventType.toolkitToolAvailable,
      tracked: tracked,
      status: OpenToolRegistrationStatus.running,
      scope: previousScope == 'daemon' ? 'daemon' : 'tool',
      reason: previousScope == 'daemon' ? 'daemonRecovered' : 'recovered',
    );
  }

  void _publish(
    String bundleId, {
    required String type,
    required _TrackedTool tracked,
    required String status,
    required String scope,
    required String reason,
    String? message,
  }) {
    _appKitService.publishAppEvent(
      bundleId,
      _appKitService.createAppEvent(
        type: type,
        source: 'toolkit',
        subject: tracked.declaration.ref,
        data: {
          'ref': tracked.declaration.ref,
          'name': tracked.declaration.name,
          'id': tracked.toolId,
          'status': status,
          'scope': scope,
          'reason': reason,
          'server': tracked.server.toJson(),
          if (message != null && message.isNotEmpty) 'message': message,
        },
      ),
    );
  }

  Future<OpenToolDaemonGateway?> _createGateway() async {
    final factory = _gatewayFactory;
    if (factory != null) {
      return factory();
    }
    final port = await _serviceLocator.getServicePort(
      ApiConfig.serviceOpentool,
    );
    if (port == null) {
      return null;
    }
    return DaemonOpenToolGateway(
      DaemonClient(host: _serviceLocator.openToolDaemonHost, port: port),
    );
  }

  void _ensureTimer() {
    if (_timer != null ||
        checkInterval <= Duration.zero ||
        (_trackedTools.isEmpty && _toolEventSubscribers.isEmpty)) {
      return;
    }
    _timer = Timer.periodic(checkInterval, (_) => unawaited(checkNow()));
  }

  void _stopTimerIfIdle() {
    if (_trackedTools.isNotEmpty || _toolEventSubscribers.isNotEmpty) {
      return;
    }
    _timer?.cancel();
    _timer = null;
  }

  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    await _serviceStatusSubscription?.cancel();
    _serviceStatusSubscription = null;
    await _toolEventSubscription?.cancel();
    _toolEventSubscription = null;
    _trackedTools.clear();
    _toolEventSubscribers.clear();
    _observedTools.clear();
    _bundleDeclarations.clear();
  }
}

class _ObservedTool {
  const _ObservedTool({
    required this.toolId,
    required this.data,
    required this.source,
    required this.status,
  });

  final String toolId;
  final Map<String, Object?> data;
  final String source;
  final String status;
}

class _TrackedToolKey {
  const _TrackedToolKey(this.bundleId, this.ref);

  final String bundleId;
  final String ref;

  @override
  bool operator ==(Object other) {
    return other is _TrackedToolKey &&
        other.bundleId == bundleId &&
        other.ref == ref;
  }

  @override
  int get hashCode => Object.hash(bundleId, ref);
}

class _TrackedTool {
  _TrackedTool({
    required this.declaration,
    required this.server,
    required this.toolId,
  });

  final OpenToolServerDeclarationDto declaration;
  final OpenToolResolvedServerDto server;
  final String toolId;
  bool available = true;
  String? unavailableScope;
}
