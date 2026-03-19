import 'package:agentos_kernel/agentos_kernel.dart';
import 'package:liteagent_sdk_dart/liteagent_sdk_dart.dart';

class CronKitAgentCronSpecInput {
  const CronKitAgentCronSpecInput({
    required this.systemPrompt,
    required this.content,
    this.timeoutSeconds = 3600,
    this.modelId,
  });

  final String systemPrompt;
  final List<Content> content;
  final int timeoutSeconds;
  final String? modelId;

  AgentCronSpecDto toKernelDto({LLMConfig? llmConfig}) {
    return AgentCronSpecDto(
      systemPrompt: systemPrompt,
      content: content,
      timeoutSeconds: timeoutSeconds,
      llmConfig: llmConfig,
    );
  }
}

class CronKitCreateTaskRequest {
  const CronKitCreateTaskRequest({
    required this.name,
    required this.schedule,
    required this.spec,
    required this.source,
    this.userId,
    this.sessionId,
    this.timezone,
    this.concurrency = CronTaskConcurrencyDto.skipIfRunning,
    this.enabled = true,
  });

  final String name;
  final String schedule;
  final CronKitAgentCronSpecInput spec;
  final String source;
  final String? userId;
  final String? sessionId;
  final String? timezone;
  final CronTaskConcurrencyDto concurrency;
  final bool enabled;

  factory CronKitCreateTaskRequest.fromJson(Map<String, dynamic> json) {
    final name = _requiredString(json['name'], 'name');
    final schedule = _requiredString(json['schedule'], 'schedule');
    final spec = _parseCronSpec(json['spec']);
    final source = (json['source'] ?? KernelSources.api).toString();
    return CronKitCreateTaskRequest(
      name: name,
      schedule: schedule,
      spec: spec,
      source: source,
      userId: _optionalString(json['userId']),
      sessionId: _optionalString(json['sessionId']),
      timezone: _optionalString(json['timezone']),
      concurrency: _parseConcurrency(
        json['concurrency'],
        defaultValue: CronTaskConcurrencyDto.skipIfRunning,
      ),
      enabled: _parseBool(json['enabled'], defaultValue: true),
    );
  }
}

class CronKitUpdateTaskRequest {
  const CronKitUpdateTaskRequest({
    required this.cronId,
    this.name,
    this.schedule,
    this.spec,
    this.timezone,
    this.concurrency,
    this.enabled,
  });

  final String cronId;
  final String? name;
  final String? schedule;
  final CronKitAgentCronSpecInput? spec;
  final String? timezone;
  final CronTaskConcurrencyDto? concurrency;
  final bool? enabled;

  factory CronKitUpdateTaskRequest.fromJson(Map<String, dynamic> json) {
    return CronKitUpdateTaskRequest(
      cronId: _requiredString(json['cronId'], 'cronId'),
      name: _optionalString(json['name']),
      schedule: _optionalString(json['schedule']),
      spec: json['spec'] == null ? null : _parseCronSpec(json['spec']),
      timezone: _optionalString(json['timezone']),
      concurrency: json['concurrency'] == null
          ? null
          : _parseConcurrency(json['concurrency']),
      enabled: json['enabled'] == null ? null : _parseBool(json['enabled']),
    );
  }
}

class CronKitCronIdRequest {
  const CronKitCronIdRequest({required this.cronId});

  final String cronId;

  factory CronKitCronIdRequest.fromJson(Map<String, dynamic> json) {
    return CronKitCronIdRequest(
      cronId: _requiredString(json['cronId'], 'cronId'),
    );
  }
}

class CronKitSetTaskEnabledRequest {
  const CronKitSetTaskEnabledRequest({
    required this.cronId,
    required this.enabled,
  });

  final String cronId;
  final bool enabled;

  factory CronKitSetTaskEnabledRequest.fromJson(Map<String, dynamic> json) {
    return CronKitSetTaskEnabledRequest(
      cronId: _requiredString(json['cronId'], 'cronId'),
      enabled: _parseBool(json['enabled']),
    );
  }
}

class CronKitRunIdRequest {
  const CronKitRunIdRequest({required this.runId});

  final String runId;

  factory CronKitRunIdRequest.fromQuery(Map<String, String> query) {
    return CronKitRunIdRequest(runId: _requiredString(query['runId'], 'runId'));
  }

  factory CronKitRunIdRequest.fromJson(Map<String, dynamic> json) {
    return CronKitRunIdRequest(runId: _requiredString(json['runId'], 'runId'));
  }
}

class CronKitRunNowRequest {
  const CronKitRunNowRequest({required this.cronId, this.scheduledAt});

  final String cronId;
  final DateTime? scheduledAt;

  factory CronKitRunNowRequest.fromJson(Map<String, dynamic> json) {
    return CronKitRunNowRequest(
      cronId: _requiredString(json['cronId'], 'cronId'),
      scheduledAt: _parseDateTime(json['scheduledAt'], 'scheduledAt'),
    );
  }
}

class CronKitTaskDto {
  const CronKitTaskDto({
    required this.cronId,
    required this.name,
    required this.schedule,
    required this.source,
    required this.enabled,
    required this.status,
    required this.concurrency,
    required this.createdAt,
    required this.updatedAt,
    required this.spec,
    this.userId,
    this.sessionId,
    this.timezone,
    this.lastRunAt,
    this.nextRunAt,
  });

  final String cronId;
  final String name;
  final String schedule;
  final String source;
  final String? userId;
  final String? sessionId;
  final String? timezone;
  final bool enabled;
  final String status;
  final String concurrency;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? lastRunAt;
  final DateTime? nextRunAt;
  final Map<String, dynamic> spec;

  factory CronKitTaskDto.fromKernel(CronTaskDto dto, {String? modelId}) {
    return CronKitTaskDto(
      cronId: dto.cronId,
      name: dto.name,
      schedule: dto.schedule,
      source: dto.source,
      userId: dto.userId,
      sessionId: dto.sessionId,
      timezone: dto.timezone,
      enabled: dto.enabled,
      status: dto.status,
      concurrency: dto.concurrency.name,
      createdAt: dto.createdAt,
      updatedAt: dto.updatedAt,
      lastRunAt: dto.lastRunAt,
      nextRunAt: dto.nextRunAt,
      spec: _cronSpecToJson(dto.spec, modelId: modelId),
    );
  }

  Map<String, dynamic> toJson() => {
    'cronId': cronId,
    'name': name,
    'schedule': schedule,
    'source': source,
    'userId': userId,
    'sessionId': sessionId,
    'timezone': timezone,
    'enabled': enabled,
    'status': status,
    'concurrency': concurrency,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'lastRunAt': lastRunAt?.toIso8601String(),
    'nextRunAt': nextRunAt?.toIso8601String(),
    'spec': spec,
  };
}

class CronKitTaskListItemDto {
  const CronKitTaskListItemDto({
    required this.cronId,
    required this.name,
    required this.schedule,
    required this.enabled,
    required this.status,
    this.lastRunAt,
    this.nextRunAt,
  });

  final String cronId;
  final String name;
  final String schedule;
  final bool enabled;
  final String status;
  final DateTime? lastRunAt;
  final DateTime? nextRunAt;

  factory CronKitTaskListItemDto.fromKernel(CronTaskListItemDto dto) {
    return CronKitTaskListItemDto(
      cronId: dto.cronId,
      name: dto.name,
      schedule: dto.schedule,
      enabled: dto.enabled,
      status: dto.status,
      lastRunAt: dto.lastRunAt,
      nextRunAt: dto.nextRunAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'cronId': cronId,
    'name': name,
    'schedule': schedule,
    'enabled': enabled,
    'status': status,
    'lastRunAt': lastRunAt?.toIso8601String(),
    'nextRunAt': nextRunAt?.toIso8601String(),
  };
}

class CronKitRunDto {
  const CronKitRunDto({
    required this.runId,
    required this.cronId,
    required this.trigger,
    required this.status,
    required this.scheduledAt,
    required this.startedAt,
    required this.hasDisplayableResult,
    this.finishedAt,
    this.liteAgentSessionId,
    this.error,
    this.result,
    this.displayMessageId,
    this.displayText,
  });

  final String runId;
  final String cronId;
  final String trigger;
  final String status;
  final DateTime scheduledAt;
  final DateTime startedAt;
  final bool hasDisplayableResult;
  final DateTime? finishedAt;
  final String? liteAgentSessionId;
  final String? error;
  final Map<String, dynamic>? result;
  final String? displayMessageId;
  final String? displayText;

  factory CronKitRunDto.fromKernel(CronRunDto dto) {
    return CronKitRunDto(
      runId: dto.runId,
      cronId: dto.cronId,
      trigger: dto.trigger,
      status: dto.status,
      scheduledAt: dto.scheduledAt,
      startedAt: dto.startedAt,
      hasDisplayableResult: dto.hasDisplayableResult,
      finishedAt: dto.finishedAt,
      liteAgentSessionId: dto.liteAgentSessionId,
      error: dto.error,
      result: dto.result,
      displayMessageId: dto.displayMessageId,
      displayText: dto.displayText,
    );
  }

  Map<String, dynamic> toJson() => {
    'runId': runId,
    'cronId': cronId,
    'trigger': trigger,
    'status': status,
    'scheduledAt': scheduledAt.toIso8601String(),
    'startedAt': startedAt.toIso8601String(),
    'hasDisplayableResult': hasDisplayableResult,
    'finishedAt': finishedAt?.toIso8601String(),
    'liteAgentSessionId': liteAgentSessionId,
    'error': error,
    'result': result,
    'displayMessageId': displayMessageId,
    'displayText': displayText,
  };
}

class CronKitRunListItemDto {
  const CronKitRunListItemDto({
    required this.runId,
    required this.cronId,
    required this.trigger,
    required this.status,
    required this.scheduledAt,
    required this.startedAt,
    required this.hasDisplayableResult,
    this.finishedAt,
    this.displayText,
  });

  final String runId;
  final String cronId;
  final String trigger;
  final String status;
  final DateTime scheduledAt;
  final DateTime startedAt;
  final bool hasDisplayableResult;
  final DateTime? finishedAt;
  final String? displayText;

  factory CronKitRunListItemDto.fromKernel(CronRunListItemDto dto) {
    return CronKitRunListItemDto(
      runId: dto.runId,
      cronId: dto.cronId,
      trigger: dto.trigger,
      status: dto.status,
      scheduledAt: dto.scheduledAt,
      startedAt: dto.startedAt,
      hasDisplayableResult: dto.hasDisplayableResult,
      finishedAt: dto.finishedAt,
      displayText: dto.displayText,
    );
  }

  Map<String, dynamic> toJson() => {
    'runId': runId,
    'cronId': cronId,
    'trigger': trigger,
    'status': status,
    'scheduledAt': scheduledAt.toIso8601String(),
    'startedAt': startedAt.toIso8601String(),
    'hasDisplayableResult': hasDisplayableResult,
    'finishedAt': finishedAt?.toIso8601String(),
    'displayText': displayText,
  };
}

class CronKitRunMessageDto {
  const CronKitRunMessageDto({
    required this.messageId,
    required this.runId,
    required this.cronId,
    required this.timestamp,
    required this.message,
  });

  final String messageId;
  final String runId;
  final String cronId;
  final DateTime timestamp;
  final Map<String, dynamic> message;

  factory CronKitRunMessageDto.fromKernel(CronRunMessageDto dto) {
    return CronKitRunMessageDto(
      messageId: dto.messageId,
      runId: dto.runId,
      cronId: dto.cronId,
      timestamp: dto.timestamp,
      message: dto.message.toJson(),
    );
  }

  Map<String, dynamic> toJson() => {
    'messageId': messageId,
    'runId': runId,
    'cronId': cronId,
    'timestamp': timestamp.toIso8601String(),
    'message': message,
  };
}

String _requiredString(Object? value, String fieldName) {
  final text = value?.toString().trim() ?? '';
  if (text.isEmpty) {
    throw FormatException('$fieldName is required');
  }
  return text;
}

String? _optionalString(Object? value) {
  if (value == null) {
    return null;
  }
  final text = value.toString().trim();
  return text.isEmpty ? null : text;
}

bool _parseBool(Object? value, {bool? defaultValue}) {
  if (value == null) {
    if (defaultValue != null) {
      return defaultValue;
    }
    throw const FormatException('boolean value is required');
  }
  if (value is bool) {
    return value;
  }
  if (value is String) {
    switch (value.trim().toLowerCase()) {
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
    }
  }
  throw const FormatException('boolean value is invalid');
}

DateTime? _parseDateTime(Object? value, String fieldName) {
  if (value == null) {
    return null;
  }
  if (value is String && value.trim().isNotEmpty) {
    final parsed = DateTime.tryParse(value);
    if (parsed == null) {
      throw FormatException('$fieldName must be an ISO-8601 datetime string');
    }
    return parsed;
  }
  throw FormatException('$fieldName must be an ISO-8601 datetime string');
}

int _parseInt(Object? value, {int? defaultValue}) {
  if (value == null) {
    if (defaultValue != null) {
      return defaultValue;
    }
    throw const FormatException('number value is required');
  }
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    final parsed = int.tryParse(value.trim());
    if (parsed != null) {
      return parsed;
    }
  }
  throw const FormatException('number value is invalid');
}

CronTaskConcurrencyDto _parseConcurrency(
  Object? value, {
  CronTaskConcurrencyDto? defaultValue,
}) {
  if (value == null) {
    if (defaultValue != null) {
      return defaultValue;
    }
    throw const FormatException('concurrency is required');
  }
  final raw = value.toString().trim();
  for (final candidate in CronTaskConcurrencyDto.values) {
    if (candidate.name == raw) {
      return candidate;
    }
  }
  throw FormatException('Unsupported concurrency: $raw');
}

CronKitAgentCronSpecInput _parseCronSpec(Object? value) {
  if (value is! Map) {
    throw const FormatException('spec must be an object');
  }
  final json = value is Map<String, dynamic>
      ? value
      : Map<String, dynamic>.from(value);
  return CronKitAgentCronSpecInput(
    systemPrompt: _requiredString(json['systemPrompt'], 'spec.systemPrompt'),
    content: _parseContentList(json['content']),
    timeoutSeconds: _parseInt(json['timeoutSeconds'], defaultValue: 3600),
    modelId: _optionalString(json['modelId']),
  );
}

List<Content> _parseContentList(Object? value) {
  if (value is! List || value.isEmpty) {
    throw const FormatException('spec.content must be a non-empty array');
  }
  return value
      .map((item) {
        if (item is Map<String, dynamic>) {
          return Content.fromJson(item);
        }
        if (item is Map) {
          return Content.fromJson(Map<String, dynamic>.from(item));
        }
        throw const FormatException('spec.content items must be objects');
      })
      .toList(growable: false);
}

Map<String, dynamic> _cronSpecToJson(AgentCronSpecDto spec, {String? modelId}) {
  final result = <String, dynamic>{
    'systemPrompt': spec.systemPrompt,
    'content': spec.content
        .map((item) => item.toJson())
        .toList(growable: false),
    'timeoutSeconds': spec.timeoutSeconds,
  };
  final normalizedModelId = modelId?.trim();
  if (normalizedModelId != null && normalizedModelId.isNotEmpty) {
    result['modelId'] = normalizedModelId;
  }
  final modelName = spec.llmConfig?.model;
  if (modelName != null && modelName.trim().isNotEmpty) {
    result['modelName'] = modelName;
  }
  return result;
}
