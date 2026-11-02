import 'dart:async';
import 'dart:convert';

import 'package:logging/logging.dart';
import 'package:unique_id_dart/unique_id_dart.dart';

import '../../models/agent/agent_models.dart';
import '../../models/app/app_models.dart';

final Logger _appKitLogger = Logger('agentos_server');

class AppKitService {
  static const int _maxPendingEventsPerBundle = 100;

  final List<String> _apps = [];
  final Map<String, _RegisteredApp> _tokenRegistry = {};
  final Map<String, String> _bundleTokens = {};
  final Map<String, List<String>> _bundleAgents = {};

  final Map<String, StreamController<EventDto>> _subscribers = {};
  final Map<String, List<EventDto>> _pendingEvents = {};
  final Map<String, AppKitToolEventSubscription> _toolEventSubscriptions = {};
  final _toolEventSubscriptionController =
      StreamController<AppKitToolEventSubscriptionChange>.broadcast();

  final _appOfflineController = StreamController<String>.broadcast();

  /// Stream of bundleIds that have gone offline (SSE disconnected).
  Stream<String> get appOfflineStream => _appOfflineController.stream;

  /// Tool lifecycle subscriptions currently attached to AppKit connections.
  Stream<AppKitToolEventSubscriptionChange> get toolEventSubscriptionChanges =>
      _toolEventSubscriptionController.stream;

  Iterable<AppKitToolEventSubscription> get toolEventSubscriptions =>
      List.unmodifiable(_toolEventSubscriptions.values);

  List<String> listApps() => List.unmodifiable(_apps);

  /// Bundle IDs of apps that have registered via [registerBundle].
  Iterable<String> get registeredBundleIds => _bundleTokens.keys;

  bool isTokenValid(String token) => _registeredAppForToken(token) != null;

  String? bundleIdForToken(String token) =>
      _registeredAppForToken(token)?.bundleId;

  String? appGroupIdForToken(String token) =>
      _registeredAppForToken(token)?.appGroupId;

  String? effectiveAppGroupIdForToken(String token) {
    return _registeredAppForToken(token)?.effectiveAppGroupId;
  }

  void registerApp(String rawDefinition) {
    // Legacy placeholder registration.
    if (rawDefinition.isNotEmpty) {
      _apps.add(rawDefinition);
    }
  }

  TokenInfo registerBundle(AppBundleDto bundle) {
    final token = _issueToken();
    final registered = _RegisteredApp(
      token: token,
      bundleId: bundle.bundleId,
      appGroupId: bundle.appGroupId,
    );
    _bundleTokens[bundle.bundleId] = token;
    _tokenRegistry[token] = registered;
    final tokenPreview = token.length <= 12
        ? token
        : '${token.substring(0, 8)}...${token.substring(token.length - 4)}';
    _appKitLogger.info(
      'AppKitService registerBundle: token=$tokenPreview bundleId=${registered.bundleId} appGroupId=${registered.effectiveAppGroupId}',
    );
    return TokenInfo(
      token: token,
      bundleId: registered.bundleId,
      appGroupId: registered.effectiveAppGroupId,
    );
  }

  bool bindAgents({required String token, required List<AgentInfoDto> agents}) {
    final bundleId = bundleIdForToken(token);
    if (bundleId == null) {
      return false;
    }
    _bundleAgents[bundleId] = agents.map((e) => e.id).toList();
    return true;
  }

  Stream<EventDto> subscribe(
    String token, {
    AppKitToolEventSubscription? toolEvents,
  }) {
    final registered = _registeredAppForToken(token);
    if (registered == null) {
      return const Stream<EventDto>.empty();
    }

    final bundleId = registered.bundleId;
    final existing = _subscribers[bundleId];
    if (existing != null && !existing.isClosed) {
      existing.close();
    }

    late final StreamController<EventDto> controller;
    if (toolEvents == null) {
      _toolEventSubscriptions.remove(bundleId);
    } else {
      _toolEventSubscriptions[bundleId] = toolEvents.withBundleId(bundleId);
    }
    _toolEventSubscriptionController.add(
      AppKitToolEventSubscriptionChange(
        bundleId: bundleId,
        subscription: _toolEventSubscriptions[bundleId],
      ),
    );
    controller = StreamController<EventDto>(
      onListen: () {
        controller.add(
          EventDto(
            event: 'welcome',
            data: jsonEncode({
              'bundleId': bundleId,
              'appGroupId': registered.effectiveAppGroupId,
            }),
          ),
        );
        final pending = _pendingEvents.remove(bundleId);
        if (pending != null) {
          for (final event in pending) {
            controller.add(event);
          }
        }
      },
      onCancel: () {
        if (identical(_subscribers[bundleId], controller)) {
          _subscribers.remove(bundleId);
          _toolEventSubscriptions.remove(bundleId);
          _toolEventSubscriptionController.add(
            AppKitToolEventSubscriptionChange(bundleId: bundleId),
          );
        }
        controller.close();
        _appOfflineController.add(bundleId);
        _appKitLogger.info('AppKitService: app went offline: $bundleId');
      },
    );

    _subscribers[bundleId] = controller;
    return controller.stream;
  }

  bool isAppOnline(String bundleId) {
    final controller = _subscribers[bundleId];
    return controller != null && !controller.isClosed;
  }

  bool pushEvent(String bundleId, EventDto event) {
    final controller = _subscribers[bundleId];
    if (controller == null || controller.isClosed) {
      return false;
    }
    controller.add(event);
    return true;
  }

  void publishAppEvent(String bundleId, AppEventDto event) {
    final dto = EventDto(
      id: event.id,
      event: 'appEvent',
      data: jsonEncode(event.toJson()),
    );
    if (pushEvent(bundleId, dto)) {
      return;
    }
    final pending = _pendingEvents.putIfAbsent(bundleId, () => []);
    pending.add(dto);
    if (pending.length > _maxPendingEventsPerBundle) {
      pending.removeAt(0);
    }
  }

  /// Tells [bundleId] that the user activated one of its NotifyKit
  /// notifications in the shell.
  ///
  /// The event is delivered like any other `appEvent`: immediately when the App
  /// is subscribed, otherwise queued (bounded) and replayed right after
  /// `welcome` once the App connects. That makes "click notification -> shell
  /// launches the App -> App receives the activation" work for an App that was
  /// not running when the user clicked.
  ///
  /// `subject` is the App-provided `subjectId` when present, otherwise the
  /// notification id. Only identifiers the App itself supplied (or the opaque
  /// notification id) are forwarded; no other App's content is exposed.
  AppEventDto publishNotificationActivated(
    String bundleId, {
    required String notificationId,
    required String eventType,
    String? subjectId,
  }) {
    final event = createAppEvent(
      type: AppEventType.notificationActivated,
      source: 'notifykit',
      subject: subjectId ?? notificationId,
      data: <String, dynamic>{
        'notificationId': notificationId,
        'eventType': eventType,
        'subjectId': ?subjectId,
      },
    );
    publishAppEvent(bundleId, event);
    return event;
  }

  /// Broadcasts daemon lifecycle changes only to apps that opted in and only
  /// to the tool IDs allowed by their subscription filter.
  void publishToolLifecycleEvent({
    required String type,
    required String toolId,
    required String status,
    required String reason,
    required Map<String, Object?> tool,
  }) {
    for (final subscription in _toolEventSubscriptions.values) {
      if (!subscription.matches(toolId)) continue;
      final event = createAppEvent(
        type: type,
        source: 'toolkit',
        subject: toolId,
        data: <String, dynamic>{
          ...tool,
          'id': toolId,
          'status': status,
          'reason': reason,
        },
      );
      pushEvent(
        subscription.bundleId,
        EventDto(
          id: event.id,
          event: 'appEvent',
          data: jsonEncode(event.toJson()),
        ),
      );
    }
  }

  AppEventDto createAppEvent({
    required String type,
    required String source,
    required String subject,
    required Map<String, dynamic> data,
  }) {
    return AppEventDto(
      id: 'evt-${uniqueId(shorter: true)}',
      type: type,
      source: source,
      time: DateTime.now().toUtc(),
      subject: subject,
      data: data,
    );
  }

  String _issueToken() {
    final generated = uniqueId(shorter: true);
    return 'sk-$generated';
  }

  _RegisteredApp? _registeredAppForToken(String token) {
    return _tokenRegistry[token];
  }
}

final class AppKitToolEventSubscription {
  final String bundleId;
  final bool all;
  final Set<String> toolIds;

  AppKitToolEventSubscription({
    required this.bundleId,
    required this.all,
    Set<String> toolIds = const {},
  }) : toolIds = Set.unmodifiable(toolIds);

  bool matches(String toolId) => all || toolIds.contains(toolId);

  AppKitToolEventSubscription withBundleId(String value) =>
      AppKitToolEventSubscription(bundleId: value, all: all, toolIds: toolIds);
}

final class AppKitToolEventSubscriptionChange {
  final String bundleId;
  final AppKitToolEventSubscription? subscription;

  const AppKitToolEventSubscriptionChange({
    required this.bundleId,
    this.subscription,
  });
}

class _RegisteredApp {
  const _RegisteredApp({
    required this.token,
    required this.bundleId,
    this.appGroupId,
  });

  final String token;
  final String bundleId;
  final String? appGroupId;

  String get effectiveAppGroupId => appGroupId ?? bundleId;
}
