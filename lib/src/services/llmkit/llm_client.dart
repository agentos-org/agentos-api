import 'dart:async';
import 'dart:io';

import 'package:agentos_kernel/agentos_kernel.dart';

import '../../config.dart';
import '../../locator.dart';
import '../modelkit/model_client.dart';

/// LLM client response.
///
/// Deprecated. Kept as a thin alias of [ModelClientResponse] so existing
/// callers compile against the new ModelKit pipeline.
@Deprecated('Use ModelClientResponse from services/modelkit/model_client.dart')
class LLMClientResponse {
  LLMClientResponse({
    required this.statusCode,
    required this.headers,
    this.bodyBytes,
    this.bodyStream,
  });

  factory LLMClientResponse.fromModel(ModelClientResponse response) {
    return LLMClientResponse(
      statusCode: response.statusCode,
      headers: response.headers,
      bodyBytes: response.bodyBytes,
      bodyStream: response.bodyStream,
    );
  }

  final int statusCode;
  final Map<String, String> headers;
  final List<int>? bodyBytes;
  final Stream<List<int>>? bodyStream;
}

/// IO-oriented LLM service classification.
///
/// Deprecated. Prefer [ModelTask] which classifies models by task (chat,
/// embedding, asr, tts) rather than IO shape. [LLMServiceType.text] and
/// [LLMServiceType.vision] both map to [ModelTask.chat]; the vision variant
/// is now identified by `capabilities.vision` on the resolved model.
@Deprecated('Use ModelTask instead')
enum LLMServiceType { text, vision, embedding, tts, asr }

/// Extensions for the deprecated [LLMServiceType] enum.
// ignore: deprecated_member_use_from_same_package
extension LLMServiceTypeExtension on LLMServiceType {
  /// Service identifier used with [AgentOSServiceLocator].
  String get serviceKey {
    switch (this) {
      // ignore: deprecated_member_use_from_same_package
      case LLMServiceType.text:
        // ignore: deprecated_member_use_from_same_package
        return ApiConfig.serviceLlmText;
      // ignore: deprecated_member_use_from_same_package
      case LLMServiceType.vision:
        // ignore: deprecated_member_use_from_same_package
        return ApiConfig.serviceLlmVision;
      // ignore: deprecated_member_use_from_same_package
      case LLMServiceType.embedding:
        return ApiConfig.serviceLlmEmbedding;
      // ignore: deprecated_member_use_from_same_package
      case LLMServiceType.tts:
        return ApiConfig.serviceLlmTts;
      // ignore: deprecated_member_use_from_same_package
      case LLMServiceType.asr:
        return ApiConfig.serviceLlmAsr;
    }
  }

  String get displayName {
    switch (this) {
      // ignore: deprecated_member_use_from_same_package
      case LLMServiceType.text:
        return 'Text Generation';
      // ignore: deprecated_member_use_from_same_package
      case LLMServiceType.vision:
        return 'Image-Text-to-Text';
      // ignore: deprecated_member_use_from_same_package
      case LLMServiceType.embedding:
        return 'Text Embedding';
      // ignore: deprecated_member_use_from_same_package
      case LLMServiceType.tts:
        return 'Text-to-Speech';
      // ignore: deprecated_member_use_from_same_package
      case LLMServiceType.asr:
        return 'Speech-to-Text';
    }
  }

  /// Equivalent [ModelTask] for this legacy service type.
  ModelTask get task {
    switch (this) {
      // ignore: deprecated_member_use_from_same_package
      case LLMServiceType.text:
      // ignore: deprecated_member_use_from_same_package
      case LLMServiceType.vision:
        return ModelTask.chat;
      // ignore: deprecated_member_use_from_same_package
      case LLMServiceType.embedding:
        return ModelTask.embedding;
      // ignore: deprecated_member_use_from_same_package
      case LLMServiceType.tts:
        return ModelTask.tts;
      // ignore: deprecated_member_use_from_same_package
      case LLMServiceType.asr:
        return ModelTask.asr;
    }
  }
}

/// Legacy LLM client.
///
/// Deprecated. New code must use [ModelClient]. This class is preserved as a
/// thin adapter that converts legacy [LLMServiceType] calls into the new
/// task-oriented [ModelClient.send] requests so that existing integrations
/// keep functioning during the migration window.
@Deprecated('Use ModelClient instead')
class LLMClient {
  /// Creates an [LLMClient] backed by a fresh [ModelClient].
  LLMClient({
    HttpClient? httpClient,
    AgentOSServiceLocator? serviceLocator,
    required Future<KernelService?> kernelFuture,
  }) : _delegate = ModelClient(
         httpClient: httpClient,
         serviceLocator: serviceLocator,
         kernelFuture: kernelFuture,
       );

  /// Creates an [LLMClient] that delegates to an existing [ModelClient].
  LLMClient.fromDelegate(ModelClient delegate) : _delegate = delegate;

  final ModelClient _delegate;

  /// Service locator used by the underlying [ModelClient].
  AgentOSServiceLocator get serviceLocator => _delegate.serviceLocator;

  /// Underlying task-oriented client.
  ModelClient get delegate => _delegate;

  /// Forwards a request through the new ModelKit pipeline.
  // ignore: deprecated_member_use_from_same_package
  Future<LLMClientResponse> send({
    // ignore: deprecated_member_use_from_same_package
    required LLMServiceType serviceType,
    required String method,
    required String path,
    Map<String, String>? headers,
    Map<String, String>? queryParameters,
    List<int>? body,
    bool streamResponse = false,
  }) async {
    final response = await _delegate.send(
      task: serviceType.task,
      method: method,
      path: path,
      headers: headers,
      queryParameters: queryParameters,
      body: body,
      streamResponse: streamResponse,
    );
    // ignore: deprecated_member_use_from_same_package
    return LLMClientResponse.fromModel(response);
  }
}
