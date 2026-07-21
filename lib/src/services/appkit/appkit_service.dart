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

  List<String> listApps() => List.unmodifiable(_apps);

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

  Stream<EventDto> subscribe(String token) {
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
        _subscribers.remove(bundleId);
        controller.close();
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
