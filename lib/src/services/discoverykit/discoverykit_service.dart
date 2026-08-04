import 'dart:async';

import 'package:logging/logging.dart';

import '../../locator.dart';
import '../authkit/authkit_service.dart';

final Logger _logger = Logger('DiscoveryKitService');

/// DiscoveryKit service for discovering nearby AgentOS devices.
///
/// Supports per-app registration: each app on this device can register itself
/// via [registerApp] after obtaining a userId from AuthKit. The registered
/// apps are broadcast to peers as part of the multicast announcement.
class DiscoveryKitService {
  DiscoveryKitService({
    required AgentOSServiceLocator serviceLocator,
    AuthKitService? authKitService,
  }) : _serviceLocator = serviceLocator,
       _authKitService = authKitService;

  final AgentOSServiceLocator _serviceLocator;
  AuthKitService? _authKitService;

  void setAuthKitService(AuthKitService service) {
    _authKitService = service;
  }

  NearbyServiceLocator? get _nearby =>
      _serviceLocator is NearbyServiceLocator
          ? _serviceLocator as NearbyServiceLocator
          : null;

  /// Register an app into discovery broadcast.
  ///
  /// [bundleId] identifies the app.
  /// [userId] must match an existing AuthKit grant for [bundleId].
  /// [username] and [appName] are optional display fields.
  bool registerApp({
    required String bundleId,
    String? userId,
    String? username,
    String? appName,
    String? avatarUrl,
    FileReceivePolicy? receivePolicy,
  }) {
    final nearby = _nearby;
    if (nearby == null) {
      _logger.warning('DiscoveryKit: registerApp failed — nearby not available');
      return false;
    }

    if (userId != null) {
      final authKit = _authKitService;
      if (authKit == null) {
        _logger.warning('DiscoveryKit: registerApp failed — authKit not available for userId verification');
        return false;
      }
    }

    final policy = receivePolicy ?? FileReceivePolicy.autoAccept;

    nearby.registerDiscoveryApp(DiscoveryRegistration(
      bundleId: bundleId,
      userId: userId,
      username: username,
      appName: appName,
      avatarUrl: avatarUrl,
      receivePolicy: policy,
    ));

    _logger.info('DiscoveryKit: registered app $bundleId (userId=${userId ?? 'null'}, receivePolicy=${policy.name})');
    return true;
  }

  /// Unregister an app from discovery broadcast.
  bool unregisterApp(String bundleId) {
    final nearby = _nearby;
    if (nearby == null) return false;

    nearby.unregisterDiscoveryApp(bundleId);
    _logger.info('DiscoveryKit: unregistered app $bundleId');
    return true;
  }

  /// Get all currently registered apps on this device.
  List<DiscoveryRegistration> getRegisteredApps() {
    return _nearby?.registeredApps ?? const [];
  }

  /// Get filtered peer devices based on scan level.
  ///
  /// When [callerBundleId] is null (device-level scan from AgentOS settings),
  /// only device-level targets are returned (apps where isDeviceLevel == true).
  /// The local device's own device-level target is excluded.
  ///
  /// When [callerBundleId] is non-null (app-level scan), only app-level
  /// targets with the same bundleId are returned. The caller's own
  /// registration is excluded.
  List<PeerDevice> getPeers({String? callerBundleId}) {
    final nearby = _nearby;
    if (nearby == null || !nearby.nearbyTransferEnabled) {
      return const [];
    }

    final remotePeers = nearby.discoveredPeers;
    final selfPeer = nearby.selfDeviceAsPeer(excludeBundleId: callerBundleId);
    final allPeers = selfPeer.apps.isEmpty
        ? remotePeers
        : [...remotePeers, selfPeer];

    return _filterPeers(allPeers, callerBundleId: callerBundleId,
        selfDeviceId: nearby.deviceFingerprint);
  }

  /// Apply scan-level filtering rules.
  ///
  /// Device-level: returns device info with empty apps, excludes self.
  /// App-level: returns device info + only matching bundleId apps.
  List<PeerDevice> _filterPeers(
    List<PeerDevice> peers, {
    String? callerBundleId,
    required String selfDeviceId,
  }) {
    final result = <PeerDevice>[];
    for (final peer in peers) {
      final isLocalDevice = peer.deviceId == selfDeviceId;

      if (callerBundleId == null) {
        if (isLocalDevice) continue;
        result.add(PeerDevice(
          deviceId: peer.deviceId,
          name: peer.name,
          avatarUrl: peer.avatarUrl,
          deviceName: peer.deviceName,
          deviceType: peer.deviceType,
          host: peer.host,
          port: peer.port,
          online: peer.online,
          apps: const [],
        ));
      } else {
        final filteredApps = peer.apps
            .where((a) => !a.isDeviceLevel && a.bundleId == callerBundleId)
            .toList();
        if (filteredApps.isEmpty) continue;
        result.add(PeerDevice(
          deviceId: peer.deviceId,
          name: peer.name,
          avatarUrl: peer.avatarUrl,
          deviceName: peer.deviceName,
          deviceType: peer.deviceType,
          host: peer.host,
          port: peer.port,
          online: peer.online,
          apps: filteredApps,
        ));
      }
    }
    return result;
  }

  /// Get peer device event stream for SSE.
  Stream<PeerDeviceEvent>? getPeerEventStream() {
    final nearby = _nearby;
    if (nearby == null || !nearby.nearbyTransferEnabled) {
      return null;
    }
    return nearby.peerEventStream;
  }

  /// Get self device info.
  Map<String, dynamic>? getSelfInfo() {
    final nearby = _nearby;
    if (nearby == null) return null;
    return {
      'deviceId': nearby.deviceFingerprint,
      'deviceName': nearby.deviceDisplayName,
      'nearbyTransferEnabled': nearby.nearbyTransferEnabled,
      'registeredApps': nearby.registeredApps
          .map((r) => {
                'bundleId': r.bundleId,
                if (r.userId != null) 'userId': r.userId,
                if (r.username != null) 'username': r.username,
                if (r.appName != null) 'appName': r.appName,
              })
          .toList(),
    };
  }

  bool get isAvailable => _nearby != null && _nearby!.nearbyTransferEnabled;
}
