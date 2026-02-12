/// AgentOS API Configuration
///
/// Centralized management of API constants and configurations

/// API configuration constants
class ApiConfig {
  ApiConfig._();

  /// Default port
  static const int defaultPort = 20261;

  /// Hostname (externally exposed)
  static const String host = 'localhost';

  /// Internal service host (for proxy forwarding target)
  static const String internalHost = '127.0.0.1';

  // ============ Kit Path Prefixes ============

  /// AgentKit API path (proxy to LiteAgent)
  static const String agentkitPath = '/agentkit';

  /// AppKit API path (app registration/subscription)
  static const String appkitPath = '/appkit';

  /// ToolKit API path (proxy to OpenTool)
  static const String toolkitPath = '/toolkit';

  /// LLMKit API path (proxy to LLM services)
  static const String llmkitPath = '/llmkit';

  /// IntentKit API path (intent detection)
  static const String intentkitPath = '/intentkit';

  // ============ LLMKit Sub-paths ============

  /// LLM text generation path
  static const String llmTextPath = '$llmkitPath/text';

  /// LLM image-text understanding path
  static const String llmVisionPath = '$llmkitPath/vision';

  /// LLM text embedding path
  static const String llmEmbeddingPath = '$llmkitPath/embedding';

  /// LLM text-to-speech path
  static const String llmTtsPath = '$llmkitPath/tts';

  /// LLM speech-to-text path
  static const String llmAsrPath = '$llmkitPath/asr';

  // ============ Service Identifiers ============

  /// Service identifier constants
  static const String serviceLiteagent = 'liteagent';
  static const String serviceOpentool = 'opentool';
  static const String serviceLlmText = 'llm_text';
  static const String serviceLlmVision = 'llm_vision';
  static const String serviceLlmEmbedding = 'llm_embedding';
  static const String serviceLlmTts = 'llm_tts';
  static const String serviceLlmAsr = 'llm_asr';

  // ============ Default Ports ============

  /// LiteAgent default port
  static const int defaultLiteagentPort = 9527;

  /// OpenTool default port
  static const int defaultOpentoolPort = 19627;

  /// LLM text service default port
  static const int defaultLlmTextPort = 52010;

  /// LLM embedding service default port
  static const int defaultLlmEmbeddingPort = 52030;

  // ============ Utility Methods ============

  /// Gets the base URL
  static String getBaseUrl([int? port]) =>
      'http://$host:${port ?? defaultPort}';

  /// Gets internal service address (for proxy forwarding)
  static String getInternalUrl(int port) => 'http://$internalHost:$port';

  /// Gets Kit path by service identifier
  static String? getKitPath(String serviceKey) {
    switch (serviceKey) {
      case serviceLiteagent:
        return agentkitPath;
      case serviceOpentool:
        return toolkitPath;
      case serviceLlmText:
        return llmTextPath;
      case serviceLlmVision:
        return llmVisionPath;
      case serviceLlmEmbedding:
        return llmEmbeddingPath;
      case serviceLlmTts:
        return llmTtsPath;
      case serviceLlmAsr:
        return llmAsrPath;
      default:
        return null;
    }
  }

  // ============ Service Display Names (English) ============

  static const String liteagentName = 'LiteAgent';
  static const String opentoolName = 'OpenTool';
  static const String llmTextName = 'Text Generation';
  static const String llmVisionName = 'Image-Text-to-Text';
  static const String llmEmbeddingName = 'Text Embedding';
  static const String llmTtsName = 'Text-to-Speech';
  static const String llmAsrName = 'Speech-to-Text';

  // ============ Service Display Names (Chinese) ============

  static const String liteagentNameZh = 'LiteAgent';
  static const String opentoolNameZh = 'OpenTool';
  static const String llmTextNameZh = '文本生成';
  static const String llmVisionNameZh = '图文理解';
  static const String llmEmbeddingNameZh = '文本嵌入';
  static const String llmTtsNameZh = '文本转语音';
  static const String llmAsrNameZh = '语音转文本';

  static String getDisplayName(String serviceKey) {
    switch (serviceKey) {
      case serviceLiteagent:
        return liteagentName;
      case serviceOpentool:
        return opentoolName;
      case serviceLlmText:
        return llmTextName;
      case serviceLlmVision:
        return llmVisionName;
      case serviceLlmEmbedding:
        return llmEmbeddingName;
      case serviceLlmTts:
        return llmTtsName;
      case serviceLlmAsr:
        return llmAsrName;
      default:
        return serviceKey;
    }
  }

  static String getDisplayNameZh(String serviceKey) {
    switch (serviceKey) {
      case serviceLiteagent:
        return liteagentNameZh;
      case serviceOpentool:
        return opentoolNameZh;
      case serviceLlmText:
        return llmTextNameZh;
      case serviceLlmVision:
        return llmVisionNameZh;
      case serviceLlmEmbedding:
        return llmEmbeddingNameZh;
      case serviceLlmTts:
        return llmTtsNameZh;
      case serviceLlmAsr:
        return llmAsrNameZh;
      default:
        return serviceKey;
    }
  }
}