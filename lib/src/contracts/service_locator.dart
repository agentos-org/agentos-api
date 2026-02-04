/// AgentOS Service Locator Abstract Interface
///
/// Defines a generic interface for service discovery, allowing different implementations:
/// - Default implementation: Static configuration based on environment variables
/// - Desktop implementation: Gets dynamic info from agentos_desktop service manager
/// - Test implementation: Mock data for unit tests
abstract class AgentOSServiceLocator {
  /// Gets the LiteAgent service base URL
  ///
  /// Default: http://127.0.0.1:9527/api/v1
  String get liteagentBaseUrl;

  /// Gets the port number for the specified service
  ///
  /// [serviceKey] Service identifier, supported values:
  /// - 'liteagent': LiteAgent agent service
  /// - 'opentool': OpenTool tool service
  /// - 'llm_text': Text generation service
  /// - 'llm_vision': Image-text understanding service
  /// - 'llm_embedding': Text embedding service
  /// - 'llm_tts': Text-to-speech service
  /// - 'llm_asr': Speech-to-text service
  ///
  /// Returns null if service is not running or unavailable
  Future<int?> getServicePort(String serviceKey);

  /// Resolves LLM service port
  ///
  /// LLM services may have multiple instances (different models), routes to corresponding instance based on model field in request body
  /// [serviceKey] Service identifier (e.g., 'llm_text', 'llm_vision', etc.)
  /// [requestBody] Request body bytes (used to parse model field)
  ///
  /// Returns target port, or null if service is unavailable
  Future<int?> resolveLLMPort(String serviceKey, List<int>? requestBody);

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
  });

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
      };
}
