import 'dart:convert';

import 'package:agentos_kernel/agentos_kernel.dart';
import 'package:liteagent_sdk_dart/liteagent_sdk_dart.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../../config.dart';
import '../../locator.dart';
import '../../middleware.dart';
import '../../models/cronkit/cronkit_models.dart';
import '../../services/appkit/appkit_service.dart';
import '../../services/cronkit/cronkit_model_ref_store.dart';

class CronKitController {
  CronKitController({
    required Future<KernelService?> kernelFuture,
    required AppKitService appKitService,
    required AgentOSServiceLocator serviceLocator,
    required CronKitModelRefStore modelRefStore,
    String? liteAgentBaseUrl,
  }) : _kernelFuture = kernelFuture,
       _appKitService = appKitService,
       _serviceLocator = serviceLocator,
       _modelRefStore = modelRefStore,
       _liteAgentBaseUrl = liteAgentBaseUrl;

  final Future<KernelService?> _kernelFuture;
  final AppKitService _appKitService;
  final AgentOSServiceLocator _serviceLocator;
  final CronKitModelRefStore _modelRefStore;
  final String? _liteAgentBaseUrl;

  Router get router {
    final router = Router();
    final guard = requireBearer();

    router.get('/task', guard(_getTask));
    router.get('/task/list', guard(_listTasks));
    router.post('/task/create', guard(_createTask));
    router.post('/task/update', guard(_updateTask));
    router.post('/task/delete', guard(_deleteTask));
    router.post('/task/setEnabled', guard(_setTaskEnabled));
    router.post('/task/runNow', guard(_runTaskNow));
    router.get('/run', guard(_getRun));
    router.get('/run/list', guard(_listRuns));
    router.get('/run/messages', guard(_listRunMessages));
    router.post('/run/delete', guard(_deleteRun));
    return router;
  }

  Future<Response> _createTask(Request request) async {
    _logAppScopeResolution(request, route: 'POST /cronkit/task/create');
    final scope = _requireAppScope(request);
    if (scope == null) {
      return unauthorizedResponse();
    }
    final kernel = await _resolveKernel();
    if (kernel == null) {
      return _notConfigured();
    }
    final payload = await _readJsonBody(request);
    if (payload == null) {
      return _badRequest('Invalid JSON payload.');
    }
    try {
      final parsed = CronKitCreateTaskRequest.fromJson(payload);
      final spec = await _resolveCronSpec(parsed.spec);
      final task = await kernel.createCronTask(
        name: parsed.name,
        schedule: parsed.schedule,
        spec: spec,
        source: _encodeSource(scope),
        userId: parsed.userId,
        sessionId: parsed.sessionId,
        timezone: parsed.timezone,
        concurrency: parsed.concurrency,
        enabled: parsed.enabled,
      );
      await _persistModelRef(
        task.cronId,
        modelId: parsed.spec.modelId,
        scope: scope,
      );
      return _jsonResponse((await _buildTaskDto(task, scope: scope)).toJson());
    } catch (error) {
      return _handleError('createTask', error);
    }
  }

  Future<Response> _updateTask(Request request) async {
    final scope = _requireAppScope(request);
    if (scope == null) {
      return unauthorizedResponse();
    }
    final kernel = await _resolveKernel();
    if (kernel == null) {
      return _notConfigured();
    }
    final payload = await _readJsonBody(request);
    if (payload == null) {
      return _badRequest('Invalid JSON payload.');
    }
    try {
      final parsed = CronKitUpdateTaskRequest.fromJson(payload);
      final spec = parsed.spec == null
          ? null
          : await _resolveCronSpec(parsed.spec!);
      final accessResponse = await _ensureTaskReadableByGroup(
        kernel,
        cronId: parsed.cronId,
        appGroupId: scope.appGroupId,
      );
      if (accessResponse != null) {
        return accessResponse;
      }
      final task = await kernel.updateCronTask(
        cronId: parsed.cronId,
        name: parsed.name,
        schedule: parsed.schedule,
        spec: spec,
        timezone: parsed.timezone,
        concurrency: parsed.concurrency,
        enabled: parsed.enabled,
      );
      if (parsed.spec?.modelId != null) {
        await _persistModelRef(
          task.cronId,
          modelId: parsed.spec!.modelId,
          scope: scope,
        );
      }
      return _jsonResponse((await _buildTaskDto(task, scope: scope)).toJson());
    } catch (error) {
      return _handleError('updateTask', error);
    }
  }

  Future<Response> _getTask(Request request) async {
    final scope = _requireAppScope(request);
    if (scope == null) {
      return unauthorizedResponse();
    }
    final kernel = await _resolveKernel();
    if (kernel == null) {
      return _notConfigured();
    }
    final cronId = request.url.queryParameters['cronId']?.trim();
    if (cronId == null || cronId.isEmpty) {
      return _badRequest('cronId is required');
    }
    try {
      final accessResponse = await _ensureTaskReadableByGroup(
        kernel,
        cronId: cronId,
        appGroupId: scope.appGroupId,
      );
      if (accessResponse != null) {
        return accessResponse;
      }
      final task = await kernel.getCronTask(cronId);
      return _jsonResponse((await _buildTaskDto(task, scope: scope)).toJson());
    } catch (error) {
      return _handleError('getTask', error);
    }
  }

  Future<Response> _listTasks(Request request) async {
    _logAppScopeResolution(request, route: 'GET /cronkit/task/list');
    final scope = _requireAppScope(request);
    if (scope == null) {
      return unauthorizedResponse();
    }
    final kernel = await _resolveKernel();
    if (kernel == null) {
      return _notConfigured();
    }
    try {
      final enabled = _parseQueryBool(request.url.queryParameters['enabled']);
      final offset = _parseQueryInt(
        request.url.queryParameters['offset'],
        fieldName: 'offset',
        defaultValue: 0,
      );
      final limit = _parseQueryInt(
        request.url.queryParameters['limit'],
        fieldName: 'limit',
        defaultValue: 50,
      );
      final tasks = await kernel.listCronTasks(
        enabled: enabled,
        source: null,
        offset: 0,
        limit: 1000000,
      );
      final readableTasks = <CronTaskListItemDto>[];
      for (final item in tasks) {
        final task = await kernel.getCronTask(item.cronId);
        if (_belongsToAppGroup(task.source, scope.appGroupId)) {
          readableTasks.add(item);
        }
      }
      return _jsonResponse(
        readableTasks
            .skip(offset)
            .take(limit)
            .map((item) => CronKitTaskListItemDto.fromKernel(item).toJson())
            .toList(growable: false),
      );
    } catch (error) {
      return _handleError('listTasks', error);
    }
  }

  Future<Response> _deleteTask(Request request) async {
    final scope = _requireAppScope(request);
    if (scope == null) {
      return unauthorizedResponse();
    }
    final kernel = await _resolveKernel();
    if (kernel == null) {
      return _notConfigured();
    }
    final payload = await _readJsonBody(request);
    if (payload == null) {
      return _badRequest('Invalid JSON payload.');
    }
    try {
      final parsed = CronKitCronIdRequest.fromJson(payload);
      final accessResponse = await _ensureTaskReadableByGroup(
        kernel,
        cronId: parsed.cronId,
        appGroupId: scope.appGroupId,
      );
      if (accessResponse != null) {
        return accessResponse;
      }
      await kernel.deleteCronTask(parsed.cronId);
      await _deleteModelRef(parsed.cronId);
      return _jsonResponse(<String, dynamic>{
        'deleted': true,
        'cronId': parsed.cronId,
      });
    } catch (error) {
      return _handleError('deleteTask', error);
    }
  }

  Future<Response> _setTaskEnabled(Request request) async {
    final scope = _requireAppScope(request);
    if (scope == null) {
      return unauthorizedResponse();
    }
    final kernel = await _resolveKernel();
    if (kernel == null) {
      return _notConfigured();
    }
    final payload = await _readJsonBody(request);
    if (payload == null) {
      return _badRequest('Invalid JSON payload.');
    }
    try {
      final parsed = CronKitSetTaskEnabledRequest.fromJson(payload);
      final accessResponse = await _ensureTaskReadableByGroup(
        kernel,
        cronId: parsed.cronId,
        appGroupId: scope.appGroupId,
      );
      if (accessResponse != null) {
        return accessResponse;
      }
      final task = await kernel.updateCronTask(
        cronId: parsed.cronId,
        enabled: parsed.enabled,
      );
      return _jsonResponse((await _buildTaskDto(task, scope: scope)).toJson());
    } catch (error) {
      return _handleError('setTaskEnabled', error);
    }
  }

  Future<Response> _runTaskNow(Request request) async {
    final scope = _requireAppScope(request);
    if (scope == null) {
      return unauthorizedResponse();
    }
    final kernel = await _resolveKernel();
    if (kernel == null) {
      return _notConfigured();
    }
    final payload = await _readJsonBody(request);
    if (payload == null) {
      return _badRequest('Invalid JSON payload.');
    }
    try {
      final parsed = CronKitRunNowRequest.fromJson(payload);
      final accessResponse = await _ensureTaskReadableByGroup(
        kernel,
        cronId: parsed.cronId,
        appGroupId: scope.appGroupId,
      );
      if (accessResponse != null) {
        return accessResponse;
      }
      final run = await kernel.runCronTaskNow(
        parsed.cronId,
        scheduledAt: parsed.scheduledAt,
      );
      return _jsonResponse(CronKitRunDto.fromKernel(run).toJson());
    } catch (error) {
      _logRunNowFailureContext(error);
      return _handleError('runTaskNow', error);
    }
  }

  Future<Response> _listRuns(Request request) async {
    final scope = _requireAppScope(request);
    if (scope == null) {
      return unauthorizedResponse();
    }
    final kernel = await _resolveKernel();
    if (kernel == null) {
      return _notConfigured();
    }
    try {
      final cronId = request.url.queryParameters['cronId']?.trim();
      final after = _parseQueryDateTime(
        request.url.queryParameters['after'],
        fieldName: 'after',
      );
      final before = _parseQueryDateTime(
        request.url.queryParameters['before'],
        fieldName: 'before',
      );
      final offset = _parseQueryInt(
        request.url.queryParameters['offset'],
        fieldName: 'offset',
        defaultValue: 0,
      );
      final limit = _parseQueryInt(
        request.url.queryParameters['limit'],
        fieldName: 'limit',
        defaultValue: 50,
      );
      final runs = await kernel.listCronRuns(
        cronId: cronId == null || cronId.isEmpty ? null : cronId,
        after: after,
        before: before,
        offset: offset,
        limit: limit,
        includeNonDisplayable: true,
      );
      _logKernelRunListPayload(runs);
      final listedTasks = await kernel.listCronTasks(
        source: null,
        offset: 0,
        limit: 1000000,
      );
      final readableCronIds = <String>{};
      for (final item in listedTasks) {
        final task = await kernel.getCronTask(item.cronId);
        if (_belongsToAppGroup(task.source, scope.appGroupId)) {
          readableCronIds.add(item.cronId);
        }
      }
      final visibleRuns = runs
          .where(
            (item) =>
                readableCronIds.contains(item.cronId) &&
                item.hasDisplayableResult,
          )
          .toList(growable: false);
      _logRunListPayload(visibleRuns);
      return _jsonResponse(
        visibleRuns
            .map((item) => CronKitRunListItemDto.fromKernel(item).toJson())
            .toList(growable: false),
      );
    } catch (error) {
      return _handleError('listRuns', error);
    }
  }

  Future<Response> _getRun(Request request) async {
    final scope = _requireAppScope(request);
    if (scope == null) {
      return unauthorizedResponse();
    }
    final kernel = await _resolveKernel();
    if (kernel == null) {
      return _notConfigured();
    }
    try {
      final parsed = CronKitRunIdRequest.fromQuery(request.url.queryParameters);
      final accessResponse = await _ensureRunReadableByGroup(
        kernel,
        runId: parsed.runId,
        appGroupId: scope.appGroupId,
      );
      if (accessResponse != null) {
        return accessResponse;
      }
      final displayableResponse = await _ensureRunDisplayable(
        kernel,
        runId: parsed.runId,
      );
      if (displayableResponse != null) {
        return displayableResponse;
      }
      final run = await kernel.getCronRun(parsed.runId);
      _logRunPayload(run);
      return _jsonResponse(CronKitRunDto.fromKernel(run).toJson());
    } catch (error) {
      return _handleError('getRun', error);
    }
  }

  Future<Response> _listRunMessages(Request request) async {
    final scope = _requireAppScope(request);
    if (scope == null) {
      return unauthorizedResponse();
    }
    final kernel = await _resolveKernel();
    if (kernel == null) {
      return _notConfigured();
    }
    try {
      final parsed = CronKitRunIdRequest.fromQuery(request.url.queryParameters);
      final offset = _parseQueryInt(
        request.url.queryParameters['offset'],
        fieldName: 'offset',
        defaultValue: 0,
      );
      final limit = _parseQueryInt(
        request.url.queryParameters['limit'],
        fieldName: 'limit',
        defaultValue: 200,
      );
      final accessResponse = await _ensureRunReadableByGroup(
        kernel,
        runId: parsed.runId,
        appGroupId: scope.appGroupId,
      );
      if (accessResponse != null) {
        return accessResponse;
      }
      final displayableResponse = await _ensureRunDisplayable(
        kernel,
        runId: parsed.runId,
      );
      if (displayableResponse != null) {
        return displayableResponse;
      }
      final messages = await kernel.listCronRunMessages(
        parsed.runId,
        offset: offset,
        limit: limit,
      );
      _logRunMessagesPayload(parsed.runId, messages);
      return _jsonResponse(
        messages
            .map((item) => CronKitRunMessageDto.fromKernel(item).toJson())
            .toList(growable: false),
      );
    } catch (error) {
      return _handleError('listRunMessages', error);
    }
  }

  Future<Response> _deleteRun(Request request) async {
    final scope = _requireAppScope(request);
    if (scope == null) {
      return unauthorizedResponse();
    }
    final kernel = await _resolveKernel();
    if (kernel == null) {
      return _notConfigured();
    }
    final payload = await _readJsonBody(request);
    if (payload == null) {
      return _badRequest('Invalid JSON payload.');
    }
    try {
      final parsed = CronKitRunIdRequest.fromJson(payload);
      final accessResponse = await _ensureRunReadableByGroup(
        kernel,
        runId: parsed.runId,
        appGroupId: scope.appGroupId,
      );
      if (accessResponse != null) {
        return accessResponse;
      }
      await kernel.deleteCronRun(parsed.runId);
      return _jsonResponse(<String, dynamic>{
        'deleted': true,
        'runId': parsed.runId,
      });
    } catch (error) {
      return _handleError('deleteRun', error);
    }
  }

  Future<KernelService?> _resolveKernel() => _kernelFuture;

  Future<CronKitTaskDto> _buildTaskDto(
    CronTaskDto task, {
    required _AppScope scope,
  }) async {
    final modelId = await _resolveModelIdForTask(task.cronId, scope: scope);
    return CronKitTaskDto.fromKernel(task, modelId: modelId);
  }

  Future<String?> _resolveModelIdForTask(
    String cronId, {
    required _AppScope scope,
  }) async {
    try {
      final ref = await _modelRefStore.get(cronId);
      if (ref == null) {
        return null;
      }
      if (ref.appGroupId != scope.appGroupId) {
        requestLogger.warning(
          'CronKit model ref scope mismatch: cronId=$cronId '
          'storedBundleId=${ref.bundleId} storedAppGroupId=${ref.appGroupId} '
          'requestBundleId=${scope.bundleId} requestAppGroupId=${scope.appGroupId}',
        );
        return null;
      }
      return ref.modelId;
    } catch (error) {
      requestLogger.warning(
        'CronKit model ref read failed: cronId=$cronId error=$error',
      );
      return null;
    }
  }

  Future<void> _persistModelRef(
    String cronId, {
    required String? modelId,
    required _AppScope scope,
  }) async {
    final normalized = modelId?.trim();
    if (normalized == null || normalized.isEmpty) {
      return;
    }
    try {
      await _modelRefStore.put(
        CronKitModelRef(
          cronId: cronId,
          modelId: normalized,
          bundleId: scope.bundleId,
          appGroupId: scope.appGroupId,
          updatedAt: DateTime.now().toUtc(),
        ),
      );
    } catch (error) {
      requestLogger.warning(
        'CronKit model ref write failed: cronId=$cronId modelId=$normalized error=$error',
      );
    }
  }

  Future<void> _deleteModelRef(String cronId) async {
    try {
      await _modelRefStore.delete(cronId);
    } catch (error) {
      requestLogger.warning(
        'CronKit model ref delete failed: cronId=$cronId error=$error',
      );
    }
  }

  Future<AgentCronSpecDto> _resolveCronSpec(
    CronKitAgentCronSpecInput spec,
  ) async {
    final modelId = spec.modelId;
    if (modelId == null || modelId.isEmpty) {
      return spec.toKernelDto();
    }
    final llmConfig = await _resolveLlmConfigById(modelId);
    if (llmConfig == null) {
      throw ArgumentError('Unknown or unavailable modelId: $modelId');
    }
    return spec.toKernelDto(llmConfig: llmConfig);
  }

  Future<LLMConfig?> _resolveLlmConfigById(String id) async {
    final models = await _serviceLocator.getLlmModelList();
    LlmModelInfo? matched;
    for (final model in models) {
      if (model.id == id) {
        matched = model;
        break;
      }
    }
    if (matched == null) {
      return null;
    }
    final baseUrl = await _resolveModelBaseUrl(matched);
    if (baseUrl == null || baseUrl.isEmpty) {
      return null;
    }
    return LLMConfig(
      baseUrl: baseUrl,
      apiKey: matched.apiKey ?? '',
      model: matched.name,
      contextWindowSize: matched.contextWindowSize,
    );
  }

  Future<String?> _resolveModelBaseUrl(LlmModelInfo model) async {
    if (model.isRemote) {
      return model.baseUrl;
    }
    final specificPort =
        await _serviceLocator.getServicePort(
          ApiConfig.serviceLlmText,
          modelId: model.id,
        ) ??
        await _serviceLocator.getServicePort(
          ApiConfig.serviceLlmVision,
          modelId: model.id,
        );
    final fallbackPort =
        specificPort ??
        await _serviceLocator.getServicePort(ApiConfig.serviceLlmText) ??
        await _serviceLocator.getServicePort(ApiConfig.serviceLlmVision);
    if (fallbackPort == null) {
      return null;
    }
    return ApiConfig.getInternalUrl(fallbackPort);
  }

  _AppScope? _requireAppScope(Request request) {
    final token = bearerTokenFrom(request);
    if (token == null || token.isEmpty) {
      requestLogger.warning('CronKit: missing bearer token.');
      return null;
    }
    final bundleId = _appKitService.bundleIdForToken(token);
    final appGroupId = _appKitService.effectiveAppGroupIdForToken(token);
    if (bundleId == null ||
        bundleId.isEmpty ||
        appGroupId == null ||
        appGroupId.isEmpty) {
      requestLogger.warning('CronKit: invalid app token.');
      return null;
    }
    return _AppScope(bundleId: bundleId, appGroupId: appGroupId);
  }

  void _logAppScopeResolution(Request request, {required String route}) {
    final token = bearerTokenFrom(request);
    if (token == null || token.isEmpty) {
      requestLogger.info('$route app auth: missing bearer token');
      return;
    }
    final bundleId = _appKitService.bundleIdForToken(token);
    final appGroupId = _appKitService.effectiveAppGroupIdForToken(token);
    final tokenPreview = token.length <= 12
        ? token
        : '${token.substring(0, 8)}...${token.substring(token.length - 4)}';
    requestLogger.info(
      '$route app auth: token=$tokenPreview bundleId=$bundleId appGroupId=$appGroupId',
    );
  }

  void _logRunPayload(CronRunDto run) {
    final result = run.result;
    final resultKeys = result?.keys.toList(growable: false) ?? const <String>[];
    final resultContent = result == null
        ? null
        : _previewValue(result['content']);
    requestLogger.info(
      'GET /cronkit/run payload: runId=${run.runId} status=${run.status} '
      'hasDisplayableResult=${run.hasDisplayableResult} '
      'displayMessageId=${run.displayMessageId} '
      'displayText=${_previewValue(run.displayText)} '
      'resultKeys=$resultKeys resultContent=$resultContent error=${run.error}',
    );
  }

  void _logRunListPayload(List<CronRunListItemDto> runs) {
    if (runs.isEmpty) {
      requestLogger.info('GET /cronkit/run/list payload: count=0');
      return;
    }
    final latest = runs.first;
    requestLogger.info(
      'GET /cronkit/run/list payload: count=${runs.length} '
      'latestRunId=${latest.runId} latestStatus=${latest.status} '
      'latestHasDisplayableResult=${latest.hasDisplayableResult} '
      'latestDisplayText=${_previewValue(latest.displayText)}',
    );
  }

  void _logKernelRunListPayload(List<CronRunListItemDto> runs) {
    if (runs.isEmpty) {
      requestLogger.info('GET /cronkit/run/list raw kernel payload: count=0');
      return;
    }
    final latest = runs.first;
    requestLogger.info(
      'GET /cronkit/run/list raw kernel payload: count=${runs.length} '
      'latestRunId=${latest.runId} latestStatus=${latest.status} '
      'latestHasDisplayableResult=${latest.hasDisplayableResult} '
      'latestDisplayText=${_previewValue(latest.displayText)}',
    );
  }

  void _logRunMessagesPayload(String runId, List<CronRunMessageDto> messages) {
    if (messages.isEmpty) {
      requestLogger.info(
        'GET /cronkit/run/messages payload: runId=$runId count=0',
      );
      return;
    }
    final last = messages.last.message;
    requestLogger.info(
      'GET /cronkit/run/messages payload: runId=$runId count=${messages.length} '
      'lastType=${last.type} lastRole=${last.role} '
      'lastContent=${_previewValue(last.content)}',
    );
  }

  String _previewValue(Object? value, {int maxLength = 160}) {
    if (value == null) {
      return 'null';
    }
    String text;
    if (value is String) {
      text = value;
    } else {
      try {
        text = jsonEncode(value);
      } catch (_) {
        text = value.toString();
      }
    }
    final normalized = text.replaceAll('\n', r'\n');
    if (normalized.length <= maxLength) {
      return normalized;
    }
    return '${normalized.substring(0, maxLength)}...';
  }

  void _logRunNowFailureContext(Object error) {
    requestLogger.warning(
      'CronKit runNow downstream: liteAgentBaseUrl=$_liteAgentBaseUrl error=$error',
    );
  }

  String _encodeSource(_AppScope scope) {
    final owner = Uri.encodeComponent(scope.bundleId);
    final group = Uri.encodeComponent(scope.appGroupId);
    return 'appkit|owner=$owner|group=$group';
  }

  _AppScope _decodeSource(String source) {
    if (source.startsWith('appkit|')) {
      String? owner;
      String? group;
      for (final segment in source.split('|').skip(1)) {
        final separator = segment.indexOf('=');
        if (separator <= 0) {
          continue;
        }
        final key = segment.substring(0, separator);
        final value = Uri.decodeComponent(segment.substring(separator + 1));
        if (key == 'owner') {
          owner = value;
        } else if (key == 'group') {
          group = value;
        }
      }
      if (owner != null && owner.isNotEmpty) {
        return _AppScope(
          bundleId: owner,
          appGroupId: (group == null || group.isEmpty) ? owner : group,
        );
      }
    }
    if (source.startsWith('appkit:')) {
      final bundleId = source.substring('appkit:'.length);
      return _AppScope(bundleId: bundleId, appGroupId: bundleId);
    }
    return _AppScope(bundleId: source, appGroupId: source);
  }

  bool _belongsToAppGroup(String source, String appGroupId) {
    return _decodeSource(source).appGroupId == appGroupId;
  }

  Future<Response?> _ensureTaskReadableByGroup(
    KernelService kernel, {
    required String cronId,
    required String appGroupId,
  }) async {
    try {
      final task = await kernel.getCronTask(cronId);
      if (_decodeSource(task.source).appGroupId != appGroupId) {
        return Response(404, body: 'Unknown cronId: $cronId');
      }
      return null;
    } on StateError catch (error) {
      return _handleError('taskAccess', error);
    }
  }

  Future<Response?> _ensureRunReadableByGroup(
    KernelService kernel, {
    required String runId,
    required String appGroupId,
  }) async {
    try {
      final run = await kernel.getCronRun(runId);
      final task = await kernel.getCronTask(run.cronId);
      if (_decodeSource(task.source).appGroupId != appGroupId) {
        return Response(404, body: 'Unknown cron runId: $runId');
      }
      return null;
    } on StateError catch (error) {
      return _handleError('runAccess', error);
    }
  }

  Future<Response?> _ensureRunDisplayable(
    KernelService kernel, {
    required String runId,
  }) async {
    try {
      final run = await kernel.getCronRun(runId);
      if (!run.hasDisplayableResult) {
        return Response(404, body: 'Unknown cron runId: $runId');
      }
      return null;
    } on StateError catch (error) {
      return _handleError('runDisplayable', error);
    }
  }

  Response _jsonResponse(Object body, {int statusCode = 200}) {
    return Response(
      statusCode,
      body: jsonEncode(body),
      headers: const {'content-type': 'application/json'},
    );
  }

  Response _badRequest(String message) => Response(400, body: message);

  Response _notConfigured() => Response(503, body: 'CronKit not configured.');

  Response _handleError(String action, Object error) {
    if (error is FormatException) {
      requestLogger.warning('CronKit $action: $error');
      return Response(400, body: error.message);
    }
    if (error is ArgumentError) {
      requestLogger.warning('CronKit $action: $error');
      return Response(400, body: error.message ?? error.toString());
    }
    if (error is StateError) {
      requestLogger.warning('CronKit $action: $error');
      final message = error.message.toString();
      if (message.startsWith('Unknown cronId:') ||
          message.startsWith('Unknown cron runId:')) {
        return Response(404, body: message);
      }
      return Response(503, body: message);
    }
    requestLogger.severe('CronKit $action error: $error');
    return Response(502, body: 'CronKit $action error: $error');
  }

  Future<Map<String, dynamic>?> _readJsonBody(Request request) async {
    try {
      final rawBody = await request.readAsString();
      if (rawBody.isEmpty) {
        return <String, dynamic>{};
      }
      final decoded = jsonDecode(rawBody);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
      return null;
    } catch (_) {
      return null;
    }
  }
}

bool? _parseQueryBool(String? raw) {
  if (raw == null || raw.trim().isEmpty) {
    return null;
  }
  switch (raw.trim().toLowerCase()) {
    case 'true':
    case '1':
    case 'yes':
    case 'on':
      return true;
    case 'false':
    case '0':
    case 'no':
    case 'off':
      return false;
    default:
      throw FormatException('enabled must be a boolean');
  }
}

int _parseQueryInt(
  String? raw, {
  required String fieldName,
  required int defaultValue,
}) {
  if (raw == null || raw.trim().isEmpty) {
    return defaultValue;
  }
  final value = int.tryParse(raw.trim());
  if (value == null) {
    throw FormatException('$fieldName must be an integer');
  }
  if (value < 0) {
    throw FormatException('$fieldName must be >= 0');
  }
  return value;
}

DateTime? _parseQueryDateTime(String? raw, {required String fieldName}) {
  if (raw == null || raw.trim().isEmpty) {
    return null;
  }
  final parsed = DateTime.tryParse(raw.trim());
  if (parsed == null) {
    throw FormatException('$fieldName must be an ISO-8601 datetime string');
  }
  return parsed;
}

class _AppScope {
  const _AppScope({required this.bundleId, required this.appGroupId});

  final String bundleId;
  final String appGroupId;
}
