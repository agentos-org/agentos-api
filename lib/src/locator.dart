import 'dart:async';

import 'services/modelkit/app_model_id.dart';
import 'services/toolkit/app_open_tool_provider.dart';

/// Unified service state across all service types
enum ServiceState { stopped, starting, running, error }

/// File receive policy for incoming transfers.
enum FileReceivePolicy { autoAccept, requireConfirm }

/// Service status change event emitted by [AgentOSServiceLocator.serviceStatusStream]
class ServiceStatusEvent {
  /// Service identifier (matches [ApiConfig] service constants)
  final String serviceKey;

  final ServiceState state;

  /// Service port when running; null otherwise
  final int? port;

  final String? message;

  /// Model identifier for LLM services.
  /// Null for non-LLM services.
  final String? modelId;

  /// Model type string for LLM services (e.g. 'textGeneration', 'audioTextToText').
  /// Matches [LlmModelInfo.type]. Null for non-LLM services.
  final String? modelType;

  const ServiceStatusEvent({
    required this.serviceKey,
    required this.state,
    this.port,
    this.message,
    this.modelId,
    this.modelType,
  });

  @override
  String toString() =>
      'ServiceStatusEvent($serviceKey, $state, port=$port'
      '${modelId != null ? ", model=$modelId" : ""}'
      '${modelType != null ? ", type=$modelType" : ""}'
      '${message != null ? ", $message" : ""})';
}

/// App information
class AppInfo {
  final String bundleId;
  final String version;
  final String description;
  final String name;

  const AppInfo({
    required this.bundleId,
    required this.version,
    required this.description,
    required this.name,
  });

  Map<String, dynamic> toJson() => {
    'bundleId': bundleId,
    'version': version,
    'description': description,
    'name': name,
  };
}

/// 模型的来源/归属分类（互斥，单一取值）。
///
/// 用一个显式枚举取代 `isRemote` / `isCustom` / `isAppModel` 三个布尔值的
/// 隐式组合，使外部使用端无需各自推导分类：
///
/// - [local]：在本机运行（本地内置/导入模型）；
/// - [platform]：AgentOS 平台下发的远端模型；
/// - [custom]：用户自行配置的远端模型；
/// - [app]：由第三方应用通过应用模型注册 API 注册的模型。
///
/// 运行位置（本机/云端）是次要信息，不再混入分类名称。
enum LlmModelSource {
  local('local'),
  platform('platform'),
  custom('custom'),
  app('app');

  const LlmModelSource(this.wireName);

  /// 对外下发的 wire 取值（`local` / `platform` / `custom` / `app`）。
  final String wireName;

  /// 按 wire 取值解析；未知或为空时返回 null。
  static LlmModelSource? tryParse(String? value) {
    if (value == null) return null;
    for (final source in LlmModelSource.values) {
      if (source.wireName == value) return source;
    }
    return null;
  }
}

/// LLM model information
class LlmModelInfo {
  final String id;
  final String name;
  final String alias;
  final String description;
  final String parameters;
  final num paramsB;
  final String quantization;
  final num sizeGB;
  final num minRAMGB;
  final String downloadUrl;
  final List<String> tags;
  final String repoId;

  /// Legacy IO-oriented type identifier preserved for wire compatibility
  /// (`textGeneration` / `imageTextToText` / `embedding` / `audioTextToText` /
  /// `textToSpeech`).
  ///
  /// Locators populate this verbatim from upstream metadata; controllers should
  /// not assume it carries the new task name. New code should consume [task].
  final String type;
  final int? contextWindowSize;

  /// Remote model's own base URL. Null means using the local service URL.
  final String? baseUrl;

  /// Remote model's own API key. Null means using the default key.
  final String? apiKey;

  /// Whether this model is a user-defined custom remote model.
  final bool isCustom;

  /// Whether this model is registered by a third-party app.
  final bool isAppModel;

  /// The bundle ID of the third-party app that registered this model.
  /// Null for non-app models.
  final String? appBundleId;

  /// Human-readable name of the third-party app that registered this model
  /// (for grouping/labelling in model pickers). Null for non-app models, or
  /// when the locator cannot provide one — consumers should then fall back to
  /// [appBundleId].
  final String? appName;

  /// Task-oriented identifier (`chat` / `embedding` / `asr` / `tts`).
  ///
  /// Optional to preserve binary compatibility with locators that still emit
  /// the legacy [type] only. ModelKit consumers prefer [task] and fall back
  /// to inferring from [type].
  final String? task;

  /// Input modality wire names (`text` / `image` / `audio` / `video`).
  ///
  /// Empty list means "unknown – locator did not populate". ModelKit echoes
  /// this directly to clients so they can self-describe multimodal inputs.
  final List<String> inputModalities;

  /// Output modality wire names; same conventions as [inputModalities].
  final List<String> outputModalities;

  /// Vision capability flag. Derived from `inputModalities` containing
  /// `image` (or `video`).
  final bool vision;

  /// Tool-calling capability flag.
  final bool toolCall;

  /// Streaming-output capability flag.
  final bool stream;

  /// Reasoning / deep-think capability flag. Mirrors the upstream
  /// `deepThink` field for remote models or `capabilities.reasoning` for
  /// local models. Defaults to `true` so callers that omit the flag keep
  /// reasoning enabled.
  final bool reasoning;

  /// Canonical LLM provider name as defined by the desktop model registry,
  /// constrained to `[openai, deepseek, glm, kimi, mimo, minimax, qwen]`.
  ///
  /// When agentos-api / agentos-kernel build a liteagent `LLMConfig`, this
  /// value is forwarded verbatim as the liteagent `adapter`, while the
  /// liteagent `provider` is always `lite_oneapi`. Defaults to `openai` for
  /// locators that don't populate it.
  final String provider;

  const LlmModelInfo({
    required this.id,
    required this.name,
    required this.alias,
    required this.description,
    required this.parameters,
    required this.paramsB,
    required this.quantization,
    required this.sizeGB,
    required this.minRAMGB,
    required this.downloadUrl,
    required this.tags,
    required this.repoId,
    required this.type,
    this.contextWindowSize,
    this.baseUrl,
    this.apiKey,
    this.isCustom = false,
    this.isAppModel = false,
    this.appBundleId,
    this.appName,
    this.task,
    this.inputModalities = const [],
    this.outputModalities = const [],
    this.vision = false,
    this.toolCall = false,
    this.stream = true,
    this.reasoning = true,
    this.provider = 'openai',
  });

  /// Whether this model is a remote model with its own endpoint.
  bool get isRemote => baseUrl != null && baseUrl!.isNotEmpty;

  /// 模型的来源分类（互斥），由现有布尔字段按固定优先级推导：
  ///
  /// 1. [isAppModel] → [LlmModelSource.app]（应用模型即使没有 baseUrl 也归应用）；
  /// 2. 非 [isRemote] → [LlmModelSource.local]；
  /// 3. [isCustom] → [LlmModelSource.custom]；
  /// 4. 其余 → [LlmModelSource.platform]。
  LlmModelSource get source {
    if (isAppModel) return LlmModelSource.app;
    if (!isRemote) return LlmModelSource.local;
    if (isCustom) return LlmModelSource.custom;
    return LlmModelSource.platform;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'alias': alias,
    'description': description,
    'parameters': parameters,
    'paramsB': paramsB,
    'quantization': quantization,
    'sizeGB': sizeGB,
    'minRAMGB': minRAMGB,
    'downloadUrl': downloadUrl,
    'tags': tags,
    'repoId': repoId,
    'type': type,
    if (contextWindowSize != null) 'contextWindowSize': contextWindowSize,
    if (baseUrl != null) 'baseUrl': baseUrl,
    if (apiKey != null) 'apiKey': apiKey,
    if (isCustom) 'isCustom': true,
    if (isAppModel) 'isAppModel': true,
    if (appBundleId != null) 'appBundleId': appBundleId,
    if (appName != null && appName!.isNotEmpty) 'appName': appName,
    'source': source.wireName,
    if (task != null) 'task': task,
    'provider': provider,
    if (inputModalities.isNotEmpty) 'input': inputModalities,
    if (outputModalities.isNotEmpty) 'output': outputModalities,
    'capabilities': {
      'vision': vision,
      'tool_call': toolCall,
      'stream': stream,
      'reasoning': reasoning,
    },
  };
}

/// AgentOS Service Locator Abstract Interface
///
/// Defines a generic interface for service discovery, allowing different implementations:
/// - Default implementation: Static configuration based on environment variables
/// - Desktop implementation: Gets dynamic info from agentos_desktop service manager
/// - Test implementation: Mock data for unit tests
abstract class AgentOSServiceLocator {
  /// Gets the LiteAgent service base URL
  String get liteagentBaseUrl;

  /// Stream of service status change events
  ///
  /// Emits [ServiceStatusEvent] whenever a managed service transitions
  /// between states (stopped/starting/running/error).
  ///
  /// Default (static) locators return an empty stream.
  /// Desktop implementations aggregate all local service status streams.
  Stream<ServiceStatusEvent> get serviceStatusStream;

  /// Gets the port number for the specified service
  ///
  /// [serviceKey] Service identifier, supported values:
  /// - 'liteagent': LiteAgent agent service
  /// - 'opentool': OpenTool tool service
  /// - 'embeddings': Embeddings server
  /// - 'llm_chat': Chat service (text + vision)
  /// - 'llm_embedding': LLM embedding model service
  /// - 'llm_tts': Text-to-speech service
  /// - 'llm_asr': Speech-to-text service
  /// - 'llm_decision': Decision-model service (llama.cpp `/v1/systemone`)
  ///
  /// [modelId] Optional model identifier for LLM services with multiple
  /// running instances. When provided, attempts to route to the specific
  /// model instance; falls back to the first available instance of that type.
  ///
  /// Returns null if service is not running or unavailable
  Future<int?> getServicePort(String serviceKey, {String? modelId});

  /// Gets registered app info list
  ///
  /// Returns app metadata for AppKit/intent routing usage
  Future<List<AppInfo>> getAppInfoList();

  /// Gets available LLM model list
  ///
  /// Returns LLM models registered by external implementations.
  /// Default implementation returns empty list.
  Future<List<LlmModelInfo>> getLlmModelList();
}

/// App model management mixin for [AgentOSServiceLocator].
///
/// Third-party applications register models through ModelKit API, and
/// locators that support app models implement this interface.
/// Default no-op implementations are provided via extension for backward
/// compatibility with locators that do not yet support app models.
///
/// App models are addressed by their hashid ([AppModelData.id]): a 12-character
/// hex id the gateway derives from `bundleId + name` (see [AppModelId]). It is
/// gateway-wide unique, so the store needs no bundle namespacing.
abstract class AppModelStore {
  /// Lists all app-registered models.
  List<AppModelData> get appModels;

  /// Adds an app-registered model.
  Future<void> addAppModel(AppModelData model);

  /// Updates the app-registered model identified by hashid [id].
  Future<bool> updateAppModel(String id, AppModelData model);

  /// Deletes the app-registered model identified by hashid [id].
  Future<bool> deleteAppModel(String id);

  /// Toggles the disabled state of the app-registered model identified by
  /// hashid [id].
  Future<bool> toggleAppModelDisabled(String id);

  /// Removes all models registered by a specific app.
  Future<int> removeAppModelsByBundleId(String bundleId);
}

/// App model data used at the API layer (independent of Hive persistence).
class AppModelData {
  /// The gateway-wide model id: a 12-character hashid generated by the gateway
  /// from `appBundleId + name` when the app registers the model (see
  /// [AppModelId.generate]). It stays stable for the lifetime of the
  /// registration (renaming the model does not change it), and is the id that
  /// `/modelkit/models` exposes, that the app uses to maintain the model, and
  /// that requests use to address it.
  final String id;
  final String name;
  final String alias;
  final String description;
  final String task;
  final String provider;
  final List<String> inputModalities;
  final List<String> outputModalities;
  final bool stream;
  final bool toolCall;
  final bool reasoning;
  final String? baseUrl;
  final String? apiKey;
  final int? contextSize;
  final bool isDisabled;
  final String appBundleId;
  final String appName;

  const AppModelData({
    required this.id,
    required this.name,
    this.alias = '',
    this.description = '',
    this.task = 'chat',
    this.provider = 'openai_compatible',
    this.inputModalities = const ['text'],
    this.outputModalities = const ['text'],
    this.stream = true,
    this.toolCall = false,
    this.reasoning = true,
    this.baseUrl,
    this.apiKey,
    this.contextSize,
    this.isDisabled = false,
    required this.appBundleId,
    this.appName = '',
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'alias': alias,
    'description': description,
    'task': task,
    'provider': provider,
    'input': inputModalities,
    'output': outputModalities,
    'capabilities': {
      'stream': stream,
      'tool_call': toolCall,
      'reasoning': reasoning,
    },
    if (baseUrl != null) 'baseUrl': baseUrl,
    'hasApiKey': (apiKey ?? '').isNotEmpty,
    if (contextSize != null) 'contextWindowSize': contextSize,
    'isDisabled': isDisabled,
    'appBundleId': appBundleId,
    'appName': appName,
  };
}

extension AgentOSServiceLocatorOpenToolConfig on AgentOSServiceLocator {
  /// Gets the OpenTool daemon host for kernel runtime integration.
  ///
  /// Older external implementations may not define this member yet, so this
  /// extension falls back to localhost.
  String get openToolDaemonHost {
    final dynamic self = this;
    try {
      final value = self.openToolDaemonHost;
      if (value is String) {
        final normalized = value.trim();
        if (normalized.isNotEmpty) {
          return normalized;
        }
      }
    } catch (_) {}
    return '127.0.0.1';
  }
}

extension AgentOSServiceLocatorAppOpenToolProvider on AgentOSServiceLocator {
  /// Optional host bridge for process App OpenTool providers.
  ///
  /// Kept optional so existing external service locators remain compatible.
  AppOpenToolProvider? get appOpenToolProvider {
    final dynamic self = this;
    try {
      final value = self.appOpenToolProvider;
      return value is AppOpenToolProvider ? value : null;
    } catch (_) {
      return null;
    }
  }
}

/// User public profile (avatar + name) exposed to third-party apps.
class UserProfile {
  final String name;
  final String? avatarUrl;

  const UserProfile({required this.name, this.avatarUrl});

  Map<String, dynamic> toJson() => {
    'name': name,
    if (avatarUrl != null) 'avatarUrl': avatarUrl,
  };
}

/// A registered app on a peer device, discovered via multicast.
class PeerApp {
  final String? bundleId;
  final String? userId;
  final String? username;
  final String? appName;
  final String? avatarUrl;

  const PeerApp({
    this.bundleId,
    this.userId,
    this.username,
    this.appName,
    this.avatarUrl,
  });

  bool get isDeviceLevel => userId == null;

  Map<String, dynamic> toJson() => {
    if (bundleId != null) 'bundleId': bundleId,
    if (userId != null) 'userId': userId,
    if (username != null) 'username': username,
    if (appName != null) 'appName': appName,
    if (avatarUrl != null) 'avatarUrl': avatarUrl,
  };

  factory PeerApp.fromJson(Map<String, dynamic> json) => PeerApp(
    bundleId: json['bundleId'] as String?,
    userId: json['userId'] as String?,
    username: json['username'] as String?,
    appName: json['appName'] as String?,
    avatarUrl: json['avatarUrl'] as String?,
  );
}

/// Nearby peer device information.
class PeerDevice {
  final String deviceId;
  final String name;
  final String? avatarUrl;
  final String deviceName;
  final String deviceType;
  final String host;
  final int port;
  final bool online;
  final List<PeerApp> apps;

  const PeerDevice({
    required this.deviceId,
    required this.name,
    this.avatarUrl,
    required this.deviceName,
    required this.deviceType,
    required this.host,
    required this.port,
    this.online = true,
    this.apps = const [],
  });

  Map<String, dynamic> toJson() => {
    'deviceId': deviceId,
    'name': name,
    if (avatarUrl != null) 'avatarUrl': avatarUrl,
    'deviceName': deviceName,
    'deviceType': deviceType,
    'host': host,
    'port': port,
    'online': online,
    'apps': apps.map((a) => a.toJson()).toList(),
  };
}

/// App-level discovery registration info (internal to this device).
class DiscoveryRegistration {
  final String bundleId;
  final String? userId;
  final String? username;
  final String? appName;
  final String? avatarUrl;
  final FileReceivePolicy receivePolicy;

  const DiscoveryRegistration({
    required this.bundleId,
    this.userId,
    this.username,
    this.appName,
    this.avatarUrl,
    this.receivePolicy = FileReceivePolicy.autoAccept,
  });
}

/// Nearby transfer capability extension interface.
///
/// Implemented by [RuntimeServiceLocator] when desktop host provides
/// user account and nearby-transfer settings. API layer detects via
/// `serviceLocator is NearbyServiceLocator`.
abstract class NearbyServiceLocator {
  Future<UserProfile?> getUserProfile();

  /// Emits whenever the host sets a new UserProfile (or clears it).
  Stream<UserProfile?> get userProfileChangedStream;

  String get deviceFingerprint;

  String get deviceDisplayName;

  bool get nearbyTransferEnabled;

  Stream<bool> get nearbyTransferEnabledStream;

  /// Currently discovered peer devices.
  List<PeerDevice> get discoveredPeers;

  /// Stream of peer device changes (join/leave).
  Stream<PeerDeviceEvent> get peerEventStream;

  /// Build a PeerDevice representing this device itself for local queries.
  ///
  /// [excludeBundleId] omits the registration belonging to this caller so
  /// that the caller never sees itself in the peer list.
  PeerDevice selfDeviceAsPeer({String? excludeBundleId});

  /// Register an app to be advertised via multicast discovery.
  void registerDiscoveryApp(DiscoveryRegistration registration);

  /// Unregister an app from discovery advertisement.
  void unregisterDiscoveryApp(String bundleId);

  /// All currently registered apps on this device.
  List<DiscoveryRegistration> get registeredApps;

  /// Send files to a target device.
  Future<TransferSession> sendFiles({
    required String targetDeviceId,
    required String bundleId,
    required List<TransferFileInfo> files,
    String? userId,
    String? targetBundleId,
    String? targetHost,
    int? targetPort,
  });

  /// Stream of file transfer progress updates.
  Stream<TransferSession>? get fileTransferProgressStream;

  /// Stream of incoming file transfer events.
  Stream<IncomingTransferEvent> get incomingTransferStream;

  /// Respond to a pending incoming transfer (accept or decline).
  /// Returns true if the transfer was found and responded to.
  bool respondToTransfer(String transferId, bool accept);

  /// Set file receive policy for a specific app (or the default).
  void setReceivePolicy(FileReceivePolicy policy, {String? bundleId});

  /// Get file receive policy for a specific app (falls back to default).
  FileReceivePolicy getReceivePolicy({String? bundleId});

  /// Set the base directory for saving received files.
  void setSaveDirectory(String path);
}

/// Peer device event types.
enum PeerDeviceEventType { joined, left, updated }

/// Peer device change event.
class PeerDeviceEvent {
  final PeerDeviceEventType type;
  final PeerDevice device;

  const PeerDeviceEvent({required this.type, required this.device});
}

/// File info for transfer.
class TransferFileInfo {
  final String fileName;
  final int size;
  final String filePath;
  final String? mimeType;

  const TransferFileInfo({
    required this.fileName,
    required this.size,
    required this.filePath,
    this.mimeType,
  });

  Map<String, dynamic> toJson() => {
    'fileName': fileName,
    'size': size,
    'filePath': filePath,
    if (mimeType != null) 'mimeType': mimeType,
  };
}

/// Transfer session state.
enum TransferState {
  pending,
  preparing,
  transferring,
  completed,
  failed,
  cancelled,
}

/// Per-file transfer state.
enum FileTransferState { pending, transferring, completed, failed }

/// Active transfer session.
class TransferSession {
  final String transferId;
  TransferState state;
  double progress;
  final String targetDeviceId;
  final String bundleId;
  final String? userId;
  final String? targetBundleId;
  final List<TransferFileInfo> files;
  String? errorMessage;

  /// Per-file progress: key is fileName, value is 0.0~1.0.
  final Map<String, double> fileProgress;

  /// Per-file state: key is fileName.
  final Map<String, FileTransferState> fileStates;

  TransferSession({
    required this.transferId,
    this.state = TransferState.pending,
    this.progress = 0.0,
    required this.targetDeviceId,
    required this.bundleId,
    this.userId,
    this.targetBundleId,
    required this.files,
    this.errorMessage,
    Map<String, double>? fileProgress,
    Map<String, FileTransferState>? fileStates,
  }) : fileProgress = fileProgress ?? {},
       fileStates = fileStates ?? {};

  Map<String, dynamic> toJson() => {
    'transferId': transferId,
    'state': state.name,
    'progress': progress,
    'targetDeviceId': targetDeviceId,
    'bundleId': bundleId,
    if (userId != null) 'userId': userId,
    if (targetBundleId != null) 'targetBundleId': targetBundleId,
    'files': files.map((f) => f.toJson()).toList(),
    if (errorMessage != null) 'errorMessage': errorMessage,
  };
}

/// Incoming file transfer event.
class IncomingTransferEvent {
  final String transferId;
  final String fromDeviceId;
  final String fromName;
  final String sourceBundleId;
  final String? targetBundleId;
  final bool autoAccepted;
  final List<ReceivedFileInfo> files;

  const IncomingTransferEvent({
    required this.transferId,
    required this.fromDeviceId,
    required this.fromName,
    required this.sourceBundleId,
    this.targetBundleId,
    this.autoAccepted = true,
    required this.files,
  });

  Map<String, dynamic> toJson() => {
    'transferId': transferId,
    'fromDeviceId': fromDeviceId,
    'fromName': fromName,
    'sourceBundleId': sourceBundleId,
    if (targetBundleId != null) 'targetBundleId': targetBundleId,
    'autoAccepted': autoAccepted,
    'files': files.map((f) => f.toJson()).toList(),
  };
}

/// Received file info.
class ReceivedFileInfo {
  final String fileName;
  final int size;
  final String savedPath;
  final String? mimeType;

  const ReceivedFileInfo({
    required this.fileName,
    required this.size,
    required this.savedPath,
    this.mimeType,
  });

  Map<String, dynamic> toJson() => {
    'fileName': fileName,
    'size': size,
    'savedPath': savedPath,
    if (mimeType != null) 'mimeType': mimeType,
  };
}

/// Direction of a transfer.
enum TransferDirection { send, receive }

/// A persisted transfer history record.
class TransferHistoryRecord {
  final String id;
  final TransferDirection direction;
  final String peerDeviceId;
  final String peerName;
  final String? peerAvatarUrl;
  final List<TransferHistoryFile> files;
  final int totalSize;
  final TransferState state;
  final DateTime timestamp;
  final String? savedDir;

  const TransferHistoryRecord({
    required this.id,
    required this.direction,
    required this.peerDeviceId,
    required this.peerName,
    this.peerAvatarUrl,
    required this.files,
    required this.totalSize,
    required this.state,
    required this.timestamp,
    this.savedDir,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'direction': direction.name,
    'peerDeviceId': peerDeviceId,
    'peerName': peerName,
    if (peerAvatarUrl != null) 'peerAvatarUrl': peerAvatarUrl,
    'files': files.map((f) => f.toJson()).toList(),
    'totalSize': totalSize,
    'state': state.name,
    'timestamp': timestamp.toIso8601String(),
    if (savedDir != null) 'savedDir': savedDir,
  };

  factory TransferHistoryRecord.fromJson(Map<String, dynamic> json) {
    return TransferHistoryRecord(
      id: json['id'] as String,
      direction: TransferDirection.values.firstWhere(
        (d) => d.name == json['direction'],
        orElse: () => TransferDirection.send,
      ),
      peerDeviceId: json['peerDeviceId'] as String,
      peerName: json['peerName'] as String,
      peerAvatarUrl: json['peerAvatarUrl'] as String?,
      files: (json['files'] as List)
          .map((f) => TransferHistoryFile.fromJson(f as Map<String, dynamic>))
          .toList(),
      totalSize: json['totalSize'] as int,
      state: TransferState.values.firstWhere(
        (s) => s.name == json['state'],
        orElse: () => TransferState.completed,
      ),
      timestamp: DateTime.parse(json['timestamp'] as String),
      savedDir: json['savedDir'] as String?,
    );
  }
}

/// A file entry inside a transfer history record.
class TransferHistoryFile {
  final String fileName;
  final int size;
  final String? filePath;

  const TransferHistoryFile({
    required this.fileName,
    required this.size,
    this.filePath,
  });

  Map<String, dynamic> toJson() => {
    'fileName': fileName,
    'size': size,
    if (filePath != null) 'filePath': filePath,
  };

  factory TransferHistoryFile.fromJson(Map<String, dynamic> json) {
    return TransferHistoryFile(
      fileName: json['fileName'] as String,
      size: json['size'] as int,
      filePath: json['filePath'] as String?,
    );
  }
}

/// Default Service Locator Implementation
///
/// Static configuration based on defaults, suitable for:
/// - Standalone agentos-api server deployment
/// - Development and testing environments
/// - Simple single-machine deployment scenarios
class DefaultServiceLocator implements AgentOSServiceLocator {
  DefaultServiceLocator({
    String? liteagentBaseUrl,
    String? openToolDaemonHost,
    Map<String, int>? servicePorts,
  }) : _liteagentBaseUrl = liteagentBaseUrl ?? _defaultLiteagentBaseUrl,
       _openToolDaemonHost = _normalizeHost(openToolDaemonHost),
       _servicePorts = servicePorts ?? _defaultPorts;

  final String _liteagentBaseUrl;
  final String _openToolDaemonHost;
  final Map<String, int> _servicePorts;

  /// Default liteagentbaseurl
  static const String _defaultLiteagentBaseUrl = 'http://127.0.0.1:9527/api/v1';

  /// Default service port configuration
  static const Map<String, int> _defaultPorts = {
    'liteagent': 9527,
    'opentool': 19627,
    'embeddings': 9537,
    'llm_chat': 52010,
    'llm_embedding': 52030,
    'llm_tts': 52040,
    'llm_asr': 52050,
    'llm_decision': 52060,
  };

  @override
  String get liteagentBaseUrl => _liteagentBaseUrl;

  String get openToolDaemonHost => _openToolDaemonHost;

  @override
  Future<int?> getServicePort(String serviceKey, {String? modelId}) async {
    return _servicePorts[serviceKey];
  }

  @override
  Future<List<AppInfo>> getAppInfoList() async {
    return const [];
  }

  @override
  Future<List<LlmModelInfo>> getLlmModelList() async {
    return const [];
  }

  @override
  Stream<ServiceStatusEvent> get serviceStatusStream => const Stream.empty();

  static String _normalizeHost(String? host) {
    final normalized = (host ?? '').trim();
    return normalized.isEmpty ? '127.0.0.1' : normalized;
  }
}
