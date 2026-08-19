import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:hive/hive.dart';
import 'package:logging/logging.dart';

import '../../locator.dart';
import '../../models/app/app_models.dart';
import '../../repository/hive/hive_provider.dart';
import '../appkit/appkit_service.dart';

final Logger _logger = Logger('AuthKitService');

/// Manages AgentOS login identity for Kit APIs (DiscoveryKit, TransferKit).
///
/// OAuth authorization is handled by AgentOS Server via the AuthKit delivery flow.
/// flow. This service tracks login state and derives per-app userIds using the
/// same algorithm as the legacy local AuthKit (`sha256(loginId:bundleId)`).
class AuthKitService {
  AuthKitService({
    required AgentOSServiceLocator serviceLocator,
    HiveProvider? hiveProvider,
    AppKitService? appKitService,
  }) : _serviceLocator = serviceLocator,
       _hiveProvider = hiveProvider ?? HiveProvider(),
       _appKitService = appKitService;

  final AgentOSServiceLocator _serviceLocator;
  final HiveProvider _hiveProvider;
  AppKitService? _appKitService;

  static const String _lastLoginIdKey = '__authkit_last_login_id__';

  String? _loginId;
  Box<Map>? _sessionBox;

  void setAppKitService(AppKitService service) {
    _appKitService = service;
  }

  /// Update the current login user ID.
  ///
  /// Broadcasts login lifecycle events to all AppKit-registered apps:
  /// - **logout**: `reason=logout`
  /// - **account_switch**: `reason=account_switch`
  /// - **login** (same account): `reason=login`
  Future<void> setLoginId(String? loginId) async {
    if (loginId == _loginId) return;
    _loginId = loginId;

    if (loginId == null) {
      await _handleLogout();
    } else {
      final lastLoginId = await _getLastLoginId();
      if (lastLoginId == null || lastLoginId != loginId) {
        await _handleAccountSwitch(loginId);
      } else {
        await _handleLogin(loginId);
      }
    }
  }

  String? get loginId => _loginId;

  bool get isLoggedIn => _loginId != null;

  /// Derive the stable per-app userId for [bundleId].
  ///
  /// Returns null when AgentOS is not logged in.
  String? resolveUserIdForBundle(String bundleId) => _generateUserId(bundleId);

  Future<UserProfile?> getUserProfile() => _getUserProfile();

  void dispose() {}

  Future<void> _handleLogout() async {
    _logger.info('AuthKit: handling logout');
    final bundleIds = _registeredBundleIds();
    await _setLastLoginId(null);

    for (final bundleId in bundleIds) {
      _broadcastUserChanged(bundleId: bundleId, reason: 'logout');
    }
  }

  Future<void> _handleAccountSwitch(String newLoginId) async {
    _logger.info('AuthKit: handling account switch');
    final bundleIds = _registeredBundleIds();
    await _setLastLoginId(newLoginId);

    for (final bundleId in bundleIds) {
      _broadcastUserChanged(bundleId: bundleId, reason: 'account_switch');
    }
  }

  Future<void> _handleLogin(String loginId) async {
    _logger.info('AuthKit: handling login (same account)');
    await _setLastLoginId(loginId);

    for (final bundleId in _registeredBundleIds()) {
      _broadcastUserChanged(
        bundleId: bundleId,
        reason: 'login',
        userId: _generateUserId(bundleId),
      );
    }
  }

  Iterable<String> _registeredBundleIds() {
    final appKit = _appKitService;
    if (appKit == null) return const [];
    return appKit.registeredBundleIds;
  }

  String? _generateUserId(String bundleId) {
    final id = _loginId;
    if (id == null) return null;
    final bytes = utf8.encode('$id:$bundleId');
    return sha256.convert(bytes).toString();
  }

  void _broadcastUserChanged({
    required String bundleId,
    required String reason,
    String? userId,
  }) {
    final appKit = _appKitService;
    if (appKit == null) return;
    final resolvedUserId = userId ?? _generateUserId(bundleId);
    final event = appKit.createAppEvent(
      type: AppEventType.authkitUserChanged,
      source: 'authkit',
      subject: bundleId,
      data: {
        'bundleId': bundleId,
        'reason': reason,
        'loggedIn': resolvedUserId != null,
        if (resolvedUserId != null) 'userId': resolvedUserId,
      },
    );
    appKit.publishAppEvent(bundleId, event);
  }

  Future<String?> _getLastLoginId() async {
    final box = await _ensureSessionBox();
    final raw = box.get(_lastLoginIdKey);
    if (raw is Map && raw.containsKey('loginId')) {
      return raw['loginId'] as String?;
    }
    return null;
  }

  Future<void> _setLastLoginId(String? loginId) async {
    final box = await _ensureSessionBox();
    if (loginId == null) {
      await box.delete(_lastLoginIdKey);
    } else {
      await box.put(_lastLoginIdKey, {'loginId': loginId});
    }
  }

  Future<UserProfile?> _getUserProfile() async {
    if (_serviceLocator is NearbyServiceLocator) {
      return (_serviceLocator as NearbyServiceLocator).getUserProfile();
    }
    return null;
  }

  Future<Box<Map>> _ensureSessionBox() async {
    final current = _sessionBox;
    if (current != null && current.isOpen) return current;
    await _hiveProvider.init();
    _sessionBox = await Hive.openBox<Map>('authkit_session');
    return _sessionBox!;
  }
}
