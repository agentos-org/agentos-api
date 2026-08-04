import 'dart:async';
import 'dart:convert';

import 'package:hive/hive.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;

import '../../locator.dart';
import '../../repository/hive/hive_provider.dart';
import '../../services/appkit/appkit_service.dart';

final Logger _logger = Logger('TransferKitService');

/// TransferKit service for file transfer between AgentOS devices.
class TransferKitService {
  TransferKitService({
    required AgentOSServiceLocator serviceLocator,
    required AppKitService appKitService,
    HiveProvider? hiveProvider,
  }) : _serviceLocator = serviceLocator,
       _appKitService = appKitService,
       _hiveProvider = hiveProvider ?? HiveProvider();

  final AgentOSServiceLocator _serviceLocator;
  final AppKitService _appKitService;
  final HiveProvider _hiveProvider;

  final Map<String, TransferSession> _transfers = {};
  final _transferProgressController = StreamController<TransferSession>.broadcast();
  StreamSubscription<TransferSession>? _progressSub;

  Box<String>? _policyBox;
  Box<String>? _historyBox;

  NearbyServiceLocator? get _nearby =>
      _serviceLocator is NearbyServiceLocator
          ? _serviceLocator as NearbyServiceLocator
          : null;

  bool get isAvailable => _nearby != null && _nearby!.nearbyTransferEnabled;

  void _ensureProgressListener() {
    if (_progressSub != null) return;
    final nearby = _nearby;
    if (nearby == null) return;
    final stream = nearby.fileTransferProgressStream;
    if (stream == null) return;
    _progressSub = stream.listen((session) {
      _transfers[session.transferId] = session;
      _transferProgressController.add(session);
    });
  }

  /// Send files to a target device.
  ///
  /// [bundleId] is resolved from the bearer token.
  /// [dataDir] is the app's sandboxed data directory for path validation.
  Future<TransferSession?> sendFiles({
    required String targetDeviceId,
    required String bundleId,
    required List<TransferFileInfo> files,
    String? dataDir,
  }) async {
    final nearby = _nearby;
    if (nearby == null || !nearby.nearbyTransferEnabled) {
      return null;
    }
    _ensureProgressListener();

    // Validate all file paths are within the app's sandbox (skip if no sandbox configured)
    if (dataDir != null) {
      for (final file in files) {
        if (!_isPathInSandbox(file.filePath, dataDir)) {
          _logger.warning(
            'TransferKit: path traversal attempt: ${file.filePath} not in $dataDir',
          );
          return null;
        }
      }
    }

    final session = await nearby.sendFiles(
      targetDeviceId: targetDeviceId,
      bundleId: bundleId,
      files: files,
    );

    _transfers[session.transferId] = session;
    return session;
  }

  /// Get transfer status.
  TransferSession? getTransferStatus(String transferId) =>
      _transfers[transferId];

  /// Get all transfers for a bundle.
  List<TransferSession> getTransfersForBundle(String bundleId) =>
      _transfers.values.where((t) => t.bundleId == bundleId).toList();

  /// Cancel a transfer.
  bool cancelTransfer(String transferId) {
    final session = _transfers[transferId];
    if (session == null) return false;
    if (session.state == TransferState.completed ||
        session.state == TransferState.cancelled) {
      return false;
    }
    session.state = TransferState.cancelled;
    return true;
  }

  /// Get transfer progress stream for SSE.
  Stream<TransferSession> get transferProgressStream {
    _ensureProgressListener();
    return _transferProgressController.stream;
  }

  /// Get incoming transfer stream for a specific bundleId.
  Stream<IncomingTransferEvent>? getIncomingStream() {
    return _nearby?.incomingTransferStream;
  }

  // --- Receive Policy ---

  Future<FileReceivePolicy> getPolicy({String? bundleId}) async {
    final box = await _ensurePolicyBox();
    final key = bundleId ?? '_default';
    final value = box.get(key);
    if (value == null) return FileReceivePolicy.autoAccept;
    return FileReceivePolicy.values.firstWhere(
      (p) => p.name == value,
      orElse: () => FileReceivePolicy.autoAccept,
    );
  }

  Future<void> setPolicy(FileReceivePolicy policy, {String? bundleId}) async {
    final box = await _ensurePolicyBox();
    final key = bundleId ?? '_default';
    await box.put(key, policy.name);
    _logger.info('TransferKit: policy set to ${policy.name} for ${bundleId ?? "default"}');
  }

  /// Push incoming file event to the target app via AppKit SSE.
  void notifyIncomingFile(IncomingTransferEvent event) {
    final appEvent = _appKitService.createAppEvent(
      type: 'transferkit.file.received',
      source: 'transferkit',
      subject: event.sourceBundleId,
      data: event.toJson(),
    );
    _appKitService.publishAppEvent(event.sourceBundleId, appEvent);
  }

  // --- Transfer History ---

  /// History is scoped by `deviceId:userId`.
  /// Settings panel uses empty userId; third-party apps use their userId.
  String _historyScope(String deviceId, String? userId) =>
      '$deviceId:${userId ?? ''}';

  /// Add a history record.
  Future<void> addHistory(
    TransferHistoryRecord record, {
    required String deviceId,
    String? userId,
  }) async {
    final box = await _ensureHistoryBox();
    final scope = _historyScope(deviceId, userId);
    final list = _loadHistoryList(box, scope);
    list.insert(0, record);
    await box.put(scope, jsonEncode(list.map((r) => r.toJson()).toList()));
    _logger.info('TransferKit: history added (${record.direction.name}) '
        'scope=$scope id=${record.id}');
  }

  /// Get all history for a scope, newest first.
  Future<List<TransferHistoryRecord>> getHistory({
    required String deviceId,
    String? userId,
  }) async {
    final box = await _ensureHistoryBox();
    final scope = _historyScope(deviceId, userId);
    return _loadHistoryList(box, scope);
  }

  /// Delete a single history record by id.
  Future<bool> deleteHistory(
    String recordId, {
    required String deviceId,
    String? userId,
  }) async {
    final box = await _ensureHistoryBox();
    final scope = _historyScope(deviceId, userId);
    final list = _loadHistoryList(box, scope);
    final before = list.length;
    list.removeWhere((r) => r.id == recordId);
    if (list.length == before) return false;
    await box.put(scope, jsonEncode(list.map((r) => r.toJson()).toList()));
    return true;
  }

  /// Clear all history for a scope.
  Future<void> clearHistory({
    required String deviceId,
    String? userId,
  }) async {
    final box = await _ensureHistoryBox();
    final scope = _historyScope(deviceId, userId);
    await box.delete(scope);
    _logger.info('TransferKit: history cleared scope=$scope');
  }

  void dispose() {
    _progressSub?.cancel();
    _transferProgressController.close();
  }

  // --- Private ---

  bool _isPathInSandbox(String filePath, String sandboxDir) {
    final canonicalFile = p.canonicalize(filePath);
    final canonicalDir = p.canonicalize(sandboxDir);
    return canonicalFile.startsWith(canonicalDir);
  }

  Future<Box<String>> _ensurePolicyBox() async {
    final current = _policyBox;
    if (current != null && current.isOpen) return current;
    await _hiveProvider.init();
    _policyBox = await Hive.openBox<String>('transferkit_policies');
    return _policyBox!;
  }

  Future<Box<String>> _ensureHistoryBox() async {
    final current = _historyBox;
    if (current != null && current.isOpen) return current;
    await _hiveProvider.init();
    _historyBox = await Hive.openBox<String>('transferkit_history');
    return _historyBox!;
  }

  List<TransferHistoryRecord> _loadHistoryList(Box<String> box, String scope) {
    final raw = box.get(scope);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((e) =>
              TransferHistoryRecord.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      _logger.warning('TransferKit: failed to parse history for $scope: $e');
      return [];
    }
  }
}
