import 'dart:io';

import 'service_locator.dart';
import '../gateway/gateway_config.dart';

/// Default Service Locator Implementation
///
/// Static configuration based on environment variables, suitable for:
/// - Standalone agentos-api server deployment
/// - Development and testing environments
/// - Simple single-machine deployment scenarios
class DefaultServiceLocator implements AgentOSServiceLocator {
  DefaultServiceLocator({
    String? liteagentBaseUrl,
    Map<String, int>? servicePorts,
    int? gatewayPort,
  })  : _liteagentBaseUrl = liteagentBaseUrl ?? _resolveFromEnv(),
        _servicePorts = servicePorts ?? _defaultPorts,
        _gatewayPort = gatewayPort ?? GatewayConfig.defaultPort;

  final String _liteagentBaseUrl;
  final Map<String, int> _servicePorts;
  final int _gatewayPort;

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

  /// Resolves LiteAgent base URL from environment variables
  static String _resolveFromEnv() {
    return Platform.environment['LITEAGENT_BASEURL'] ??
        'http://127.0.0.1:9527/api/v1';
  }

  @override
  String get liteagentBaseUrl => _liteagentBaseUrl;

  @override
  Future<int?> getServicePort(String serviceKey) async {
    return _servicePorts[serviceKey];
  }

  @override
  Future<bool> isServiceHealthy(String serviceKey) async {
    // Default implementation skips health check, assumes service is available
    // Actual health check is done by specific implementation classes
    return _servicePorts.containsKey(serviceKey);
  }

  @override
  Future<List<ServiceInfo>> getRunningServices() async {
    // Default implementation returns all configured services (assuming all are running)
    return _servicePorts.entries.map((e) {
      return ServiceInfo(
        name: _serviceNames[e.key] ?? e.key,
        key: e.key,
        port: e.value,
        isRunning: true,
        description: _serviceDescriptions[e.key],
      );
    }).toList();
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
  Future<HealthStatus> getHealthStatus() async {
    // Default implementation returns all services as healthy
    final services = <String, ServiceHealthInfo>{};

    for (final entry in _servicePorts.entries) {
      services[entry.key] = ServiceHealthInfo(
        name: _serviceNames[entry.key] ?? entry.key,
        healthy: true,
        port: entry.value,
      );
    }

    return HealthStatus(
      status: 'healthy',
      timestamp: DateTime.now(),
      services: services,
    );
  }

  @override
  Future<ServicesDiscovery> getServicesDiscovery() async {
    final services = <ServiceDiscoveryInfo>[];

    for (final entry in _servicePorts.entries) {
      final kitPath = GatewayConfig.getKitPath(entry.key);
      services.add(ServiceDiscoveryInfo(
        name: _serviceNames[entry.key] ?? entry.key,
        key: entry.key,
        path: kitPath ?? '/${entry.key}',
        port: entry.value,
        isRunning: true,
        description: _serviceDescriptions[entry.key],
      ));
    }

    return ServicesDiscovery(
      gatewayPort: _gatewayPort,
      baseUrl: GatewayConfig.getBaseUrl(_gatewayPort),
      services: services,
    );
  }

  @override
  Future<List<AppInfo>> getAppInfoList() async {
    return const [];
  }

  @override
  Future<List<LlmModelInfo>> getLlmModelList() async {
    return const [];
  }

  /// Service name mapping
  static const Map<String, String> _serviceNames = {
    'liteagent': 'LiteAgent Server',
    'opentool': 'OpenTool Daemon',
    'llm_text': 'Text Generation',
    'llm_vision': 'Image-Text-to-Text',
    'llm_embedding': 'Embedding',
    'llm_tts': 'Text-to-Speech',
    'llm_asr': 'Audio-Text-to-Text',
  };

  /// Service description mapping
  static const Map<String, String> _serviceDescriptions = {
    'liteagent': 'LiteAgent agent service',
    'opentool': 'OpenTool tool service',
    'llm_text': 'Text generation service',
    'llm_vision': 'Image-text understanding service',
    'llm_embedding': 'Text embedding service',
    'llm_tts': 'Text-to-speech service',
    'llm_asr': 'Speech-to-text service',
  };
}
