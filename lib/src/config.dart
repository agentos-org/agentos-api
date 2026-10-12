/// AgentOS API Configuration
///
/// Centralized management of API constants and configurations

/// API configuration constants
class ApiConfig {
  ApiConfig._();

  /// Default port
  static const int defaultPort = 8888;

  /// Hostname (externally exposed)
  static const String host = 'localhost';

  /// Internal service host (for proxy forwarding target)
  static const String internalHost = '127.0.0.1';

  // ============ Kit Path Prefixes ============

  /// AgentKit API path (proxy to LiteAgent)
  static const String agentkitPath = '/agentkit';

  /// AppKit API path (app registration/subscription)
  static const String appkitPath = '/appkit';

  /// NotifyKit API path (App notification publishing).
  static const String notifykitPath = '/notifykit';

  /// ToolKit API path (proxy to OpenTool)
  static const String toolkitPath = '/toolkit';

  /// ModelKit API path — unified entry point for all model task services.
  ///
  /// Groups chat (text + vision), embedding, ASR, TTS and decision behind a
  /// single task-oriented namespace.
  static const String modelkitPath = '/modelkit';

  /// CronKit API path (cron task management)
  static const String cronkitPath = '/cronkit';

  /// RagKit API path (RAG knowledge management and query)
  static const String ragkitPath = '/ragkit';

  /// AuthKit API path (launchUri delivery to Desktop; login session is internal).
  static const String authkitPath = '/authkit';

  /// DiscoveryKit API path (nearby device discovery)
  static const String discoverykitPath = '/discoverykit';

  /// TransferKit API path (file transfer between devices)
  static const String transferkitPath = '/transferkit';

  /// HarnessKit API path (internal Harness WebApp bridge).
  ///
  /// This route is intentionally a server-side integration point rather than
  /// part of the public SDK surface. The built-in Harness WebApp reaches it
  /// with the AppKit token issued during its AgentOS connection.
  static const String harnesskitPath = '/harnesskit';

  // ============ ModelKit Sub-paths ============

  /// Chat task path — unified entry for text and vision chat completions.
  ///
  /// VLM models live behind this same path; vision capability is signaled
  /// via the model's `capabilities.vision` flag rather than a separate route.
  static const String modelChatPath = '$modelkitPath/chat';

  /// Embedding task path.
  static const String modelEmbeddingPath = '$modelkitPath/embedding';

  /// Automatic speech recognition (ASR / speech-to-text) task path.
  static const String modelAsrPath = '$modelkitPath/asr';

  /// Text-to-speech (TTS) task path.
  static const String modelTtsPath = '$modelkitPath/tts';

  /// Decision task path — typed-question decision models (llama.cpp
  /// `/v1/systemone`). Hitting the task root forwards to `/v1/systemone`.
  static const String modelDecisionPath = '$modelkitPath/decision';

  // ============ Service Identifiers ============

  /// Service identifier constants
  static const String serviceLiteagent = 'liteagent';
  static const String serviceOpentool = 'opentool';
  static const String serviceEmbeddings = 'embeddings';

  /// Unified chat service identifier (text + vision).
  static const String serviceLlmChat = 'llm_chat';

  static const String serviceLlmEmbedding = 'llm_embedding';
  static const String serviceLlmTts = 'llm_tts';
  static const String serviceLlmAsr = 'llm_asr';

  /// Decision-model service identifier (llama.cpp `/v1/systemone`).
  static const String serviceLlmDecision = 'llm_decision';

  // ============ Default Ports ============

  /// LiteAgent default port
  static const int defaultLiteagentPort = 9527;

  /// OpenTool default port
  static const int defaultOpentoolPort = 19627;

  /// Internal OpenTool tool-service path prefix hidden behind ToolKit.
  static const String defaultOpentoolPrefix = '/opentool-daemon/tools';

  /// Embeddings server default port
  static const int defaultEmbeddingsPort = 9537;

  /// Harness sidecar default port.
  static const int defaultHarnessPort = 9538;

  /// LLM chat service default port
  static const int defaultLlmChatPort = 52010;

  /// LLM embedding service default port
  static const int defaultLlmEmbeddingPort = 52030;

  // ============ Utility Methods ============

  /// Gets the base URL
  static String getBaseUrl([int? port]) =>
      'http://$host:${port ?? defaultPort}';

  /// Gets internal service address (for proxy forwarding)
  static String getInternalUrl(int port) => 'http://$internalHost:$port';

  /// Gets internal OpenTool service address (for ToolKit forwarding)
  static String getInternalOpenToolUrl(int port) =>
      '${getInternalUrl(port)}$defaultOpentoolPrefix';

  /// Gets Kit path by service identifier.
  static String? getKitPath(String serviceKey) {
    switch (serviceKey) {
      case serviceLiteagent:
        return agentkitPath;
      case serviceOpentool:
        return toolkitPath;
      case serviceLlmChat:
        return modelChatPath;
      case serviceLlmEmbedding:
        return modelEmbeddingPath;
      case serviceLlmTts:
        return modelTtsPath;
      case serviceLlmAsr:
        return modelAsrPath;
      case serviceLlmDecision:
        return modelDecisionPath;
      default:
        return null;
    }
  }

  // ============ Service Display Names (English) ============

  static const String liteagentName = 'LiteAgent';
  static const String opentoolName = 'OpenTool';
  static const String embeddingsName = 'Embeddings';

  /// Unified chat display name (text + vision).
  static const String llmChatName = 'Chat';

  static const String llmEmbeddingName = 'Text Embedding';
  static const String llmTtsName = 'Text-to-Speech';
  static const String llmAsrName = 'Speech-to-Text';
  static const String llmDecisionName = 'Decision';

  // ============ Service Display Names (Chinese) ============

  static const String liteagentNameZh = 'LiteAgent';
  static const String opentoolNameZh = 'OpenTool';
  static const String embeddingsNameZh = 'Embeddings';

  /// Unified chat Chinese display name.
  static const String llmChatNameZh = '对话';

  static const String llmEmbeddingNameZh = '文本嵌入';
  static const String llmTtsNameZh = '文本转语音';
  static const String llmAsrNameZh = '语音转文本';
  static const String llmDecisionNameZh = '决策';

  static String getDisplayName(String serviceKey) {
    switch (serviceKey) {
      case serviceLiteagent:
        return liteagentName;
      case serviceOpentool:
        return opentoolName;
      case serviceEmbeddings:
        return embeddingsName;
      case serviceLlmChat:
        return llmChatName;
      case serviceLlmEmbedding:
        return llmEmbeddingName;
      case serviceLlmTts:
        return llmTtsName;
      case serviceLlmAsr:
        return llmAsrName;
      case serviceLlmDecision:
        return llmDecisionName;
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
      case serviceEmbeddings:
        return embeddingsNameZh;
      case serviceLlmChat:
        return llmChatNameZh;
      case serviceLlmEmbedding:
        return llmEmbeddingNameZh;
      case serviceLlmTts:
        return llmTtsNameZh;
      case serviceLlmAsr:
        return llmAsrNameZh;
      case serviceLlmDecision:
        return llmDecisionNameZh;
      default:
        return serviceKey;
    }
  }
}
