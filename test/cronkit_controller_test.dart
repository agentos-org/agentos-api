import 'dart:convert';

import 'package:agentos_api/src/controllers/cronkit/cronkit_controller.dart';
import 'package:agentos_api/src/locator.dart' as api_locator;
import 'package:agentos_api/src/models/app/app_models.dart';
import 'package:agentos_api/src/services/appkit/appkit_service.dart';
import 'package:agentos_api/src/services/cronkit/cronkit_model_ref_store.dart';
import 'package:agentos_kernel/agentos_kernel.dart';
import 'package:liteagent_sdk_dart/liteagent_sdk_dart.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

class _FakeKernelService implements KernelService {
  String? createdSource;
  AgentCronSpecDto? createdSpec;
  final Map<String, CronTaskDto> tasksById = <String, CronTaskDto>{};
  final Map<String, CronRunDto> runsById = <String, CronRunDto>{};
  final Map<String, List<CronRunMessageDto>> messagesByRunId =
      <String, List<CronRunMessageDto>>{};
  final now = DateTime.parse('2026-03-17T12:00:00Z');

  @override
  Future<CronTaskDto> createCronTask({
    required String name,
    required String schedule,
    required AgentCronSpecDto spec,
    String source = KernelSources.api,
    String? userId,
    String? sessionId,
    String? timezone,
    CronTaskConcurrencyDto concurrency = CronTaskConcurrencyDto.skipIfRunning,
    bool enabled = true,
  }) async {
    createdSource = source;
    createdSpec = spec;
    final task = CronTaskDto(
      cronId: 'cron-1',
      name: name,
      schedule: schedule,
      source: source,
      userId: userId,
      sessionId: sessionId,
      timezone: timezone,
      enabled: enabled,
      status: enabled ? 'active' : 'paused',
      concurrency: concurrency,
      createdAt: now,
      updatedAt: now,
      nextRunAt: now.add(const Duration(hours: 1)),
      spec: spec,
    );
    tasksById[task.cronId] = task;
    return task;
  }

  @override
  Future<CronTaskDto> getCronTask(String cronId) async {
    final task = tasksById[cronId];
    if (task == null) {
      throw StateError('Unknown cronId: $cronId');
    }
    return task;
  }

  @override
  Future<List<CronTaskListItemDto>> listCronTasks({
    bool? enabled,
    String? source,
    int offset = 0,
    int limit = 50,
  }) async {
    return tasksById.values
        .where((task) => enabled == null || task.enabled == enabled)
        .skip(offset)
        .take(limit)
        .map(
          (task) => CronTaskListItemDto(
            cronId: task.cronId,
            name: task.name,
            schedule: task.schedule,
            enabled: task.enabled,
            status: task.status,
            lastRunAt: task.lastRunAt,
            nextRunAt: task.nextRunAt,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<CronTaskDto> pauseCronTask(String cronId) => getCronTask(cronId);

  @override
  Future<CronTaskDto> resumeCronTask(String cronId) => getCronTask(cronId);

  @override
  Future<CronTaskDto> updateCronTask({
    required String cronId,
    String? name,
    String? schedule,
    AgentCronSpecDto? spec,
    String? timezone,
    CronTaskConcurrencyDto? concurrency,
    bool? enabled,
  }) async {
    final existing = await getCronTask(cronId);
    final updated = CronTaskDto(
      cronId: existing.cronId,
      name: name ?? existing.name,
      schedule: schedule ?? existing.schedule,
      source: existing.source,
      userId: existing.userId,
      sessionId: existing.sessionId,
      timezone: timezone ?? existing.timezone,
      enabled: enabled ?? existing.enabled,
      status: enabled == null
          ? existing.status
          : (enabled ? 'active' : 'paused'),
      concurrency: concurrency ?? existing.concurrency,
      createdAt: existing.createdAt,
      updatedAt: now,
      lastRunAt: existing.lastRunAt,
      nextRunAt: existing.nextRunAt,
      spec: spec ?? existing.spec,
    );
    tasksById[cronId] = updated;
    return updated;
  }

  @override
  Future<void> deleteCronTask(String cronId) async {
    tasksById.remove(cronId);
  }

  @override
  Future<CronRunDto> runCronTaskNow(
    String cronId, {
    DateTime? scheduledAt,
  }) async {
    final run = CronRunDto(
      runId: 'run-1',
      cronId: cronId,
      trigger: 'manual',
      status: 'succeeded',
      scheduledAt: scheduledAt ?? now,
      startedAt: now,
      hasDisplayableResult: false,
      finishedAt: now.add(const Duration(minutes: 1)),
      result: const {'message': 'ok'},
    );
    runsById[run.runId] = run;
    return run;
  }

  @override
  Future<CronRunDto> getCronRun(String runId) async {
    final run = runsById[runId];
    if (run == null) {
      throw StateError('Unknown cron runId: $runId');
    }
    return run;
  }

  @override
  Future<List<CronRunListItemDto>> listCronRuns({
    String? cronId,
    DateTime? after,
    DateTime? before,
    int offset = 0,
    int limit = 50,
    bool includeNonDisplayable = false,
  }) async {
    return runsById.values
        .where((run) => cronId == null || run.cronId == cronId)
        .map(
          (run) => CronRunListItemDto(
            runId: run.runId,
            cronId: run.cronId,
            trigger: run.trigger,
            status: run.status,
            scheduledAt: run.scheduledAt,
            startedAt: run.startedAt,
            hasDisplayableResult: run.hasDisplayableResult,
            finishedAt: run.finishedAt,
            llmConfig: run.llmConfig,
            displayText: run.displayText,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<List<CronRunMessageDto>> listCronRunMessages(
    String runId, {
    int offset = 0,
    int limit = 200,
  }) async {
    return messagesByRunId[runId] ?? const <CronRunMessageDto>[];
  }

  @override
  Future<void> deleteCronRun(String runId) async {
    final removedRun = runsById.remove(runId);
    messagesByRunId.remove(runId);
    if (removedRun == null) {
      throw StateError('Unknown cron runId: $runId');
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not mocked');
}

class _FakeServiceLocator implements api_locator.AgentOSServiceLocator {
  @override
  String get liteagentBaseUrl => 'http://127.0.0.1:9527/api/v1';

  @override
  Stream<api_locator.ServiceStatusEvent> get serviceStatusStream =>
      const Stream<api_locator.ServiceStatusEvent>.empty();

  @override
  Future<List<api_locator.AppInfo>> getAppInfoList() async =>
      const <api_locator.AppInfo>[];

  @override
  Future<List<api_locator.LlmModelInfo>> getLlmModelList() async {
    return const <api_locator.LlmModelInfo>[
      api_locator.LlmModelInfo(
        id: 'gpt-4o',
        name: 'gpt-4o',
        alias: 'gpt-4o',
        description: 'remote model',
        parameters: 'remote',
        paramsB: 0,
        quantization: 'remote',
        sizeGB: 0,
        minRAMGB: 0,
        downloadUrl: '',
        tags: <String>[],
        repoId: '',
        type: 'textGeneration',
        contextWindowSize: 128000,
        baseUrl: 'https://api.example.com/v1',
        apiKey: 'secret-key',
        isCustom: true,
      ),
    ];
  }

  @override
  Future<int?> getServicePort(String serviceKey, {String? modelId}) async {
    return null;
  }
}

class _FakeCronKitModelRefStore implements CronKitModelRefStore {
  final Map<String, CronKitModelRef> refsByCronId = <String, CronKitModelRef>{};

  @override
  Future<void> delete(String cronId) async {
    refsByCronId.remove(cronId);
  }

  @override
  Future<CronKitModelRef?> get(String cronId) async {
    return refsByCronId[cronId];
  }

  @override
  Future<void> put(CronKitModelRef ref) async {
    refsByCronId[ref.cronId] = ref;
  }
}

void main() {
  group('CronKitController', () {
    late AppKitService appKitService;
    late api_locator.AgentOSServiceLocator serviceLocator;
    late _FakeCronKitModelRefStore modelRefStore;
    late String desktopToken;
    late String mobileToken;

    setUp(() {
      appKitService = AppKitService();
      serviceLocator = _FakeServiceLocator();
      modelRefStore = _FakeCronKitModelRefStore();
      desktopToken = appKitService
          .registerBundle(
            AppBundleDto(
              bundleId: 'com.litevar.agentosChat',
              appGroupId: 'com.litevar.agentos',
            ),
          )
          .token;
      mobileToken = appKitService
          .registerBundle(
            AppBundleDto(
              bundleId: 'com.litevar.agentosMobile',
              appGroupId: 'com.litevar.agentos',
            ),
          )
          .token;
    });

    test('create task resolves modelId into kernel llmConfig', () async {
      final kernel = _FakeKernelService();
      final controller = CronKitController(
        kernelFuture: Future.value(kernel),
        appKitService: appKitService,
        serviceLocator: serviceLocator,
        modelRefStore: modelRefStore,
      );

      final response = await controller.router.call(
        Request(
          'POST',
          Uri.parse('http://localhost/task/create'),
          headers: <String, String>{
            'authorization': 'Bearer $desktopToken',
            'content-type': 'application/json',
          },
          body: jsonEncode(<String, dynamic>{
            'name': 'Nightly Sync',
            'schedule': '0 2 * * *',
            'spec': <String, dynamic>{
              'systemPrompt': 'system',
              'content': <Map<String, dynamic>>[
                <String, dynamic>{'type': 'text', 'message': 'sync records'},
              ],
              'modelId': 'gpt-4o',
            },
          }),
        ),
      );

      expect(response.statusCode, 200);
      final payload =
          jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      expect(kernel.createdSpec, isNotNull);
      expect(kernel.createdSpec!.llmConfig, isNotNull);
      expect(
        kernel.createdSpec!.llmConfig!.baseUrl,
        'https://api.example.com/v1',
      );
      expect(kernel.createdSpec!.llmConfig!.apiKey, 'secret-key');
      expect(kernel.createdSpec!.llmConfig!.model, 'gpt-4o');
      expect(modelRefStore.refsByCronId['cron-1']?.modelId, 'gpt-4o');
      expect(payload['spec']['modelName'], 'gpt-4o');
      expect(payload['spec']['modelId'], 'gpt-4o');
      expect(payload['spec'].containsKey('llmConfig'), isFalse);
      expect(jsonEncode(payload), isNot(contains('secret-key')));
      expect(
        kernel.createdSource,
        'appkit|owner=com.litevar.agentosChat|group=com.litevar.agentos',
      );
    });

    test('same app group can read run detail and messages', () async {
      final kernel = _FakeKernelService();
      kernel.tasksById['cron-1'] = CronTaskDto(
        cronId: 'cron-1',
        name: 'desktop task',
        schedule: '* * * * *',
        source:
            'appkit|owner=com.litevar.agentosChat|group=com.litevar.agentos',
        enabled: true,
        status: 'active',
        concurrency: CronTaskConcurrencyDto.skipIfRunning,
        createdAt: kernel.now,
        updatedAt: kernel.now,
        spec: AgentCronSpecDto(
          systemPrompt: 'system',
          content: <Content>[
            Content(type: ContentType.text, message: 'prompt'),
          ],
        ),
      );
      kernel.runsById['run-1'] = CronRunDto(
        runId: 'run-1',
        cronId: 'cron-1',
        trigger: 'scheduler',
        status: 'succeeded',
        scheduledAt: kernel.now,
        startedAt: kernel.now,
        hasDisplayableResult: true,
        finishedAt: kernel.now.add(const Duration(minutes: 1)),
        llmConfig: LLMConfig(
          baseUrl: 'https://api.example.com/v1',
          apiKey: 'secret-key',
          model: 'gpt-4o',
          contextWindowSize: 128000,
        ),
        displayText: 'done',
      );
      await modelRefStore.put(
        CronKitModelRef(
          cronId: 'cron-1',
          modelId: 'gpt-4o-id',
          modelName: 'gpt-4o',
          bundleId: 'com.litevar.agentosChat',
          appGroupId: 'com.litevar.agentos',
          updatedAt: kernel.now,
        ),
      );
      kernel.messagesByRunId['run-1'] = <CronRunMessageDto>[
        CronRunMessageDto(
          messageId: 'msg-1',
          runId: 'run-1',
          cronId: 'cron-1',
          timestamp: kernel.now,
          message: AgentMessage(
            sessionId: 'session-1',
            taskId: 'task-1',
            role: AgentRoleType.LLM,
            to: AgentRoleType.USER,
            type: AgentMessageType.TEXT,
            content: 'done',
            createTime: kernel.now,
          ),
        ),
      ];
      final controller = CronKitController(
        kernelFuture: Future.value(kernel),
        appKitService: appKitService,
        serviceLocator: serviceLocator,
        modelRefStore: modelRefStore,
      );

      final runResponse = await controller.router.call(
        Request(
          'GET',
          Uri.parse('http://localhost/run?runId=run-1'),
          headers: <String, String>{'authorization': 'Bearer $mobileToken'},
        ),
      );
      final messageResponse = await controller.router.call(
        Request(
          'GET',
          Uri.parse('http://localhost/run/messages?runId=run-1'),
          headers: <String, String>{'authorization': 'Bearer $mobileToken'},
        ),
      );

      expect(runResponse.statusCode, 200);
      expect(messageResponse.statusCode, 200);
      final runPayload =
          jsonDecode(await runResponse.readAsString()) as Map<String, dynamic>;
      expect(runPayload['trigger'], 'scheduler');
      expect(runPayload['modelId'], 'gpt-4o-id');
      expect(runPayload.containsKey('llmConfig'), isFalse);
      expect(runPayload.containsKey('displayText'), isTrue);
      final messagePayload =
          jsonDecode(await messageResponse.readAsString()) as List<dynamic>;
      expect(messagePayload, hasLength(1));
      expect(messagePayload.first['messageId'], 'msg-1');
      expect(messagePayload.first['message']['content'], 'done');
    });

    test('same app group can delete run', () async {
      final kernel = _FakeKernelService();
      kernel.tasksById['cron-1'] = CronTaskDto(
        cronId: 'cron-1',
        name: 'desktop task',
        schedule: '* * * * *',
        source:
            'appkit|owner=com.litevar.agentosChat|group=com.litevar.agentos',
        enabled: true,
        status: 'active',
        concurrency: CronTaskConcurrencyDto.skipIfRunning,
        createdAt: kernel.now,
        updatedAt: kernel.now,
        spec: AgentCronSpecDto(
          systemPrompt: 'system',
          content: <Content>[
            Content(type: ContentType.text, message: 'prompt'),
          ],
        ),
      );
      kernel.runsById['run-1'] = CronRunDto(
        runId: 'run-1',
        cronId: 'cron-1',
        trigger: 'scheduler',
        status: 'succeeded',
        scheduledAt: kernel.now,
        startedAt: kernel.now,
        hasDisplayableResult: true,
      );
      kernel.messagesByRunId['run-1'] = <CronRunMessageDto>[
        CronRunMessageDto(
          messageId: 'msg-1',
          runId: 'run-1',
          cronId: 'cron-1',
          timestamp: kernel.now,
          message: AgentMessage(
            sessionId: 'session-1',
            taskId: 'task-1',
            role: AgentRoleType.AGENT,
            to: AgentRoleType.USER,
            type: AgentMessageType.TEXT,
            content: 'done',
            createTime: kernel.now,
          ),
        ),
      ];
      final controller = CronKitController(
        kernelFuture: Future.value(kernel),
        appKitService: appKitService,
        serviceLocator: serviceLocator,
        modelRefStore: modelRefStore,
      );

      final mobileDeleteResponse = await controller.router.call(
        Request(
          'POST',
          Uri.parse('http://localhost/run/delete'),
          headers: <String, String>{
            'authorization': 'Bearer $mobileToken',
            'content-type': 'application/json',
          },
          body: jsonEncode(<String, dynamic>{'runId': 'run-1'}),
        ),
      );
      expect(mobileDeleteResponse.statusCode, 200);
      expect(kernel.runsById.containsKey('run-1'), isFalse);
      expect(kernel.messagesByRunId['run-1'], isNull);
      final payload =
          jsonDecode(await mobileDeleteResponse.readAsString())
              as Map<String, dynamic>;
      expect(payload['deleted'], isTrue);
      expect(payload['runId'], 'run-1');
    });

    test('same app group can set task enabled explicitly', () async {
      final kernel = _FakeKernelService();
      kernel.tasksById['cron-1'] = CronTaskDto(
        cronId: 'cron-1',
        name: 'desktop task',
        schedule: '* * * * *',
        source:
            'appkit|owner=com.litevar.agentosChat|group=com.litevar.agentos',
        enabled: true,
        status: 'active',
        concurrency: CronTaskConcurrencyDto.skipIfRunning,
        createdAt: kernel.now,
        updatedAt: kernel.now,
        spec: AgentCronSpecDto(
          systemPrompt: 'system',
          content: <Content>[
            Content(type: ContentType.text, message: 'prompt'),
          ],
        ),
      );
      final controller = CronKitController(
        kernelFuture: Future.value(kernel),
        appKitService: appKitService,
        serviceLocator: serviceLocator,
        modelRefStore: modelRefStore,
      );

      final disableResponse = await controller.router.call(
        Request(
          'POST',
          Uri.parse('http://localhost/task/setEnabled'),
          headers: <String, String>{
            'authorization': 'Bearer $mobileToken',
            'content-type': 'application/json',
          },
          body: jsonEncode(<String, dynamic>{
            'cronId': 'cron-1',
            'enabled': false,
          }),
        ),
      );
      expect(disableResponse.statusCode, 200);
      final disablePayload =
          jsonDecode(await disableResponse.readAsString())
              as Map<String, dynamic>;
      expect(disablePayload['enabled'], isFalse);
      expect(disablePayload['status'], 'paused');

      final enableResponse = await controller.router.call(
        Request(
          'POST',
          Uri.parse('http://localhost/task/setEnabled'),
          headers: <String, String>{
            'authorization': 'Bearer $mobileToken',
            'content-type': 'application/json',
          },
          body: jsonEncode(<String, dynamic>{
            'cronId': 'cron-1',
            'enabled': true,
          }),
        ),
      );
      expect(enableResponse.statusCode, 200);
      final enablePayload =
          jsonDecode(await enableResponse.readAsString())
              as Map<String, dynamic>;
      expect(enablePayload['enabled'], isTrue);
      expect(enablePayload['status'], 'active');
    });

    test('same app group can update task', () async {
      final kernel = _FakeKernelService();
      kernel.tasksById['cron-1'] = CronTaskDto(
        cronId: 'cron-1',
        name: 'desktop task',
        schedule: '* * * * *',
        source:
            'appkit|owner=com.litevar.agentosChat|group=com.litevar.agentos',
        enabled: true,
        status: 'active',
        concurrency: CronTaskConcurrencyDto.skipIfRunning,
        createdAt: kernel.now,
        updatedAt: kernel.now,
        spec: AgentCronSpecDto(
          systemPrompt: 'system',
          content: <Content>[
            Content(type: ContentType.text, message: 'prompt'),
          ],
        ),
      );
      final controller = CronKitController(
        kernelFuture: Future.value(kernel),
        appKitService: appKitService,
        serviceLocator: serviceLocator,
        modelRefStore: modelRefStore,
      );

      final response = await controller.router.call(
        Request(
          'POST',
          Uri.parse('http://localhost/task/update'),
          headers: <String, String>{
            'authorization': 'Bearer $mobileToken',
            'content-type': 'application/json',
          },
          body: jsonEncode(<String, dynamic>{
            'cronId': 'cron-1',
            'name': 'mobile updated task',
            'schedule': '0 * * * *',
          }),
        ),
      );

      expect(response.statusCode, 200);
      final payload =
          jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      expect(payload['cronId'], 'cron-1');
      expect(payload['name'], 'mobile updated task');
      expect(payload['schedule'], '0 * * * *');
      expect(kernel.tasksById['cron-1']?.name, 'mobile updated task');
    });

    test('update task persists and returns latest model selection', () async {
      final kernel = _FakeKernelService();
      kernel.tasksById['cron-1'] = CronTaskDto(
        cronId: 'cron-1',
        name: 'daily reminder',
        schedule: '0 8 * * *',
        source:
            'appkit|owner=com.litevar.agentosChat|group=com.litevar.agentos',
        enabled: true,
        status: 'active',
        concurrency: CronTaskConcurrencyDto.skipIfRunning,
        createdAt: kernel.now,
        updatedAt: kernel.now,
        spec: AgentCronSpecDto(
          systemPrompt: 'system',
          content: <Content>[
            Content(type: ContentType.text, message: 'drink water'),
          ],
          llmConfig: LLMConfig(
            baseUrl: 'https://api.example.com/v1',
            apiKey: 'secret-key',
            model: 'qwen3.5-122b-a10b',
          ),
        ),
      );
      final controller = CronKitController(
        kernelFuture: Future.value(kernel),
        appKitService: appKitService,
        serviceLocator: serviceLocator,
        modelRefStore: modelRefStore,
      );

      final updateResponse = await controller.router.call(
        Request(
          'POST',
          Uri.parse('http://localhost/task/update'),
          headers: <String, String>{
            'authorization': 'Bearer $mobileToken',
            'content-type': 'application/json',
          },
          body: jsonEncode(<String, dynamic>{
            'cronId': 'cron-1',
            'spec': <String, dynamic>{
              'systemPrompt': 'system',
              'content': <Map<String, dynamic>>[
                <String, dynamic>{'type': 'text', 'message': 'drink water'},
              ],
              'modelId': 'gpt-4o',
            },
          }),
        ),
      );

      expect(updateResponse.statusCode, 200);
      final updatePayload =
          jsonDecode(await updateResponse.readAsString())
              as Map<String, dynamic>;
      expect(modelRefStore.refsByCronId['cron-1']?.modelId, 'gpt-4o');
      expect(modelRefStore.refsByCronId['cron-1']?.modelName, 'gpt-4o');
      expect(updatePayload['spec']['modelId'], 'gpt-4o');
      expect(updatePayload['spec']['modelName'], 'gpt-4o');

      kernel.tasksById['cron-1'] = CronTaskDto(
        cronId: 'cron-1',
        name: 'daily reminder',
        schedule: '0 8 * * *',
        source:
            'appkit|owner=com.litevar.agentosChat|group=com.litevar.agentos',
        enabled: true,
        status: 'active',
        concurrency: CronTaskConcurrencyDto.skipIfRunning,
        createdAt: kernel.now,
        updatedAt: kernel.now,
        spec: AgentCronSpecDto(
          systemPrompt: 'system',
          content: <Content>[
            Content(type: ContentType.text, message: 'drink water'),
          ],
          llmConfig: LLMConfig(
            baseUrl: 'https://api.example.com/v1',
            apiKey: 'secret-key',
            model: 'qwen3.5-122b-a10b',
          ),
        ),
      );

      final getResponse = await controller.router.call(
        Request(
          'GET',
          Uri.parse('http://localhost/task?cronId=cron-1'),
          headers: <String, String>{'authorization': 'Bearer $mobileToken'},
        ),
      );

      expect(getResponse.statusCode, 200);
      final getPayload =
          jsonDecode(await getResponse.readAsString()) as Map<String, dynamic>;
      expect(getPayload['spec']['modelId'], 'gpt-4o');
      expect(getPayload['spec']['modelName'], 'gpt-4o');
    });

    test('list tasks returns stored model selection', () async {
      final kernel = _FakeKernelService();
      kernel.tasksById['cron-1'] = CronTaskDto(
        cronId: 'cron-1',
        name: 'desktop task',
        schedule: '* * * * *',
        source:
            'appkit|owner=com.litevar.agentosChat|group=com.litevar.agentos',
        enabled: true,
        status: 'active',
        concurrency: CronTaskConcurrencyDto.skipIfRunning,
        createdAt: kernel.now,
        updatedAt: kernel.now,
        spec: AgentCronSpecDto(
          systemPrompt: 'system',
          content: <Content>[
            Content(type: ContentType.text, message: 'prompt'),
          ],
          llmConfig: LLMConfig(
            baseUrl: 'https://api.example.com/v1',
            apiKey: 'secret-key',
            model: 'qwen3.5-122b-a10b',
          ),
        ),
      );
      await modelRefStore.put(
        CronKitModelRef(
          cronId: 'cron-1',
          modelId: 'gpt-4o',
          modelName: 'gpt-4o',
          bundleId: 'com.litevar.agentosChat',
          appGroupId: 'com.litevar.agentos',
          updatedAt: kernel.now,
        ),
      );
      final controller = CronKitController(
        kernelFuture: Future.value(kernel),
        appKitService: appKitService,
        serviceLocator: serviceLocator,
        modelRefStore: modelRefStore,
      );

      final response = await controller.router.call(
        Request(
          'GET',
          Uri.parse('http://localhost/task/list?limit=100'),
          headers: <String, String>{'authorization': 'Bearer $mobileToken'},
        ),
      );

      expect(response.statusCode, 200);
      final payload =
          jsonDecode(await response.readAsString()) as List<dynamic>;
      expect(payload, hasLength(1));
      expect(payload.first['spec']['modelId'], 'gpt-4o');
      expect(payload.first['spec']['modelName'], 'gpt-4o');
    });

    test('same app group can delete task', () async {
      final kernel = _FakeKernelService();
      kernel.tasksById['cron-1'] = CronTaskDto(
        cronId: 'cron-1',
        name: 'desktop task',
        schedule: '* * * * *',
        source:
            'appkit|owner=com.litevar.agentosChat|group=com.litevar.agentos',
        enabled: true,
        status: 'active',
        concurrency: CronTaskConcurrencyDto.skipIfRunning,
        createdAt: kernel.now,
        updatedAt: kernel.now,
        spec: AgentCronSpecDto(
          systemPrompt: 'system',
          content: <Content>[
            Content(type: ContentType.text, message: 'prompt'),
          ],
        ),
      );
      await modelRefStore.put(
        CronKitModelRef(
          cronId: 'cron-1',
          modelId: 'gpt-4o',
          bundleId: 'com.litevar.agentosChat',
          appGroupId: 'com.litevar.agentos',
          updatedAt: kernel.now,
        ),
      );
      final controller = CronKitController(
        kernelFuture: Future.value(kernel),
        appKitService: appKitService,
        serviceLocator: serviceLocator,
        modelRefStore: modelRefStore,
      );

      final response = await controller.router.call(
        Request(
          'POST',
          Uri.parse('http://localhost/task/delete'),
          headers: <String, String>{
            'authorization': 'Bearer $mobileToken',
            'content-type': 'application/json',
          },
          body: jsonEncode(<String, dynamic>{'cronId': 'cron-1'}),
        ),
      );

      expect(response.statusCode, 200);
      expect(kernel.tasksById.containsKey('cron-1'), isFalse);
      expect(modelRefStore.refsByCronId['cron-1'], isNull);
      final payload =
          jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      expect(payload['deleted'], isTrue);
      expect(payload['cronId'], 'cron-1');
    });

    test('same app group can run task now', () async {
      final kernel = _FakeKernelService();
      kernel.tasksById['cron-1'] = CronTaskDto(
        cronId: 'cron-1',
        name: 'desktop task',
        schedule: '* * * * *',
        source:
            'appkit|owner=com.litevar.agentosChat|group=com.litevar.agentos',
        enabled: true,
        status: 'active',
        concurrency: CronTaskConcurrencyDto.skipIfRunning,
        createdAt: kernel.now,
        updatedAt: kernel.now,
        spec: AgentCronSpecDto(
          systemPrompt: 'system',
          content: <Content>[
            Content(type: ContentType.text, message: 'prompt'),
          ],
        ),
      );
      final controller = CronKitController(
        kernelFuture: Future.value(kernel),
        appKitService: appKitService,
        serviceLocator: serviceLocator,
        modelRefStore: modelRefStore,
      );

      final response = await controller.router.call(
        Request(
          'POST',
          Uri.parse('http://localhost/task/runNow'),
          headers: <String, String>{
            'authorization': 'Bearer $mobileToken',
            'content-type': 'application/json',
          },
          body: jsonEncode(<String, dynamic>{
            'cronId': 'cron-1',
            'scheduledAt': '2026-03-17T12:30:00Z',
          }),
        ),
      );

      expect(response.statusCode, 200);
      final payload =
          jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      expect(payload['runId'], 'run-1');
      expect(payload['cronId'], 'cron-1');
      expect(payload['trigger'], 'manual');
    });

    test('non-displayable run is hidden from external reads', () async {
      final kernel = _FakeKernelService();
      kernel.tasksById['cron-1'] = CronTaskDto(
        cronId: 'cron-1',
        name: 'desktop task',
        schedule: '* * * * *',
        source:
            'appkit|owner=com.litevar.agentosChat|group=com.litevar.agentos',
        enabled: true,
        status: 'active',
        concurrency: CronTaskConcurrencyDto.skipIfRunning,
        createdAt: kernel.now,
        updatedAt: kernel.now,
        spec: AgentCronSpecDto(
          systemPrompt: 'system',
          content: <Content>[
            Content(type: ContentType.text, message: 'prompt'),
          ],
        ),
      );
      kernel.runsById['run-1'] = CronRunDto(
        runId: 'run-1',
        cronId: 'cron-1',
        trigger: 'scheduler',
        status: 'succeeded',
        scheduledAt: kernel.now,
        startedAt: kernel.now,
        hasDisplayableResult: false,
        finishedAt: kernel.now.add(const Duration(minutes: 1)),
        result: const <String, dynamic>{'message': 'done'},
      );
      final controller = CronKitController(
        kernelFuture: Future.value(kernel),
        appKitService: appKitService,
        serviceLocator: serviceLocator,
        modelRefStore: modelRefStore,
      );

      final listResponse = await controller.router.call(
        Request(
          'GET',
          Uri.parse('http://localhost/run/list?limit=100'),
          headers: <String, String>{'authorization': 'Bearer $mobileToken'},
        ),
      );
      final runResponse = await controller.router.call(
        Request(
          'GET',
          Uri.parse('http://localhost/run?runId=run-1'),
          headers: <String, String>{'authorization': 'Bearer $mobileToken'},
        ),
      );
      final messagesResponse = await controller.router.call(
        Request(
          'GET',
          Uri.parse('http://localhost/run/messages?runId=run-1'),
          headers: <String, String>{'authorization': 'Bearer $mobileToken'},
        ),
      );

      expect(listResponse.statusCode, 200);
      final payload =
          jsonDecode(await listResponse.readAsString()) as List<dynamic>;
      expect(payload, isEmpty);
      expect(runResponse.statusCode, 404);
      expect(messagesResponse.statusCode, 404);
    });

    test('run list returns llmConfig and resolved modelId', () async {
      final kernel = _FakeKernelService();
      kernel.tasksById['cron-1'] = CronTaskDto(
        cronId: 'cron-1',
        name: 'desktop task',
        schedule: '* * * * *',
        source:
            'appkit|owner=com.litevar.agentosChat|group=com.litevar.agentos',
        enabled: true,
        status: 'active',
        concurrency: CronTaskConcurrencyDto.skipIfRunning,
        createdAt: kernel.now,
        updatedAt: kernel.now,
        spec: AgentCronSpecDto(
          systemPrompt: 'system',
          content: <Content>[
            Content(type: ContentType.text, message: 'prompt'),
          ],
        ),
      );
      kernel.runsById['run-1'] = CronRunDto(
        runId: 'run-1',
        cronId: 'cron-1',
        trigger: 'scheduler',
        status: 'succeeded',
        scheduledAt: kernel.now,
        startedAt: kernel.now,
        hasDisplayableResult: true,
        finishedAt: kernel.now.add(const Duration(minutes: 1)),
        llmConfig: LLMConfig(
          baseUrl: 'https://api.example.com/v1',
          apiKey: 'secret-key',
          model: 'gpt-4o',
          contextWindowSize: 128000,
        ),
        displayText: 'done',
      );
      await modelRefStore.put(
        CronKitModelRef(
          cronId: 'cron-1',
          modelId: 'gpt-4o-id',
          modelName: 'gpt-4o',
          bundleId: 'com.litevar.agentosChat',
          appGroupId: 'com.litevar.agentos',
          updatedAt: kernel.now,
        ),
      );
      final controller = CronKitController(
        kernelFuture: Future.value(kernel),
        appKitService: appKitService,
        serviceLocator: serviceLocator,
        modelRefStore: modelRefStore,
      );

      final response = await controller.router.call(
        Request(
          'GET',
          Uri.parse('http://localhost/run/list?limit=100'),
          headers: <String, String>{'authorization': 'Bearer $mobileToken'},
        ),
      );

      expect(response.statusCode, 200);
      final payload =
          jsonDecode(await response.readAsString()) as List<dynamic>;
      expect(payload, hasLength(1));
      expect(payload.first['modelId'], 'gpt-4o-id');
      expect(payload.first.containsKey('llmConfig'), isFalse);
    });

    test(
      'get task returns stored modelId without exposing llmConfig',
      () async {
        final kernel = _FakeKernelService();
        kernel.tasksById['cron-1'] = CronTaskDto(
          cronId: 'cron-1',
          name: 'desktop task',
          schedule: '* * * * *',
          source:
              'appkit|owner=com.litevar.agentosChat|group=com.litevar.agentos',
          enabled: true,
          status: 'active',
          concurrency: CronTaskConcurrencyDto.skipIfRunning,
          createdAt: kernel.now,
          updatedAt: kernel.now,
          spec: AgentCronSpecDto(
            systemPrompt: 'system',
            content: <Content>[
              Content(type: ContentType.text, message: 'prompt'),
            ],
            llmConfig: LLMConfig(
              baseUrl: 'https://api.example.com/v1',
              apiKey: 'secret-key',
              model: 'gpt-4o',
              contextWindowSize: 128000,
            ),
          ),
        );
        await modelRefStore.put(
          CronKitModelRef(
            cronId: 'cron-1',
            modelId: 'gpt-4o',
            bundleId: 'com.litevar.agentosChat',
            appGroupId: 'com.litevar.agentos',
            updatedAt: kernel.now,
          ),
        );
        final controller = CronKitController(
          kernelFuture: Future.value(kernel),
          appKitService: appKitService,
          serviceLocator: serviceLocator,
          modelRefStore: modelRefStore,
        );

        final response = await controller.router.call(
          Request(
            'GET',
            Uri.parse('http://localhost/task?cronId=cron-1'),
            headers: <String, String>{'authorization': 'Bearer $mobileToken'},
          ),
        );

        expect(response.statusCode, 200);
        final payload =
            jsonDecode(await response.readAsString()) as Map<String, dynamic>;
        expect(payload['spec']['modelId'], 'gpt-4o');
        expect(payload['spec']['modelName'], 'gpt-4o');
        expect(payload['spec'].containsKey('llmConfig'), isFalse);
      },
    );
  });
}
