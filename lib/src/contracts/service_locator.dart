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

  /// Checks if the specified service is healthy
  ///
  /// [serviceKey] Service identifier
  Future<bool> isServiceHealthy(String serviceKey);

  /// Gets information about all running services
  Future<List<ServiceInfo>> getRunningServices();

  /// Resolves LLM service port
  ///
  /// LLM services may have multiple instances (different models), routes to corresponding instance based on model field in request body
  /// [serviceKey] Service identifier (e.g., 'llm_text', 'llm_vision', etc.)
  /// [requestBody] Request body bytes (used to parse model field)
  ///
  /// Returns target port, or null if service is unavailable
  Future<int?> resolveLLMPort(String serviceKey, List<int>? requestBody);

  /// Gets aggregated health status
  ///
  /// Returns health check results for all services
  Future<HealthStatus> getHealthStatus();

  /// Gets service discovery information
  ///
  /// Returns complete service list including port ranges, instance info, etc.
  Future<ServicesDiscovery> getServicesDiscovery();

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

/// Health status
class HealthStatus {
  /// Overall status: healthy, degraded, unhealthy
  final String status;

  /// Timestamp
  final DateTime timestamp;

  /// Health status for each service
  final Map<String, ServiceHealthInfo> services;

  const HealthStatus({
    required this.status,
    required this.timestamp,
    required this.services,
  });

  Map<String, dynamic> toJson() => {
        'status': status,
        'timestamp': timestamp.toIso8601String(),
        'services': services.map((k, v) => MapEntry(k, v.toJson())),
      };
}

/// Health information for a single service
class ServiceHealthInfo {
  final String name;
  final bool healthy;
  final int? port;
  final List<ServiceInstanceInfo>? instances;

  const ServiceHealthInfo({
    required this.name,
    required this.healthy,
    this.port,
    this.instances,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'healthy': healthy,
        if (port != null) 'port': port,
        if (instances != null)
          'instances': instances!.map((i) => i.toJson()).toList(),
      };
}

/// Service instance information
class ServiceInstanceInfo {
  final String? modelId;
  final String? modelAlias;
  final int port;

  const ServiceInstanceInfo({
    this.modelId,
    this.modelAlias,
    required this.port,
  });

  Map<String, dynamic> toJson() => {
        if (modelId != null) 'modelId': modelId,
        if (modelAlias != null) 'modelAlias': modelAlias,
        'port': port,
      };
}

/// Service discovery information
class ServicesDiscovery {
  /// Gateway port
  final int gatewayPort;

  /// Base URL
  final String baseUrl;

  /// Service list
  final List<ServiceDiscoveryInfo> services;

  const ServicesDiscovery({
    required this.gatewayPort,
    required this.baseUrl,
    required this.services,
  });

  Map<String, dynamic> toJson() => {
        'gatewayPort': gatewayPort,
        'baseUrl': baseUrl,
        'services': services.map((s) => s.toJson()).toList(),
      };
}

/// Discovery information for a single service
class ServiceDiscoveryInfo {
  final String name;
  final String key;
  final String path;
  final int? port;
  final String? portRange;
  final bool isRunning;
  final String? description;
  final List<ServiceInstanceInfo>? instances;

  const ServiceDiscoveryInfo({
    required this.name,
    required this.key,
    required this.path,
    this.port,
    this.portRange,
    required this.isRunning,
    this.description,
    this.instances,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'key': key,
        'path': path,
        if (port != null) 'port': port,
        if (portRange != null) 'portRange': portRange,
        'isRunning': isRunning,
        if (description != null) 'description': description,
        if (instances != null)
          'instances': instances!.map((i) => i.toJson()).toList(),
      };
}

/// Service information
class ServiceInfo {
  /// Service name
  final String name;

  /// Service identifier
  final String key;

  /// Service port
  final int port;

  /// Whether running
  final bool isRunning;

  /// Service description
  final String? description;

  const ServiceInfo({
    required this.name,
    required this.key,
    required this.port,
    required this.isRunning,
    this.description,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'key': key,
        'port': port,
        'isRunning': isRunning,
        if (description != null) 'description': description,
      };
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
