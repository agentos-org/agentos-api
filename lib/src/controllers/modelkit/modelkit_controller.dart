import 'dart:convert';

import 'package:agentos_kernel/agentos_kernel.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../../config.dart';
import '../../locator.dart';
import '../../services/modelkit/model_client.dart';

/// ModelKit Controller
///
/// Task-oriented gateway controller. Exposes one route per [ModelTask]:
/// `/chat`, `/embedding`, `/asr`, `/tts`. Replaces the legacy IO-oriented
/// `LLMKitController` (`/text`, `/vision`, ...). Vision-language models live
/// behind `/chat` and are identified by `capabilities.vision = true` on the
/// resolved model.
class ModelKitController {
  /// Creates a [ModelKitController].
  ///
  /// [kernelFuture] Future that resolves to KernelService for metrics tracking.
  /// [client] Optional [ModelClient] instance (created automatically if not
  /// provided).
  ModelKitController({
    required Future<KernelService?> kernelFuture,
    ModelClient? client,
  }) : _client = client ?? ModelClient(kernelFuture: kernelFuture);

  final ModelClient _client;

  /// Backing client (exposed for compatibility shims).
  ModelClient get client => _client;

  Router get router {
    final router = Router();

    router.get('/models', _listModels);

    router.get('/chat/models', _listChatModels);
    router.get('/chat/models/', _listChatModels);
    router.get('/chat/v1/models', _listChatModels);
    router.get('/chat/v1/models/', _listChatModels);

    _registerForwardRoutes(router, ModelTask.chat);
    _registerForwardRoutes(router, ModelTask.embedding);
    _registerForwardRoutes(router, ModelTask.asr);
    _registerForwardRoutes(router, ModelTask.tts);

    return router;
  }

  void _registerForwardRoutes(Router router, ModelTask task) {
    final prefix = task.wireName;
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

  /// Lists models in the **task-oriented ModelKit wire schema**.
  ///
  /// Each entry carries `task` (`chat` / `embedding` / `asr` / `tts`),
  /// `input` / `output` modality wire names, and a `capabilities` block.
  /// The legacy IO-oriented `type` field is not emitted; LLMKit consumers
  /// that need it should call `/llmkit/models` instead.
  Future<Response> _listModels(Request request) async {
    try {
      final models = await _client.serviceLocator.getLlmModelList();
      final availableModels = <Map<String, dynamic>>[];

      for (final model in models) {
        if (!await _isModelAvailable(model)) continue;

        final task = _resolveTask(model);
        if (task == null) continue;

        availableModels.add(<String, dynamic>{
          'id': model.id,
          'name': model.name,
          'alias': model.alias,
          'description': model.description,
          'task': task.wireName,
          'input': model.inputModalities.isNotEmpty
              ? model.inputModalities
              : _defaultInputs(task, vision: model.vision),
          'output': model.outputModalities.isNotEmpty
              ? model.outputModalities
              : _defaultOutputs(task),
          'capabilities': {
            'vision': model.vision,
            'tool_call': model.toolCall,
            'stream': model.stream,
            'reasoning': model.reasoning,
          },
          if (model.contextWindowSize != null)
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
      return Response(502, body: 'Model list error: $error');
    }
  }

  /// Lists models in the **llama.cpp combined wire schema** used by
  /// `/chat/v1/models` and `/chat/models`.
  ///
  /// The payload mirrors what llama.cpp emits (an OpenAI-style `object`/`data` block), 
  /// but aggregates **all** available models — remote and local, every task — just like `/models`,
  /// instead of only the models loaded by a single llama backend.
  Future<Response> _listChatModels(Request request) async {
    try {
      final models = await _client.serviceLocator.getLlmModelList();
      final openaiData = <Map<String, dynamic>>[];
      final created = DateTime.now().millisecondsSinceEpoch ~/ 1000;

      for (final model in models) {
        if (!await _isModelAvailable(model)) continue;

        final task = _resolveTask(model);
        if (task == null || task != ModelTask.chat) continue;

        openaiData.add(<String, dynamic>{
          'id': _menuModelLabel(model) ?? model.id,
          'aliases': _aliases(model),
          'tags': const <String>[],
          'object': 'model',
          'created': created,
          'owned_by': model.provider,
          'meta': <String, dynamic>{
            if (model.contextWindowSize != null)
              'n_ctx': model.contextWindowSize,
          },
        });
      }

      return Response.ok(
        jsonEncode({
          'object': 'list',
          'data': openaiData,
        }),
        headers: const {'content-type': 'application/json'},
      );
    } on Exception catch (error) {
      return Response(502, body: 'Model list error: $error');
    }
  }

  /// Builds the menu-facing model label that becomes the OpenAI-style `id`.
  ///
  /// Prefers the alias, appending the canonical name as `alias (name)` when the
  /// two differ, and falls back to name then id. Mirrors the desktop client's
  /// `_displayMenuModelLabel` so the `id` it sends back can be resolved by
  /// [ModelClient].
  static String? _menuModelLabel(LlmModelInfo model) {
    final alias = model.alias.trim();
    if (alias.isNotEmpty) {
      final name = model.name.trim();
      if (name.isNotEmpty && name != alias) {
        return '$alias ($name)';
      }
      return alias;
    }
    final name = model.name.trim();
    if (name.isNotEmpty) {
      return name;
    }
    final id = model.id.trim();
    if (id.isNotEmpty) {
      return id;
    }
    return null;
  }

  static List<String> _aliases(LlmModelInfo model) {
    final aliases = <String>[model.name];
    if (model.alias.isNotEmpty && model.alias != model.name) {
      aliases.add(model.alias);
    }
    return aliases;
  }

  /// Prefer [LlmModelInfo.task] (new locators emit it directly); fall back to
  /// inferring from [LlmModelInfo.type] for legacy locators.
  static ModelTask? _resolveTask(LlmModelInfo model) {
    final taskName = model.task;
    if (taskName != null) {
      for (final t in ModelTask.values) {
        if (t.name == taskName) return t;
      }
    }
    return _inferTaskFromModelType(model.type);
  }

  static List<String> _defaultInputs(ModelTask task, {bool vision = false}) {
    switch (task) {
      case ModelTask.chat:
        return vision ? const ['text', 'image'] : const ['text'];
      case ModelTask.embedding:
        return const ['text'];
      case ModelTask.asr:
        return const ['audio'];
      case ModelTask.tts:
        return const ['text'];
    }
  }

  static List<String> _defaultOutputs(ModelTask task) {
    switch (task) {
      case ModelTask.chat:
        return const ['text'];
      case ModelTask.embedding:
        return const ['text'];
      case ModelTask.asr:
        return const ['text'];
      case ModelTask.tts:
        return const ['audio'];
    }
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
    // Fall back to legacy service keys for chat-capable locators that
    // haven't migrated to `llm_chat` yet.
    if (task == ModelTask.chat) {
      // ignore: deprecated_member_use_from_same_package
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

  /// Infers the [ModelTask] from a legacy `LlmModelInfo.type` string.
  ///
  /// Accepts both new task names (`chat`, `embedding`, `asr`, `tts`) and the
  /// legacy IO-oriented identifiers (`textGeneration`, `imageTextToText`,
  /// `audioTextToText`, `textToSpeech`).
  static ModelTask? _inferTaskFromModelType(String modelType) {
    final normalized = modelType.trim().toLowerCase();
    if (normalized.isEmpty) return null;
    // Direct task names
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

      final responseBody = _postProcessResponse(
        task,
        path,
        response.bodyBytes,
      );
      return Response(
        response.statusCode,
        body: responseBody,
        headers: response.headers,
      );
    } on Exception catch (error) {
      return Response(502, body: 'Model proxy error: $error');
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

  /// Post-processes TTS voices response by stripping filesystem paths from
  /// the upstream `qwen3-tts-server` model keys.
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
