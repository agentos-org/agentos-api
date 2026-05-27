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

  /// ToolKit API path (proxy to OpenTool)
  static const String toolkitPath = '/toolkit';

  /// ModelKit API path — unified entry point for all model task services.
  ///
  /// Groups chat (text + vision), embedding, ASR and TTS behind a single
  /// task-oriented namespace. Replaces the legacy IO-oriented [llmkitPath].
  static const String modelkitPath = '/modelkit';

  /// LLMKit API path
  ///
  /// Deprecated. Backward-compatible alias of [modelkitPath]; new code should
  /// route through `/modelkit`. The legacy `/llmkit` mount is preserved by the
  /// gateway but internally delegates to the same ModelKit pipeline.
  @Deprecated('Use modelkitPath instead')
  static const String llmkitPath = '/llmkit';

  /// CronKit API path (cron task management)
  static const String cronkitPath = '/cronkit';

  /// RagKit API path (RAG knowledge management and query)
  static const String ragkitPath = '/ragkit';

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

  // ============ LLMKit Sub-paths (DEPRECATED) ============

  /// LLM chat path under the legacy `/llmkit` mount.
  ///
  /// Deprecated. Prefer [modelChatPath] (`/modelkit/chat`) for new code; this
  /// path keeps working through the compatibility mount.
  @Deprecated('Use modelChatPath instead')
  // ignore: deprecated_member_use_from_same_package
  static const String llmChatPath = '$llmkitPath/chat';

  /// LLM text generation path
  ///
  /// Deprecated alias kept for backward compatibility. New code should use
  /// [modelChatPath].
  @Deprecated('Use modelChatPath instead')
  // ignore: deprecated_member_use_from_same_package
  static const String llmTextPath = '$llmkitPath/text';

  /// LLM image-text understanding path
  ///
  /// Deprecated. VLM traffic is now routed through [modelChatPath] and the
  /// model's `capabilities.vision` flag identifies vision-capable models.
  @Deprecated('Use modelChatPath instead; VLM is identified by capabilities.vision')
  // ignore: deprecated_member_use_from_same_package
  static const String llmVisionPath = '$llmkitPath/vision';

  /// LLM text embedding path
  @Deprecated('Use modelEmbeddingPath instead')
  // ignore: deprecated_member_use_from_same_package
  static const String llmEmbeddingPath = '$llmkitPath/embedding';

  /// LLM text-to-speech path
  @Deprecated('Use modelTtsPath instead')
  // ignore: deprecated_member_use_from_same_package
  static const String llmTtsPath = '$llmkitPath/tts';

  /// LLM speech-to-text path
  @Deprecated('Use modelAsrPath instead')
  // ignore: deprecated_member_use_from_same_package
  static const String llmAsrPath = '$llmkitPath/asr';

  // ============ Service Identifiers ============

  /// Service identifier constants
  static const String serviceLiteagent = 'liteagent';
  static const String serviceOpentool = 'opentool';
  static const String serviceEmbeddings = 'embeddings';

  /// Unified chat service identifier (text + vision).
  static const String serviceLlmChat = 'llm_chat';

  /// Deprecated text-only service id. Kept for compatibility with older
  /// callers; new code should emit [serviceLlmChat].
  @Deprecated('Use serviceLlmChat instead')
  static const String serviceLlmText = 'llm_text';

  /// Deprecated vision service id. Vision is now a capability of chat models.
  @Deprecated('Use serviceLlmChat instead; vision is a capability flag')
  static const String serviceLlmVision = 'llm_vision';

  static const String serviceLlmEmbedding = 'llm_embedding';
  static const String serviceLlmTts = 'llm_tts';
  static const String serviceLlmAsr = 'llm_asr';

  // ============ Default Ports ============

  /// LiteAgent default port
  static const int defaultLiteagentPort = 9527;

  /// OpenTool default port
  static const int defaultOpentoolPort = 19627;

  /// Internal OpenTool tool-service path prefix hidden behind ToolKit.
  static const String defaultOpentoolPrefix = '/opentool-daemon/tools';

  /// Embeddings server default port
  static const int defaultEmbeddingsPort = 9537;

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

  /// Gets internal OpenTool service address (for ToolKit forwarding)
  static String getInternalOpenToolUrl(int port) =>
      '${getInternalUrl(port)}$defaultOpentoolPrefix';

  /// Gets Kit path by service identifier.
  ///
  /// Returns the canonical ModelKit path for new service keys, and the legacy
  /// LLMKit path for deprecated keys (still routable via the compatibility
  /// mount).
  static String? getKitPath(String serviceKey) {
    switch (serviceKey) {
      case serviceLiteagent:
        return agentkitPath;
      case serviceOpentool:
        return toolkitPath;
      case serviceLlmChat:
        return modelChatPath;
      // ignore: deprecated_member_use_from_same_package
      case serviceLlmText:
        // ignore: deprecated_member_use_from_same_package
        return llmTextPath;
      // ignore: deprecated_member_use_from_same_package
      case serviceLlmVision:
        // ignore: deprecated_member_use_from_same_package
        return llmVisionPath;
      case serviceLlmEmbedding:
        return modelEmbeddingPath;
      case serviceLlmTts:
        return modelTtsPath;
      case serviceLlmAsr:
        return modelAsrPath;
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

  @Deprecated('Use llmChatName instead')
  static const String llmTextName = 'Text Generation';

  @Deprecated('Use llmChatName instead')
  static const String llmVisionName = 'Image-Text-to-Text';

  static const String llmEmbeddingName = 'Text Embedding';
  static const String llmTtsName = 'Text-to-Speech';
  static const String llmAsrName = 'Speech-to-Text';

  // ============ Service Display Names (Chinese) ============

  static const String liteagentNameZh = 'LiteAgent';
  static const String opentoolNameZh = 'OpenTool';
  static const String embeddingsNameZh = 'Embeddings';

  /// Unified chat Chinese display name.
  static const String llmChatNameZh = '对话';

  @Deprecated('Use llmChatNameZh instead')
  static const String llmTextNameZh = '文本生成';

  @Deprecated('Use llmChatNameZh instead')
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
      case serviceEmbeddings:
        return embeddingsName;
      case serviceLlmChat:
        return llmChatName;
      // ignore: deprecated_member_use_from_same_package
      case serviceLlmText:
        // ignore: deprecated_member_use_from_same_package
        return llmTextName;
      // ignore: deprecated_member_use_from_same_package
      case serviceLlmVision:
        // ignore: deprecated_member_use_from_same_package
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
      case serviceEmbeddings:
        return embeddingsNameZh;
      case serviceLlmChat:
        return llmChatNameZh;
      // ignore: deprecated_member_use_from_same_package
      case serviceLlmText:
        // ignore: deprecated_member_use_from_same_package
        return llmTextNameZh;
      // ignore: deprecated_member_use_from_same_package
      case serviceLlmVision:
        // ignore: deprecated_member_use_from_same_package
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
