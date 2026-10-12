import 'dart:convert';

import 'package:agentos_kernel/agentos_kernel.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../../locator.dart';
import '../../services/modelkit/model_client.dart';
import '../../services/appkit/appkit_service.dart';

/// ModelKit Controller
///
/// Task-oriented gateway controller. Exposes one route per [ModelTask]:
/// `/chat`, `/embedding`, `/asr`, `/tts`, `/decision`. Vision-language models live
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
    AppKitService? appKitService,
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

    // App model registration API
    router.get('/app-models', _listAppModels);
    router.post('/app-models', _registerAppModel);
    router.put('/app-models/<id>', _updateAppModel);
    router.delete('/app-models/<id>', _unregisterAppModel);
    router.post('/app-models/<id>/toggle', _toggleAppModel);

    _registerForwardRoutes(router, ModelTask.chat);
    _registerForwardRoutes(router, ModelTask.embedding);
    _registerForwardRoutes(router, ModelTask.asr);
    _registerForwardRoutes(router, ModelTask.tts);
    _registerForwardRoutes(router, ModelTask.decision);

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
          if (model.isAppModel) 'isAppModel': true,
          if (model.appBundleId != null) 'appBundleId': model.appBundleId,
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
      case ModelTask.decision:
        return vision ? const ['text', 'image'] : const ['text'];
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
      case ModelTask.decision:
        // 与 llama.cpp `/v1/models` 的 architecture.output_modalities 保持一致。
        return const ['decisions'];
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
    return port != null;
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
      case 'decision':
      case 'llm_decision':
      case 'systemone':
        return ModelTask.decision;
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

  // ===========================================================================
  // App model registration API
  // ===========================================================================

  /// 列出所有第三方应用注册的模型
  Future<Response> _listAppModels(Request request) async {
    try {
      final models = _getAppModelsFromStore();
      return Response.ok(
        jsonEncode(models.map((m) => m.toJson()).toList()),
        headers: const {'content-type': 'application/json'},
      );
    } on Exception catch (error) {
      return Response(500, body: 'App models list error: $error');
    }
  }

  /// 第三方应用注册模型
  Future<Response> _registerAppModel(Request request) async {
    try {
      final bodyBytes = await _readBodyBytes(request);
      if (bodyBytes == null || bodyBytes.isEmpty) {
        return Response(400, body: jsonEncode({'error': 'empty body'}),
            headers: const {'content-type': 'application/json'});
      }

      final body = jsonDecode(String.fromCharCodes(bodyBytes));
      if (body is! Map<String, dynamic>) {
        return Response(400, body: jsonEncode({'error': 'invalid json body'}),
            headers: const {'content-type': 'application/json'});
      }

      final id = (body['id'] as String?)?.trim() ?? '';
      final name = (body['name'] as String?)?.trim() ?? '';
      final appBundleId = (body['appBundleId'] as String?)?.trim() ?? '';

      if (id.isEmpty || name.isEmpty || appBundleId.isEmpty) {
        return Response(400,
            body: jsonEncode({'error': 'id, name and appBundleId are required'}),
            headers: const {'content-type': 'application/json'});
      }

      final appName = (body['appName'] as String?)?.trim() ?? appBundleId;

      final taskStr = (body['task'] as String?)?.trim() ?? 'chat';
      // Validate: must be a known task name
      final validTask = ModelTask.values.firstWhere(
        (t) => t.name == taskStr || t.wireName == taskStr,
        orElse: () => ModelTask.chat,
      );
      final task = validTask.name;

      List<String> parseStringList(dynamic raw) {
        if (raw is! List) return const [];
        return raw.whereType<String>().toList();
      }

      final caps = body['capabilities'];
      final inputModalities = parseStringList(body['input']);
      final outputModalities = parseStringList(body['output']);

      final record = AppModelData(
        id: id,
        name: name,
        alias: (body['alias'] as String?)?.trim() ?? '',
        description: (body['description'] as String?)?.trim() ?? '',
        task: task,
        provider: (body['provider'] as String?)?.trim() ?? 'openai_compatible',
        inputModalities: inputModalities,
        outputModalities: outputModalities,
        stream: caps is Map<String, dynamic> ? (caps['stream'] as bool? ?? true) : true,
        toolCall: caps is Map<String, dynamic> ? (caps['tool_call'] as bool? ?? false) : false,
        reasoning: caps is Map<String, dynamic> ? (caps['reasoning'] as bool? ?? true) : true,
        baseUrl: (body['baseUrl'] as String?)?.trim(),
        apiKey: (body['apiKey'] as String?)?.trim(),
        contextSize: (body['contextWindowSize'] as num?)?.toInt(),
        appBundleId: appBundleId,
        appName: appName,
      );

      await _addAppModelToStore(record);

      return Response.ok(
        jsonEncode({'success': true, 'id': id}),
        headers: const {'content-type': 'application/json'},
      );
    } on Exception catch (error) {
      return Response(500, body: jsonEncode({'error': 'Register app model error: $error'}),
          headers: const {'content-type': 'application/json'});
    }
  }

  /// 更新应用模型
  Future<Response> _updateAppModel(Request request, String id) async {
    try {
      final bodyBytes = await _readBodyBytes(request);
      if (bodyBytes == null || bodyBytes.isEmpty) {
        return Response(400, body: jsonEncode({'error': 'empty body'}),
            headers: const {'content-type': 'application/json'});
      }

      final body = jsonDecode(String.fromCharCodes(bodyBytes));
      if (body is! Map<String, dynamic>) {
        return Response(400, body: jsonEncode({'error': 'invalid json body'}),
            headers: const {'content-type': 'application/json'});
      }

      body['id'] = id;
      final ok = await _updateAppModelInStore(id, body);
      if (!ok) {
        return Response.notFound(
          jsonEncode({'error': 'app model not found: $id'}),
          headers: const {'content-type': 'application/json'},
        );
      }

      return Response.ok(
        jsonEncode({'success': true}),
        headers: const {'content-type': 'application/json'},
      );
    } on Exception catch (error) {
      return Response(500, body: jsonEncode({'error': 'Update app model error: $error'}),
          headers: const {'content-type': 'application/json'});
    }
  }

  /// 第三方应用注销模型
  Future<Response> _unregisterAppModel(Request request, String id) async {
    try {
      final ok = await _deleteAppModelFromStore(id);
      if (!ok) {
        return Response.notFound(
          jsonEncode({'error': 'app model not found: $id'}),
          headers: const {'content-type': 'application/json'},
        );
      }
      return Response.ok(
        jsonEncode({'success': true}),
        headers: const {'content-type': 'application/json'},
      );
    } on Exception catch (error) {
      return Response(500, body: jsonEncode({'error': 'Unregister app model error: $error'}),
          headers: const {'content-type': 'application/json'});
    }
  }

  /// 切换应用模型的禁用状态
  Future<Response> _toggleAppModel(Request request, String id) async {
    try {
      final ok = await _toggleAppModelInStore(id);
      if (!ok) {
        return Response.notFound(
          jsonEncode({'error': 'app model not found: $id'}),
          headers: const {'content-type': 'application/json'},
        );
      }
      return Response.ok(
        jsonEncode({'success': true}),
        headers: const {'content-type': 'application/json'},
      );
    } on Exception catch (error) {
      return Response(500, body: jsonEncode({'error': 'Toggle app model error: $error'}),
          headers: const {'content-type': 'application/json'});
    }
  }

  // --- App model store helpers ---

  AppModelStore? get _appModelStore {
    final locator = _client.serviceLocator;
    if (locator is AppModelStore) return locator as AppModelStore;
    return null;
  }

  List<AppModelData> _getAppModelsFromStore() {
    return _appModelStore?.appModels ?? const [];
  }

  Future<void> _addAppModelToStore(AppModelData data) async {
    final store = _appModelStore;
    if (store == null) return;
    await store.addAppModel(data);
  }

  Future<bool> _updateAppModelInStore(String id, Map<String, dynamic> body) async {
    final store = _appModelStore;
    if (store == null) return false;

    final existing = store.appModels.where((m) => m.id == id).firstOrNull;
    if (existing == null) return false;

    final newKey = (body['apiKey'] as String?)?.trim() ?? '';

    final updated = AppModelData(
      id: id,
      name: (body['name'] as String?)?.trim() ?? existing.name,
      alias: (body['alias'] as String?)?.trim() ?? existing.alias,
      description: (body['description'] as String?)?.trim() ?? existing.description,
      task: (body['task'] as String?)?.trim() ?? existing.task,
      provider: (body['provider'] as String?)?.trim() ?? existing.provider,
      inputModalities: body['input'] is List
          ? (body['input'] as List).whereType<String>().toList()
          : existing.inputModalities,
      outputModalities: body['output'] is List
          ? (body['output'] as List).whereType<String>().toList()
          : existing.outputModalities,
      stream: body['capabilities'] is Map<String, dynamic>
          ? ((body['capabilities'] as Map<String, dynamic>)['stream'] as bool? ?? existing.stream)
          : existing.stream,
      toolCall: body['capabilities'] is Map<String, dynamic>
          ? ((body['capabilities'] as Map<String, dynamic>)['tool_call'] as bool? ?? existing.toolCall)
          : existing.toolCall,
      reasoning: body['capabilities'] is Map<String, dynamic>
          ? ((body['capabilities'] as Map<String, dynamic>)['reasoning'] as bool? ?? existing.reasoning)
          : existing.reasoning,
      baseUrl: (body['baseUrl'] as String?)?.trim() ?? existing.baseUrl,
      apiKey: newKey.isNotEmpty ? newKey : existing.apiKey,
      contextSize: (body['contextWindowSize'] as num?)?.toInt() ?? existing.contextSize,
      isDisabled: existing.isDisabled,
      appBundleId: existing.appBundleId,
      appName: (body['appName'] as String?)?.trim() ?? existing.appName,
    );

    return store.updateAppModel(id, updated);
  }

  Future<bool> _deleteAppModelFromStore(String id) async {
    final store = _appModelStore;
    if (store == null) return false;
    return store.deleteAppModel(id);
  }

  Future<bool> _toggleAppModelInStore(String id) async {
    final store = _appModelStore;
    if (store == null) return false;
    return store.toggleAppModelDisabled(id);
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
