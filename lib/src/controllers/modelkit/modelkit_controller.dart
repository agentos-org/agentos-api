import 'dart:convert';

import 'package:agentos_kernel/agentos_kernel.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../../locator.dart';
import '../../middleware.dart';
import '../../services/modelkit/app_model_id.dart';
import '../../services/modelkit/model_client.dart';
import '../../services/modelkit/model_list_guard.dart';
import '../../services/appkit/appkit_service.dart';

/// App model 写接口的请求错误：携带 HTTP 状态码，由各 handler 统一转成 JSON 响应。
class _AppModelRequestException implements Exception {
  const _AppModelRequestException(this.status, this.message);

  final int status;
  final String message;

  @override
  String toString() => '_AppModelRequestException($status): $message';
}

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
  /// [appKitService] 用于把 Bearer token 解析为调用方 bundleId，
  /// `/app-models` 的写接口依赖它校验调用方身份与模型归属；缺省时这些写接口
  /// 一律拒绝（fail closed）。
  ModelKitController({
    required Future<KernelService?> kernelFuture,
    ModelClient? client,
    AppKitService? appKitService,
  }) : _client = client ?? ModelClient(kernelFuture: kernelFuture),
       _appKitService = appKitService;

  final ModelClient _client;
  final AppKitService? _appKitService;

  /// App model 写操作的串行化队尾。
  ///
  /// 存储层 `appModels` 读取与 `addAppModel`/`updateAppModel` 之间没有原子性，
  /// 并发的同 id 注册会出现“都读到不存在 → 都追加”的重复条目，因此写操作
  /// 必须在同一个 controller 内排队执行。
  Future<void> _appModelWriteTail = Future<void>.value();

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
          // 互斥的来源分类：local / platform / custom / app。
          // 使用端应优先读取它，而不是自行用上面的布尔值推导。
          'source': model.source.wireName,
          if (model.isAppModel) 'isAppModel': true,
          if (model.appBundleId != null) 'appBundleId': model.appBundleId,
          if (model.isAppModel && (model.appName ?? '').isNotEmpty)
            'appName': model.appName,
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
      final created = DateTime.now().millisecondsSinceEpoch ~/ 1000;

      final chatModels = <LlmModelInfo>[];
      for (final model in models) {
        if (!await _isModelAvailable(model)) continue;

        final task = _resolveTask(model);
        if (task == null || task != ModelTask.chat) continue;

        chatModels.add(model);
      }

      // 菜单标签（`alias (name)` / `name`）在列表内不唯一时，冲突项回退为真实 id，
      // 否则客户端回传标签后只能命中列表里的第一个，其余模型无法被精确寻址。
      final menuIds = resolveMenuIds(
        models: chatModels,
        labels: [for (final model in chatModels) _menuModelLabel(model)],
      );

      final openaiData = <Map<String, dynamic>>[
        for (var i = 0; i < chatModels.length; i++)
          <String, dynamic>{
            'id': menuIds[i],
            'aliases': _aliases(chatModels[i]),
            'tags': const <String>[],
            'object': 'model',
            'created': created,
            'owned_by': chatModels[i].provider,
            'meta': <String, dynamic>{
              if (chatModels[i].contextWindowSize != null)
                'n_ctx': chatModels[i].contextWindowSize,
            },
          },
      ];

      return Response.ok(
        jsonEncode({'object': 'list', 'data': openaiData}),
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

      final responseBody = _postProcessResponse(task, path, response.bodyBytes);
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
  ///
  /// 需要 AppKit Bearer token。模型归属于 token 对应的 bundleId：
  /// - body 中的 `appBundleId` 可省略；若提供则必须与 token 一致，否则 403；
  ///   token 对应的 bundleId 必须符合 `[A-Za-z0-9._-]{1,128}`，否则 400；
  /// - 模型 id 由网关用 `bundleId + name` 生成 12 位 hashid（见 [AppModelId.generate]），
  ///   并在响应的 `id` 里返回。这个 hashid 同时是 `/modelkit/models` 里的 `id`，
  ///   也是后续 PUT / DELETE / toggle 用来维护该模型的 id；
  /// - 默认同一应用注册的模型 name 互不相同：注册即按 (bundleId, name) upsert——
  ///   本 bundle 下已有同名模型 → 按“整体替换”更新（保留启用/禁用状态与原 id），
  ///   响应带 `updated: true`，重复注册是幂等的；
  /// - 新 name 对应的 hashid 已被占用（本应用里某个后来改过名的模型沿用着它，
  ///   或极小概率的跨应用 hash 碰撞）→ 409，不会静默覆盖别的模型。
  Future<Response> _registerAppModel(Request request) async {
    try {
      final callerBundleId = _requireCallerBundleId(request);
      final store = _requireAppModelStore();
      final body = await _readJsonObject(request);

      return await _serializeAppModelWrite(() async {
        final name = _optionalString(body, 'name') ?? '';
        if (name.isEmpty) {
          throw const _AppModelRequestException(400, 'name is required');
        }
        if (!AppModelId.isValidBundleId(callerBundleId)) {
          throw _AppModelRequestException(
            400,
            AppModelId.bundleIdRequirement(callerBundleId),
          );
        }

        final declaredBundleId = _optionalString(body, 'appBundleId') ?? '';
        if (declaredBundleId.isNotEmpty && declaredBundleId != callerBundleId) {
          throw const _AppModelRequestException(
            403,
            'appBundleId does not match the bundle of the bearer token',
          );
        }

        // 同一应用下 name 唯一：同名即同一个模型，沿用它的 id 做整体替换。
        final existing = _findAppModelByName(store, callerBundleId, name);
        final String id;
        if (existing != null) {
          id = existing.id;
        } else {
          id = AppModelId.generate(bundleId: callerBundleId, name: name);
          // 新 name 的 hashid 已被别的模型占用：拒绝，避免覆盖。
          final holder = _findAppModelById(store, id);
          if (holder != null) {
            throw _AppModelRequestException(
              409,
              'app model id "$id" derived from name "$name" is already in use '
              '(by model "${holder.name}"); unregister it first or pick a '
              'different name',
            );
          }
        }

        final task = _resolveRegisteredTask(
          body['task'],
          fallback: ModelTask.chat,
        );
        final capabilities = _capabilitiesField(body);
        final inputs = _normalizeInputModalities(
          task,
          _optionalModalities(body, 'input') ?? const <String>[],
        );
        final outputs = _normalizeOutputModalities(
          task,
          _optionalModalities(body, 'output') ?? const <String>[],
        );
        final caps = _normalizeCapabilities(
          task,
          stream: _optionalBool(capabilities, 'stream'),
          toolCall: _optionalBool(capabilities, 'tool_call'),
          reasoning: _optionalBool(capabilities, 'reasoning'),
        );

        final appName = _optionalString(body, 'appName');
        final record = AppModelData(
          id: id,
          name: name,
          alias: _optionalString(body, 'alias') ?? '',
          description: _optionalString(body, 'description') ?? '',
          task: task.name,
          provider: _nonEmptyOr(
            _optionalString(body, 'provider'),
            'openai_compatible',
          ),
          inputModalities: inputs,
          outputModalities: outputs,
          stream: caps.stream,
          toolCall: caps.toolCall,
          reasoning: caps.reasoning,
          baseUrl: _optionalString(body, 'baseUrl'),
          apiKey: _optionalString(body, 'apiKey'),
          contextSize: _optionalInt(body, 'contextWindowSize'),
          isDisabled: existing?.isDisabled ?? false,
          appBundleId: callerBundleId,
          appName: _nonEmptyOr(
            appName,
            _nonEmptyOr(existing?.appName, callerBundleId),
          ),
        );

        final replaced =
            existing != null && await store.updateAppModel(id, record);
        if (!replaced) await store.addAppModel(record);

        return _appModelJson({
          'success': true,
          'id': id,
          if (existing != null) 'updated': true,
        });
      });
    } on _AppModelRequestException catch (error) {
      return _appModelError(error.status, error.message);
    } on Exception catch (error) {
      return _appModelError(500, 'Register app model error: $error');
    }
  }

  /// 更新应用模型（部分更新）
  ///
  /// `id` 是注册时返回的 hashid：只在调用方自己的模型里查找，找不到 → 404
  /// （别的应用的模型对调用方不可见）。改名（`name`）不会改变 `id`。
  /// `appBundleId` 不可变更；`task` 变更时未显式给出的 input/output/capabilities
  /// 会按新任务的默认值重置，避免遗留旧任务（如 chat）的模态与能力。
  Future<Response> _updateAppModel(Request request, String id) async {
    try {
      final callerBundleId = _requireCallerBundleId(request);
      final store = _requireAppModelStore();
      final body = await _readJsonObject(request);

      return await _serializeAppModelWrite(() async {
        final existing = _requireOwnedAppModel(store, id, callerBundleId);

        final declaredBundleId = _optionalString(body, 'appBundleId') ?? '';
        if (declaredBundleId.isNotEmpty &&
            declaredBundleId != existing.appBundleId) {
          throw const _AppModelRequestException(
            400,
            'appBundleId cannot be changed',
          );
        }

        final existingTask =
            _inferTaskFromModelType(existing.task) ?? ModelTask.chat;
        final task = _resolveRegisteredTask(
          body['task'],
          fallback: existingTask,
        );
        final taskChanged = task != existingTask;

        final capabilities = _capabilitiesField(body);
        final inputs = _normalizeInputModalities(
          task,
          _optionalModalities(body, 'input') ??
              (taskChanged ? const <String>[] : existing.inputModalities),
        );
        final outputs = _normalizeOutputModalities(
          task,
          _optionalModalities(body, 'output') ??
              (taskChanged ? const <String>[] : existing.outputModalities),
        );
        final caps = _normalizeCapabilities(
          task,
          stream:
              _optionalBool(capabilities, 'stream') ??
              (taskChanged ? null : existing.stream),
          toolCall:
              _optionalBool(capabilities, 'tool_call') ??
              (taskChanged ? null : existing.toolCall),
          reasoning:
              _optionalBool(capabilities, 'reasoning') ??
              (taskChanged ? null : existing.reasoning),
        );

        // 改名时同样不能与本应用下其他模型同名（同一应用内 name 唯一）。
        // 改名不会改变 id：id 是注册时分配的稳定句柄。
        final name = _nonEmptyOr(_optionalString(body, 'name'), existing.name);
        if (name != existing.name) {
          _requireUniqueNameInApp(
            store,
            bundleId: existing.appBundleId,
            name: name,
            excludeId: id,
          );
        }

        // apiKey 仅在显式给出非空值时覆盖，避免 PUT 误清除已保存的密钥。
        final newKey = _optionalString(body, 'apiKey') ?? '';

        final updated = AppModelData(
          id: id,
          name: name,
          alias: _optionalString(body, 'alias') ?? existing.alias,
          description:
              _optionalString(body, 'description') ?? existing.description,
          task: task.name,
          provider: _nonEmptyOr(
            _optionalString(body, 'provider'),
            existing.provider,
          ),
          inputModalities: inputs,
          outputModalities: outputs,
          stream: caps.stream,
          toolCall: caps.toolCall,
          reasoning: caps.reasoning,
          baseUrl: _optionalString(body, 'baseUrl') ?? existing.baseUrl,
          apiKey: newKey.isNotEmpty ? newKey : existing.apiKey,
          contextSize:
              _optionalInt(body, 'contextWindowSize') ?? existing.contextSize,
          isDisabled: existing.isDisabled,
          appBundleId: existing.appBundleId,
          appName: _nonEmptyOr(
            _optionalString(body, 'appName'),
            existing.appName,
          ),
        );

        if (!await store.updateAppModel(id, updated)) {
          throw _AppModelRequestException(404, 'app model not found: $id');
        }
        return _appModelJson({'success': true});
      });
    } on _AppModelRequestException catch (error) {
      return _appModelError(error.status, error.message);
    } on Exception catch (error) {
      return _appModelError(500, 'Update app model error: $error');
    }
  }

  /// 第三方应用注销模型（`id` 是注册时返回的 hashid，找不到 → 404）
  Future<Response> _unregisterAppModel(Request request, String id) async {
    try {
      final callerBundleId = _requireCallerBundleId(request);
      final store = _requireAppModelStore();

      return await _serializeAppModelWrite(() async {
        final existing = _requireOwnedAppModel(store, id, callerBundleId);
        if (!await store.deleteAppModel(existing.id)) {
          throw _AppModelRequestException(404, 'app model not found: $id');
        }
        return _appModelJson({'success': true});
      });
    } on _AppModelRequestException catch (error) {
      return _appModelError(error.status, error.message);
    } on Exception catch (error) {
      return _appModelError(500, 'Unregister app model error: $error');
    }
  }

  /// 切换应用模型的禁用状态（`id` 是注册时返回的 hashid，找不到 → 404）
  Future<Response> _toggleAppModel(Request request, String id) async {
    try {
      final callerBundleId = _requireCallerBundleId(request);
      final store = _requireAppModelStore();

      return await _serializeAppModelWrite(() async {
        final existing = _requireOwnedAppModel(store, id, callerBundleId);
        if (!await store.toggleAppModelDisabled(existing.id)) {
          throw _AppModelRequestException(404, 'app model not found: $id');
        }
        return _appModelJson({'success': true});
      });
    } on _AppModelRequestException catch (error) {
      return _appModelError(error.status, error.message);
    } on Exception catch (error) {
      return _appModelError(500, 'Toggle app model error: $error');
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

  /// 按 hashid 查找 [bundleId] 名下的应用模型（别的应用的模型视为不存在）。
  static AppModelData? _findAppModel(
    AppModelStore store,
    String bundleId,
    String id,
  ) {
    for (final model in store.appModels) {
      if (model.appBundleId == bundleId && model.id == id) return model;
    }
    return null;
  }

  /// 按 hashid 查找应用模型，不限定归属（hashid 是网关全局唯一的）。
  static AppModelData? _findAppModelById(AppModelStore store, String id) {
    for (final model in store.appModels) {
      if (model.id == id) return model;
    }
    return null;
  }

  /// 在 [bundleId] 名下按 name 查找应用模型（同一应用内 name 视为唯一）。
  static AppModelData? _findAppModelByName(
    AppModelStore store,
    String bundleId,
    String name,
  ) {
    for (final model in store.appModels) {
      if (model.appBundleId == bundleId && model.name == name) return model;
    }
    return null;
  }

  // --- App model write: auth / validation / normalization ---

  /// 通过 `Authorization: Bearer <AppKit token>` 解析调用方 bundleId。
  ///
  /// token 缺失、无效，或网关未接入 [AppKitService] 时抛出 401（fail closed）。
  String _requireCallerBundleId(Request request) {
    final service = _appKitService;
    final token = extractBearerToken(request);
    final bundleId = (service == null || token == null || token.isEmpty)
        ? null
        : service.bundleIdForToken(token)?.trim();
    if (bundleId == null || bundleId.isEmpty) {
      throw const _AppModelRequestException(
        401,
        'Missing or invalid AppKit bearer token',
      );
    }
    return bundleId;
  }

  /// 当前网关的 locator 不支持 app model 持久化时抛出 501，
  /// 避免写接口“假成功”但实际什么都没保存。
  AppModelStore _requireAppModelStore() {
    final store = _appModelStore;
    if (store == null) {
      throw const _AppModelRequestException(
        501,
        'App model registration is not supported by this gateway',
      );
    }
    return store;
  }

  /// 取出调用方 bundle（[callerBundleId]）名下 hashid 为 [id] 的模型；
  /// 找不到 → 404。别的应用的模型对调用方不可见，
  /// 因此不存在“修改了别人的模型”的路径，也就不再需要 403。
  static AppModelData _requireOwnedAppModel(
    AppModelStore store,
    String id,
    String callerBundleId,
  ) {
    final existing = _findAppModel(store, callerBundleId, id);
    if (existing == null) {
      throw _AppModelRequestException(404, 'app model not found: $id');
    }
    return existing;
  }

  /// 同一个应用（[bundleId]）下不允许存在同名模型：若已有 id 不为 [excludeId]、
  /// 但 name 相同的模型，抛出 409。
  ///
  /// - 仅限同一 bundle 内唯一，不同应用之间允许同名；
  /// - 已禁用的模型仍占用名称；
  /// - name 按 trim 后精确匹配（区分大小写），与 `id` 的比较方式一致。
  ///
  /// 必须在 [_serializeAppModelWrite] 的串行区内调用，才能与随后的写入构成原子操作。
  static void _requireUniqueNameInApp(
    AppModelStore store, {
    required String bundleId,
    required String name,
    required String excludeId,
  }) {
    for (final model in store.appModels) {
      if (model.appBundleId == bundleId &&
          model.id != excludeId &&
          model.name == name) {
        throw _AppModelRequestException(
          409,
          'app model name "$name" is already registered by this app '
          '(id "${model.id}")',
        );
      }
    }
  }

  /// 串行执行 app model 写操作（见 [_appModelWriteTail]）。
  Future<T> _serializeAppModelWrite<T>(Future<T> Function() action) {
    final run = _appModelWriteTail.then((_) => action());
    // 队尾吞掉异常，避免一次失败阻塞后续写入。
    _appModelWriteTail = run.then<void>((_) {}, onError: (Object _) {});
    return run;
  }

  Future<Map<String, dynamic>> _readJsonObject(Request request) async {
    final bytes = await _readBodyBytes(request);
    if (bytes == null || bytes.isEmpty) {
      throw const _AppModelRequestException(400, 'empty body');
    }
    final Object? decoded;
    try {
      // 必须按 UTF-8 解码：String.fromCharCodes 会把中文 appName/description 解成乱码。
      decoded = jsonDecode(utf8.decode(bytes));
    } on FormatException {
      throw const _AppModelRequestException(400, 'invalid json body');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const _AppModelRequestException(400, 'invalid json body');
    }
    return decoded;
  }

  static Response _appModelJson(Map<String, dynamic> data) => Response.ok(
    jsonEncode(data),
    headers: const {'content-type': 'application/json'},
  );

  static Response _appModelError(int status, String message) => Response(
    status,
    body: jsonEncode({'error': message}),
    headers: const {'content-type': 'application/json'},
  );

  /// 读取可选字符串字段（已 trim）；缺失返回 null，类型不符抛 400。
  static String? _optionalString(Map<String, dynamic> body, String key) {
    final value = body[key];
    if (value == null) return null;
    if (value is! String) {
      throw _AppModelRequestException(400, '$key must be a string');
    }
    return value.trim();
  }

  /// 读取可选整数字段；缺失返回 null，类型不符抛 400。
  static int? _optionalInt(Map<String, dynamic> body, String key) {
    final value = body[key];
    if (value == null) return null;
    if (value is! num) {
      throw _AppModelRequestException(400, '$key must be a number');
    }
    return value.toInt();
  }

  /// 读取可选 `capabilities` 对象；缺失返回 null，类型不符抛 400。
  static Map<String, dynamic>? _capabilitiesField(Map<String, dynamic> body) {
    final value = body['capabilities'];
    if (value == null) return null;
    if (value is! Map<String, dynamic>) {
      throw const _AppModelRequestException(
        400,
        'capabilities must be an object',
      );
    }
    return value;
  }

  /// 读取 `capabilities` 中的布尔项；缺失返回 null，类型不符抛 400。
  static bool? _optionalBool(Map<String, dynamic>? capabilities, String key) {
    final value = capabilities?[key];
    if (value == null) return null;
    if (value is! bool) {
      throw _AppModelRequestException(
        400,
        'capabilities.$key must be a boolean',
      );
    }
    return value;
  }

  /// 读取可选模态数组（小写、去空、去重）；缺失返回 null，类型不符抛 400。
  static List<String>? _optionalModalities(
    Map<String, dynamic> body,
    String key,
  ) {
    final value = body[key];
    if (value == null) return null;
    if (value is! List) {
      throw _AppModelRequestException(400, '$key must be an array of strings');
    }
    final result = <String>[];
    for (final item in value) {
      if (item is! String) continue;
      final normalized = item.trim().toLowerCase();
      if (normalized.isNotEmpty && !result.contains(normalized)) {
        result.add(normalized);
      }
    }
    return result;
  }

  static String _nonEmptyOr(String? value, String fallback) =>
      (value == null || value.isEmpty) ? fallback : value;

  /// 严格解析注册/更新请求中的 `task`。
  ///
  /// 接受 `chat` / `embedding` / `asr` / `tts` / `decision`（以及 decision 的别名
  /// `systemone`、`llm_decision`），大小写不敏感；缺失或为空时用 [fallback]；
  /// 其余值抛 400，而不是像以前那样静默当成 chat。
  static ModelTask _resolveRegisteredTask(
    Object? raw, {
    required ModelTask fallback,
  }) {
    if (raw == null) return fallback;
    if (raw is! String) {
      throw const _AppModelRequestException(400, 'task must be a string');
    }
    final normalized = raw.trim().toLowerCase();
    if (normalized.isEmpty) return fallback;
    if (normalized == 'systemone' || normalized == 'llm_decision') {
      return ModelTask.decision;
    }
    for (final task in ModelTask.values) {
      if (task.name == normalized || task.wireName == normalized) return task;
    }
    throw _AppModelRequestException(
      400,
      'unsupported task "${raw.trim()}"; expected one of: '
      '${ModelTask.values.map((t) => t.wireName).join(', ')}',
    );
  }

  /// 归一化输入模态。
  ///
  /// - decision：输入只允许 `text`（可选 `image` 作多模态）；`decisions` 属于
  ///   输出，不允许作为输入；缺省为 `[text]`。
  /// - 其他任务：保留调用方给出的值但剔除 `decisions`（它只属于 decision 的输出），
  ///   为空时取 [_defaultInputs]。
  static List<String> _normalizeInputModalities(
    ModelTask task,
    List<String> requested,
  ) {
    if (task == ModelTask.decision) {
      final allowed = requested
          .where((m) => m == 'text' || m == 'image')
          .toList(growable: false);
      if (allowed.isEmpty) return const ['text'];
      return ['text', if (allowed.contains('image')) 'image'];
    }
    final kept = requested.where((m) => m != 'decisions').toList();
    return kept.isEmpty ? _defaultInputs(task) : kept;
  }

  /// 归一化输出模态：decision 固定为 `[decisions]`；其他任务保留调用方给出的值但
  /// 剔除 `decisions`，为空时取 [_defaultOutputs]。
  static List<String> _normalizeOutputModalities(
    ModelTask task,
    List<String> requested,
  ) {
    if (task == ModelTask.decision) return _defaultOutputs(task);
    final kept = requested.where((m) => m != 'decisions').toList();
    return kept.isEmpty ? _defaultOutputs(task) : kept;
  }

  /// 归一化能力位。
  ///
  /// decision（`/v1/systemone`）既不流式、也不支持工具调用和推理，无论调用方
  /// 传什么都强制为 false；其他任务沿用历史默认（stream/reasoning 默认 true，
  /// tool_call 默认 false）。
  static ({bool stream, bool toolCall, bool reasoning}) _normalizeCapabilities(
    ModelTask task, {
    bool? stream,
    bool? toolCall,
    bool? reasoning,
  }) {
    if (task == ModelTask.decision) {
      return (stream: false, toolCall: false, reasoning: false);
    }
    return (
      stream: stream ?? true,
      toolCall: toolCall ?? false,
      reasoning: reasoning ?? true,
    );
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
