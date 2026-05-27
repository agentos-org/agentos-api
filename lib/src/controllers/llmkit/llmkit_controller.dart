import 'dart:convert';

import 'package:agentos_kernel/agentos_kernel.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../../config.dart';
import '../../locator.dart';
import '../../services/llmkit/llm_client.dart';
import '../../services/modelkit/model_client.dart';

/// LLMKit Controller (deprecated).
///
/// Backward-compatible wrapper that preserves the legacy
/// `/llmkit/{text,vision,embedding,tts,asr}` routes. Internally every route
/// is forwarded through the new [ModelClient] pipeline; `/text` and `/vision`
/// both map to [ModelTask.chat] because vision is now a capability flag on
/// the resolved model rather than a separate service.
///
/// New code must use `ModelKitController` mounted at
/// [ApiConfig.modelkitPath].
@Deprecated('Use ModelKitController mounted at ApiConfig.modelkitPath instead')
class LLMKitController {
  /// Creates an [LLMKitController].
  ///
  /// [kernelFuture] Future that resolves to KernelService for metrics tracking.
  /// [client] Optional legacy [LLMClient]; if provided its underlying
  /// [ModelClient] delegate is reused.
  LLMKitController({
    required Future<KernelService?> kernelFuture,
    // ignore: deprecated_member_use_from_same_package
    LLMClient? client,
    ModelClient? modelClient,
  }) : _client =
           modelClient ??
           client?.delegate ??
           ModelClient(kernelFuture: kernelFuture);

  final ModelClient _client;

  /// Underlying client (exposed for compatibility shims).
  ModelClient get client => _client;

  Router get router {
    final router = Router();

    router.get('/models', _listModels);

    // Legacy IO-oriented routes. `text` and `vision` both fan out to the
    // unified chat task; vision behavior is selected by the resolved model's
    // `capabilities.vision` flag.
    _registerForwardRoutes(router, 'text', ModelTask.chat);
    _registerForwardRoutes(router, 'vision', ModelTask.chat);
    _registerForwardRoutes(router, 'chat', ModelTask.chat);
    _registerForwardRoutes(router, 'embedding', ModelTask.embedding);
    _registerForwardRoutes(router, 'tts', ModelTask.tts);
    _registerForwardRoutes(router, 'asr', ModelTask.asr);

    return router;
  }

  void _registerForwardRoutes(Router router, String prefix, ModelTask task) {
    router.all('/$prefix', _createDefaultForward(task));
    router.all('/$prefix/', _createDefaultForward(task));
    router.all('/$prefix/<path|.*>', _createForward(task));
  }

  Handler _createDefaultForward(ModelTask task) {
    return (Request request) => _proxy(request, task: task, path: '/');
  }

  Handler _createForward(ModelTask task) {
    return (Request request) async {
      final path = request.params['path'] ?? '';
      return _proxy(request, task: task, path: '/$path');
    };
  }

  /// Lists models in the **0.3.7 LLMKit wire schema** for backwards
  /// compatibility with third-party apps. The legacy `type` field is the
  /// IO-oriented identifier (`textGeneration` / `imageTextToText` /
  /// `embedding` / `audioTextToText` / `textToSpeech`); none of the new
  /// task-oriented fields (`task` / `input` / `output` / `capabilities`)
  /// are emitted by this endpoint.
  Future<Response> _listModels(Request request) async {
    try {
      final models = await _client.serviceLocator.getLlmModelList();
      final availableModels = <Map<String, dynamic>>[];

      for (final model in models) {
        if (!await _isModelAvailable(model)) continue;
        availableModels.add(<String, dynamic>{
          'id': model.id,
          'name': model.name,
          'alias': model.alias,
          'description': model.description,
          'type': _legacyTypeFor(model),
          'contextWindowSize': model.contextWindowSize,
          'isRemote': model.isRemote,
          'isCustom': model.isCustom,
        });
      }

      return Response.ok(
        jsonEncode(availableModels),
        headers: const {'content-type': 'application/json'},
      );
    } on Exception catch (error) {
      return Response(502, body: 'LLM models error: $error');
    }
  }

  /// Resolves the 0.3.7-style `type` string for [model].
  ///
  /// Locators that already emit [LlmModelInfo.type] in the legacy schema (the
  /// AgentOS Desktop locator, since 0.4.0) have it copied verbatim. Otherwise
  /// we synthesize one from the task + vision flag for forward compatibility
  /// with third-party locators that only know the new schema.
  static String _legacyTypeFor(LlmModelInfo model) {
    final raw = model.type.trim();
    if (_isLegacyTypeString(raw)) return raw;

    final task = model.task != null
        ? _taskFromName(model.task!)
        : _inferTaskFromModelType(raw);
    if (task == null) return raw.isEmpty ? 'textGeneration' : raw;

    switch (task) {
      case ModelTask.embedding:
        return 'embedding';
      case ModelTask.asr:
        return 'audioTextToText';
      case ModelTask.tts:
        return 'textToSpeech';
      case ModelTask.chat:
        return model.vision ? 'imageTextToText' : 'textGeneration';
    }
  }

  static bool _isLegacyTypeString(String s) {
    switch (s) {
      case 'textGeneration':
      case 'imageTextToText':
      case 'embedding':
      case 'audioTextToText':
      case 'textToSpeech':
        return true;
      default:
        return false;
    }
  }

  static ModelTask? _taskFromName(String name) {
    for (final t in ModelTask.values) {
      if (t.name == name) return t;
    }
    return null;
  }

  Future<bool> _isModelAvailable(LlmModelInfo model) async {
    if (model.isRemote) return true;
    final task = _inferTaskFromModelType(model.type);
    if (task == null) return false;
    final port = await _client.serviceLocator.getServicePort(
      task.serviceKey,
      modelId: model.id,
    );
    if (port != null) return true;
    if (task == ModelTask.chat) {
      for (final legacy in const [
        // ignore: deprecated_member_use_from_same_package
        ApiConfig.serviceLlmText,
        // ignore: deprecated_member_use_from_same_package
        ApiConfig.serviceLlmVision,
      ]) {
        final fallback = await _client.serviceLocator.getServicePort(
          legacy,
          modelId: model.id,
        );
        if (fallback != null) return true;
      }
    }
    return false;
  }

  static ModelTask? _inferTaskFromModelType(String modelType) {
    final normalized = modelType.trim().toLowerCase();
    if (normalized.isEmpty) return null;
    switch (normalized) {
      case 'chat':
        return ModelTask.chat;
      case 'embedding':
        return ModelTask.embedding;
      case 'asr':
      case 'audiotexttotext':
      case 'speechtotext':
        return ModelTask.asr;
      case 'tts':
      case 'texttospeech':
        return ModelTask.tts;
    }
    if (normalized.contains('embedding')) return ModelTask.embedding;
    if (normalized.contains('speech') || normalized.contains('tts')) {
      return ModelTask.tts;
    }
    if (normalized.contains('asr') || normalized.contains('audio')) {
      return ModelTask.asr;
    }
    if (normalized.contains('vision') ||
        normalized.contains('image') ||
        normalized.contains('text')) {
      return ModelTask.chat;
    }
    return null;
  }

  Future<Response> _proxy(
    Request request, {
    required ModelTask task,
    required String path,
  }) async {
    try {
      final bodyBytes = await _readBodyBytes(request);
      final isStream = _detectStreamRequest(request, bodyBytes);

      final response = await _client.send(
        task: task,
        method: request.method,
        path: path,
        queryParameters: request.url.queryParameters,
        headers: request.headers,
        body: bodyBytes,
        streamResponse: isStream,
      );

      if (response.bodyStream != null) {
        return Response(
          response.statusCode,
          body: response.bodyStream,
          headers: response.headers,
          context: const {'shelf.io.buffer_output': false},
        );
      }
      final responseBody = _postProcessResponse(task, path, response.bodyBytes);
      return Response(
        response.statusCode,
        body: responseBody,
        headers: response.headers,
      );
    } on Exception catch (error) {
      return Response(502, body: 'LLM proxy error: $error');
    }
  }

  bool _detectStreamRequest(Request request, List<int>? bodyBytes) {
    final accept = request.headers['accept'] ?? '';
    if (accept.contains('text/event-stream')) return true;
    if (bodyBytes != null && bodyBytes.isNotEmpty) {
      try {
        final bodyString = String.fromCharCodes(bodyBytes);
        if (bodyString.contains('"stream":true') ||
            bodyString.contains('"stream": true')) {
          return true;
        }
      } catch (_) {
        // ignore
      }
    }
    return false;
  }

  List<int>? _postProcessResponse(
    ModelTask task,
    String path,
    List<int>? bodyBytes,
  ) {
    if (task != ModelTask.tts ||
        !path.contains('audio/voices') ||
        bodyBytes == null ||
        bodyBytes.isEmpty) {
      return bodyBytes;
    }
    try {
      final text = utf8.decode(bodyBytes);
      final json = jsonDecode(text);
      if (json is! Map<String, dynamic>) return bodyBytes;
      final normalized = <String, dynamic>{};
      for (final entry in json.entries) {
        final key = entry.key;
        final sep = key.lastIndexOf('/');
        final backslash = key.lastIndexOf('\\');
        final lastSep = sep > backslash ? sep : backslash;
        final basename = lastSep >= 0 ? key.substring(lastSep + 1) : key;
        normalized[basename] = entry.value;
      }
      return utf8.encode(jsonEncode(normalized));
    } catch (_) {
      return bodyBytes;
    }
  }

  Future<List<int>?> _readBodyBytes(Request request) async {
    if (request.method == 'GET' || request.method == 'HEAD') return null;
    final bytes = await request.read().fold<List<int>>(<int>[], (buffer, data) {
      buffer.addAll(data);
      return buffer;
    });
    return bytes.isEmpty ? null : bytes;
  }
}
