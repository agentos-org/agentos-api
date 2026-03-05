
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

/// LLM model information
class LlmModelInfo {
  final String id;
  final String name;
  final String description;
  final String parameters;
  final num paramsB;
  final String quantization;
  final num sizeGB;
  final num minRAMGB;
  final String downloadUrl;
  final List<String> tags;
  final String repoId;
  final String type;
  final int? contextWindowSize;

  /// Remote model's own base URL. Null means using the local service URL.
  final String? baseUrl;

  /// Remote model's own API key. Null means using the default key.
  final String? apiKey;

  /// Whether this model is a user-defined custom remote model.
  final bool isCustom;

  const LlmModelInfo({
    required this.id,
    required this.name,
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
  });

  /// Whether this model is a remote model with its own endpoint.
  bool get isRemote => baseUrl != null && baseUrl!.isNotEmpty;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
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

  /// Gets the port number for the specified service
  ///
  /// [serviceKey] Service identifier, supported values:
  /// - 'liteagent': LiteAgent agent service
  /// - 'opentool': OpenTool tool service
  /// - 'embeddings': Embeddings server
  /// - 'llm_text': Text generation service
  /// - 'llm_vision': Image-text understanding service
  /// - 'llm_embedding': LLM embedding model service
  /// - 'llm_tts': Text-to-speech service
  /// - 'llm_asr': Speech-to-text service
  ///
  /// Returns null if service is not running or unavailable
  Future<int?> getServicePort(String serviceKey);

  /// Resolves LLM service port
  ///
  /// LLM services may have multiple instances (different models), routes to corresponding instance based on model identifier
  /// [serviceKey] Service identifier (e.g., 'llm_text', 'llm_vision', etc.)
  /// [modelId] Model identifier (model id or name, used to locate the specific running instance)
  ///
  /// Returns target port, or null if service is unavailable
  Future<int?> resolveLLMPort(String serviceKey, String? modelId);

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

/// Default Service Locator Implementation
///
/// Static configuration based on defaults, suitable for:
/// - Standalone agentos-api server deployment
/// - Development and testing environments
/// - Simple single-machine deployment scenarios
class DefaultServiceLocator implements AgentOSServiceLocator {
  DefaultServiceLocator({
    String? liteagentBaseUrl,
    Map<String, int>? servicePorts,
  })  : _liteagentBaseUrl = liteagentBaseUrl ?? _defaultLiteagentBaseUrl,
        _servicePorts = servicePorts ?? _defaultPorts;

  final String _liteagentBaseUrl;
  final Map<String, int> _servicePorts;


  /// Default liteagentbaseurl
  static const String _defaultLiteagentBaseUrl = 'http://127.0.0.1:9527/api/v1';

  /// Default service port configuration
  static const Map<String, int> _defaultPorts = {
    'liteagent': 9527,
    'opentool': 19627,
    'embeddings': 9537,
    'llm_text': 52010,
    'llm_vision': 52020,
    'llm_embedding': 52030,
    'llm_tts': 52040,
    'llm_asr': 52050,
  };

  @override
  String get liteagentBaseUrl => _liteagentBaseUrl;

  @override
  Future<int?> getServicePort(String serviceKey) async {
    return _servicePorts[serviceKey];
  }

  @override
  Future<int?> resolveLLMPort(
    String serviceKey,
    String? modelId,
  ) async {
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
}
