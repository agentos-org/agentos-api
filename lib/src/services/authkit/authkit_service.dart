import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:hive/hive.dart';
import 'package:logging/logging.dart';
import 'package:unique_id_dart/unique_id_dart.dart';

import '../../locator.dart';
import '../../models/app/app_models.dart';
import '../../repository/hive/hive_provider.dart';
import '../appkit/appkit_service.dart';

final Logger _logger = Logger('AuthKitService');

class _Sentinel {
  const _Sentinel();
}
const _sentinel = _Sentinel();

enum AuthRequestStatus { pending, granted, denied, timeout }

/// Token validation result with specific error codes.
enum TokenValidationResult {
  valid,
  invalidToken,
  authExpired,
  tokenRevoked,
}

class AuthRequest {
  final String requestId;
  final String bundleId;
  final String? appName;
  final List<String> scopes;
  final DateTime createdAt;
  AuthRequestStatus status;
  String? authCode;

  AuthRequest({
    required this.requestId,
    required this.bundleId,
    this.appName,
    required this.scopes,
    required this.createdAt,
    this.status = AuthRequestStatus.pending,
    this.authCode,
  });

  bool get isExpired =>
      DateTime.now().difference(createdAt) > const Duration(minutes: 3);
}

class AuthKitGrant {
  final String bundleId;
  final String? appName;
  final String? userId;
  final List<String> scopes;
  final DateTime grantedAt;

  const AuthKitGrant({
    required this.bundleId,
    this.appName,
    this.userId,
    required this.scopes,
    required this.grantedAt,
  });

  AuthKitGrant copyWith({
    Object? appName = _sentinel,
    Object? userId = _sentinel,
  }) => AuthKitGrant(
    bundleId: bundleId,
    appName: appName == _sentinel ? this.appName : appName as String?,
    userId: userId == _sentinel ? this.userId : userId as String?,
    scopes: scopes,
    grantedAt: grantedAt,
  );

  Map<String, dynamic> toJson() => {
    'bundleId': bundleId,
    if (appName != null) 'appName': appName,
    if (userId != null) 'userId': userId,
    'scopes': scopes,
    'grantedAt': grantedAt.toIso8601String(),
  };

  factory AuthKitGrant.fromJson(Map<dynamic, dynamic> json) {
    return AuthKitGrant(
      bundleId: json['bundleId'] as String,
      appName: json['appName'] as String?,
      userId: json['userId'] as String?,
      scopes: (json['scopes'] as List).cast<String>(),
      grantedAt: DateTime.parse(json['grantedAt'] as String),
    );
  }
}

class AuthKitUserInfo {
  final String name;
  final String avatarUrl;

  const AuthKitUserInfo({required this.name, required this.avatarUrl});

  Map<String, dynamic> toJson() => {'name': name, 'avatarUrl': avatarUrl};
}

/// AuthKit service managing authorization flow for third-party apps.
///
/// App authorization lifecycle follows AgentOS login state:
/// - Login (same account): broadcast `login` to all registered apps
/// - Login (different account / first login): clear all grants+tokens, broadcast `account_switch`
/// - Logout: clear all grants+tokens, broadcast `logout`
/// - Token validity requires AgentOS to be in logged-in state
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

  final Map<String, AuthRequest> _pendingRequests = {};
  final Map<String, String> _accessTokens = {};
  final Map<String, String> _authCodeToBundle = {};

  Box<Map>? _grantsBox;
  Box<String>? _tokensBox;

  /// Stream of authorization requests for desktop UI to display.
  final _authRequestController = StreamController<AuthRequest>.broadcast();
  Stream<AuthRequest> get authRequestStream => _authRequestController.stream;

  /// Inject or replace the AppKitService used for broadcasting events.
  void setAppKitService(AppKitService service) {
    _appKitService = service;
  }

  /// Update the current login user ID.
  ///
  /// Determines the login state change type and acts accordingly:
  /// - **logout** (loginId == null): clear all grants/tokens, broadcast logout
  /// - **account_switch** (loginId differs from last persisted): clear all, broadcast account_switch
  /// - **login** (loginId same as last persisted): broadcast login only
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

  /// Get the current login ID (may be null when logged out).
  String? get loginId => _loginId;

  /// Whether AgentOS is currently in a logged-in state.
  bool get isLoggedIn => _loginId != null;

  /// Initiate an authorization request.
  ///
  /// [appName] is an optional display name supplied by the requesting app.
  /// When provided it is persisted alongside the grant so the desktop UI can
  /// show a friendly name even if the app is not installed locally.
  ///
  /// Returns the request directly with authCode if already granted previously.
  Future<AuthRequest> authorize({
    required String bundleId,
    String? appName,
    List<String> scopes = const ['profile'],
  }) async {
    final grant = await _getGrant(bundleId);
    if (grant != null) {
      final needsUpdate = (appName != null && appName != grant.appName) ||
          (grant.userId == null && _loginId != null) ||
          (grant.userId != null && grant.userId != _generateUserId(bundleId));
      if (needsUpdate) {
        await _saveGrant(grant.copyWith(
          appName: appName ?? grant.appName,
          userId: _generateUserId(bundleId),
        ));
      }
      final authCode = _issueAuthCode(bundleId);
      final request = AuthRequest(
        requestId: uniqueId(shorter: true),
        bundleId: bundleId,
        appName: appName ?? grant.appName,
        scopes: scopes,
        createdAt: DateTime.now(),
        status: AuthRequestStatus.granted,
        authCode: authCode,
      );
      _logger.info('AuthKit: auto-granted for $bundleId (previously authorized)');
      return request;
    }

    final request = AuthRequest(
      requestId: uniqueId(shorter: true),
      bundleId: bundleId,
      appName: appName,
      scopes: scopes,
      createdAt: DateTime.now(),
    );
    _pendingRequests[request.requestId] = request;
    _authRequestController.add(request);

    _scheduleTimeout(request.requestId);
    _logger.info('AuthKit: authorization requested for $bundleId, requestId=${request.requestId}');
    return request;
  }

  /// Get the status of a pending authorization request.
  AuthRequest? getRequestStatus(String requestId) {
    final request = _pendingRequests[requestId];
    if (request != null && request.isExpired && request.status == AuthRequestStatus.pending) {
      request.status = AuthRequestStatus.timeout;
    }
    return request;
  }

  /// Grant an authorization request (called by desktop UI).
  Future<void> grantRequest(String requestId) async {
    final request = _pendingRequests[requestId];
    if (request == null || request.status != AuthRequestStatus.pending) return;

    final authCode = _issueAuthCode(request.bundleId);
    request.status = AuthRequestStatus.granted;
    request.authCode = authCode;

    await _saveGrant(AuthKitGrant(
      bundleId: request.bundleId,
      appName: request.appName,
      userId: _generateUserId(request.bundleId),
      scopes: request.scopes,
      grantedAt: DateTime.now(),
    ));
    _logger.info('AuthKit: granted requestId=$requestId');
  }

  /// Deny an authorization request (called by desktop UI).
  void denyRequest(String requestId) {
    final request = _pendingRequests[requestId];
    if (request == null || request.status != AuthRequestStatus.pending) return;
    request.status = AuthRequestStatus.denied;
    _logger.info('AuthKit: denied requestId=$requestId');
  }

  /// Exchange authCode for access token + user info.
  Future<Map<String, dynamic>?> exchangeToken(String authCode) async {
    final bundleId = _authCodeToBundle.remove(authCode);
    if (bundleId == null) return null;

    final accessToken = 'akt-${uniqueId(shorter: true)}';
    _accessTokens[accessToken] = bundleId;
    await _persistToken(accessToken, bundleId);

    final profile = await _getUserProfile();
    final userInfo = {
      'name': profile?.name ?? 'AgentOS User',
      'avatarUrl': '/authkit/avatar',
    };

    final grant = await _getGrant(bundleId);

    _logger.info('AuthKit: token exchanged for bundleId=$bundleId');
    return {
      'accessToken': accessToken,
      'userInfo': userInfo,
      if (grant?.userId != null) 'userId': grant!.userId,
    };
  }

  /// Get user info using access token.
  Future<AuthKitUserInfo?> getUserInfo(String accessToken) async {
    final bundleId = await _resolveTokenBundleId(accessToken);
    if (bundleId == null) return null;

    final profile = await _getUserProfile();
    return AuthKitUserInfo(
      name: profile?.name ?? 'AgentOS User',
      avatarUrl: '/authkit/avatar',
    );
  }

  /// Validate an access token (simple bool check).
  Future<bool> isAccessTokenValid(String accessToken) async {
    return (await validateAccessToken(accessToken)) == TokenValidationResult.valid;
  }

  /// Validate an access token with a specific result code.
  ///
  /// Returns:
  /// - [TokenValidationResult.valid] if token is valid and AgentOS is logged in
  /// - [TokenValidationResult.authExpired] if AgentOS user is not logged in
  /// - [TokenValidationResult.tokenRevoked] if token exists but grant was revoked
  /// - [TokenValidationResult.invalidToken] if token is not recognized
  Future<TokenValidationResult> validateAccessToken(String accessToken) async {
    final bundleId = await _resolveTokenBundleId(accessToken);
    if (bundleId == null) return TokenValidationResult.invalidToken;

    if (!isLoggedIn) return TokenValidationResult.authExpired;

    final grant = await _getGrant(bundleId);
    if (grant == null) return TokenValidationResult.tokenRevoked;

    return TokenValidationResult.valid;
  }

  /// Get avatar data (base64 or URL) for proxy endpoint.
  Future<UserProfile?> getAvatarProfile() => _getUserProfile();

  /// Revoke authorization for a bundle.
  Future<void> revokeGrant(String bundleId) async {
    final box = await _ensureGrantsBox();
    await box.delete(bundleId);
    _accessTokens.removeWhere((_, v) => v == bundleId);
    await _removeTokensForBundle(bundleId);
    _logger.info('AuthKit: revoked grant for $bundleId');
  }

  /// Clear all persisted grants and tokens.
  ///
  /// In-flight pending requests are preserved so the authorization flow
  /// can continue (e.g. re-prompt after a login/account-switch).
  Future<void> clearAllGrants() async {
    final grantsBox = await _ensureGrantsBox();
    final tokensBox = await _ensureTokensBox();

    final lastLoginId = grantsBox.get(_lastLoginIdKey);
    await grantsBox.clear();
    if (lastLoginId != null) {
      await grantsBox.put(_lastLoginIdKey, lastLoginId);
    }

    await tokensBox.clear();
    _accessTokens.clear();
    _logger.info('AuthKit: all grants and tokens cleared');
  }

  /// List all granted authorizations.
  Future<List<AuthKitGrant>> listGrants() async {
    final box = await _ensureGrantsBox();
    return box.keys
        .where((k) => k != _lastLoginIdKey)
        .map((k) => box.get(k))
        .whereType<Map>()
        .map((v) => AuthKitGrant.fromJson(v))
        .toList();
  }

  void dispose() {
    _authRequestController.close();
  }

  // --- Login state handlers ---

  Future<void> _handleLogout() async {
    _logger.info('AuthKit: handling logout — clearing all grants');
    final grants = await listGrants();
    final pendingBundleIds = _pendingBundleIds();

    await clearAllGrants();
    await _setLastLoginId(null);

    for (final grant in grants) {
      if (pendingBundleIds.contains(grant.bundleId)) continue;
      _broadcastUserChanged(bundleId: grant.bundleId, reason: 'logout');
    }
  }

  Future<void> _handleAccountSwitch(String newLoginId) async {
    _logger.info('AuthKit: handling account switch — clearing all grants');
    final grants = await listGrants();
    final pendingBundleIds = _pendingBundleIds();

    await clearAllGrants();
    await _setLastLoginId(newLoginId);

    for (final grant in grants) {
      if (pendingBundleIds.contains(grant.bundleId)) continue;
      _broadcastUserChanged(bundleId: grant.bundleId, reason: 'account_switch');
    }

    _reEmitPendingRequests();
  }

  Future<void> _handleLogin(String loginId) async {
    _logger.info('AuthKit: handling login (same account)');
    await _setLastLoginId(loginId);

    final pendingBundleIds = _pendingBundleIds();
    final grants = await listGrants();
    for (final grant in grants) {
      if (pendingBundleIds.contains(grant.bundleId)) continue;
      final newUserId = _generateUserId(grant.bundleId);
      if (newUserId != grant.userId) {
        await _saveGrant(grant.copyWith(userId: newUserId));
      }
      _broadcastUserChanged(
        bundleId: grant.bundleId,
        reason: 'login',
        userId: newUserId,
      );
    }

    _reEmitPendingRequests();
  }

  /// BundleIds that currently have a pending (in-flight) authorization request.
  Set<String> _pendingBundleIds() {
    return _pendingRequests.values
        .where((r) => r.status == AuthRequestStatus.pending && !r.isExpired)
        .map((r) => r.bundleId)
        .toSet();
  }

  /// Re-emit pending authorization requests to the Desktop UI stream so that
  /// the confirmation dialog is shown again after a login/account-switch.
  void _reEmitPendingRequests() {
    final pending = _pendingRequests.values
        .where((r) => r.status == AuthRequestStatus.pending && !r.isExpired)
        .toList();
    if (pending.isEmpty) return;

    _logger.info('AuthKit: re-emitting ${pending.length} pending request(s) to Desktop UI');
    for (final request in pending) {
      _authRequestController.add(request);
    }
  }

  // --- Private ---

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
    final event = appKit.createAppEvent(
      type: AppEventType.authkitUserChanged,
      source: 'authkit',
      subject: bundleId,
      data: {
        'bundleId': bundleId,
        'reason': reason,
        'loggedIn': userId != null,
        if (userId != null) 'userId': userId,
      },
    );
    appKit.publishAppEvent(bundleId, event);
  }

  Future<String?> _getLastLoginId() async {
    final box = await _ensureGrantsBox();
    final raw = box.get(_lastLoginIdKey);
    if (raw is Map && raw.containsKey('loginId')) {
      return raw['loginId'] as String?;
    }
    return null;
  }

  Future<void> _setLastLoginId(String? loginId) async {
    final box = await _ensureGrantsBox();
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

  String _issueAuthCode(String bundleId) {
    final code = 'ac-${uniqueId(shorter: true)}';
    _authCodeToBundle[code] = bundleId;
    return code;
  }

  void _scheduleTimeout(String requestId) {
    Future.delayed(const Duration(minutes: 3), () {
      final request = _pendingRequests[requestId];
      if (request != null && request.status == AuthRequestStatus.pending) {
        request.status = AuthRequestStatus.timeout;
      }
    });
  }

  Future<AuthKitGrant?> _getGrant(String bundleId) async {
    final box = await _ensureGrantsBox();
    final raw = box.get(bundleId);
    if (raw == null) return null;
    return AuthKitGrant.fromJson(raw);
  }

  Future<void> _saveGrant(AuthKitGrant grant) async {
    final box = await _ensureGrantsBox();
    await box.put(grant.bundleId, grant.toJson());
  }

  Future<Box<Map>> _ensureGrantsBox() async {
    final current = _grantsBox;
    if (current != null && current.isOpen) return current;
    await _hiveProvider.init();
    _grantsBox = await Hive.openBox<Map>('authkit_grants');
    return _grantsBox!;
  }

  Future<Box<String>> _ensureTokensBox() async {
    final current = _tokensBox;
    if (current != null && current.isOpen) return current;
    await _hiveProvider.init();
    _tokensBox = await Hive.openBox<String>('authkit_tokens');
    return _tokensBox!;
  }

  /// Resolve bundleId for a token, checking memory cache first then persistent storage.
  Future<String?> _resolveTokenBundleId(String accessToken) async {
    final cached = _accessTokens[accessToken];
    if (cached != null) return cached;

    final box = await _ensureTokensBox();
    final bundleId = box.get(accessToken);
    if (bundleId != null) {
      _accessTokens[accessToken] = bundleId;
    }
    return bundleId;
  }

  Future<void> _persistToken(String accessToken, String bundleId) async {
    final box = await _ensureTokensBox();
    await box.put(accessToken, bundleId);
  }

  Future<void> _removeTokensForBundle(String bundleId) async {
    final box = await _ensureTokensBox();
    final keysToRemove = <String>[];
    for (final key in box.keys) {
      if (box.get(key) == bundleId) {
        keysToRemove.add(key as String);
      }
    }
    for (final key in keysToRemove) {
      await box.delete(key);
    }
  }
}
