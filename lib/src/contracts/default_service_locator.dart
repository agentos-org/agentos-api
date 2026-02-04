import 'service_locator.dart';

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
  })  : _liteagentBaseUrl = liteagentBaseUrl ?? _resolveFromEnv(),
        _servicePorts = servicePorts ?? _defaultPorts;

  final String _liteagentBaseUrl;
  final Map<String, int> _servicePorts;

  /// Default service port configuration
  static const Map<String, int> _defaultPorts = {
    'liteagent': 9527,
    'opentool': 19627,
    'llm_text': 52010,
    'llm_vision': 52020,
    'llm_embedding': 52030,
    'llm_tts': 52040,
    'llm_asr': 52050,
  };

  /// Resolves LiteAgent base URL from defaults
  static String _resolveFromEnv() {
    return 'http://127.0.0.1:9527/api/v1';
  }

  @override
  String get liteagentBaseUrl => _liteagentBaseUrl;

  @override
  Future<int?> getServicePort(String serviceKey) async {
    return _servicePorts[serviceKey];
  }

  @override
  Future<int?> resolveLLMPort(
    String serviceKey,
    List<int>? requestBody,
  ) async {
    // Default implementation returns configured port directly
    // Desktop implementation routes dynamically to corresponding LLM instance based on model field
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
