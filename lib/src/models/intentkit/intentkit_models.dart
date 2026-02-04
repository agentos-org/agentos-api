import 'package:agentos_kernel/agentos_kernel.dart';
import 'package:liteagent_sdk_dart/liteagent_sdk_dart.dart';

class IntentKitSubmitRawRequest {
  final String source;
  final List<Content> content;
  final Map<String, dynamic>? data;

  IntentKitSubmitRawRequest({
    required this.source,
    required this.content,
    this.data,
  });

  factory IntentKitSubmitRawRequest.fromJson(Map<String, dynamic> json) {
    final sourceValue = (json['source'] ?? KernelSources.api).toString();
    final content = _parseContent(json['content']);
    if (content == null) {
      throw FormatException('content must be a non-empty array');
    }
    final data = _parseData(json['data']);
    return IntentKitSubmitRawRequest(
      source: sourceValue,
      content: content,
      data: data,
    );
  }

  static List<Content>? _parseContent(dynamic raw) {
    if (raw is! List) {
      return null;
    }
    final items = <Content>[];
    for (final item in raw) {
      if (item is Map<String, dynamic>) {
        items.add(Content.fromJson(item));
      } else if (item is Map) {
        items.add(Content.fromJson(Map<String, dynamic>.from(item)));
      } else {
        return null;
      }
    }
    if (items.isEmpty) {
      return null;
    }
    return items;
  }

  static Map<String, dynamic>? _parseData(dynamic raw) {
    if (raw == null) {
      return null;
    }
    if (raw is Map<String, dynamic>) {
      return raw;
    }
    if (raw is Map) {
      return Map<String, dynamic>.from(raw);
    }
    return null;
  }
}

class IntentKitSubmitIntentRequest {
  final String source;
  final IntentCandidateDto intent;

  IntentKitSubmitIntentRequest({
    required this.source,
    required this.intent,
  });

  factory IntentKitSubmitIntentRequest.fromJson(Map<String, dynamic> json) {
    final sourceValue = (json['source'] ?? KernelSources.api).toString();
    final intentRaw = json['intent'];
    if (intentRaw is! Map) {
      throw FormatException('intent must be an object');
    }
    final intentMap = intentRaw is Map<String, dynamic>
        ? intentRaw
        : Map<String, dynamic>.from(intentRaw);
    final intent = IntentCandidateDto.fromJson(intentMap);
    return IntentKitSubmitIntentRequest(
      source: sourceValue,
      intent: intent,
    );
  }
}

class IntentKitConfirmJobRequest {
  final String jobId;
  final bool confirmed;

  const IntentKitConfirmJobRequest({
    required this.jobId,
    required this.confirmed,
  });

  factory IntentKitConfirmJobRequest.fromJson(Map<String, dynamic> json) {
    final jobIdValue = json['jobId'];
    final confirmedValue = json['confirmed'];
    if (jobIdValue is! String || jobIdValue.trim().isEmpty) {
      throw FormatException('jobId is required');
    }
    if (confirmedValue is! bool) {
      throw FormatException('confirmed must be a boolean');
    }
    return IntentKitConfirmJobRequest(
      jobId: jobIdValue,
      confirmed: confirmedValue,
    );
  }
}

class IntentKitSuggestNextActionRequest {
  final String source;
  final List<String>? allowedActions;
  final int? memoryLimit;

  const IntentKitSuggestNextActionRequest({
    required this.source,
    this.allowedActions,
    this.memoryLimit,
  });

  factory IntentKitSuggestNextActionRequest.fromJson(
    Map<String, dynamic> json,
  ) {
    final sourceValue = (json['source'] ?? KernelSources.api).toString();
    final allowedActions = _parseStringList(json['allowedActions']);
    final memoryLimit = _parseMemoryLimit(json['memoryLimit']);
    return IntentKitSuggestNextActionRequest(
      source: sourceValue,
      allowedActions: allowedActions,
      memoryLimit: memoryLimit,
    );
  }

  static List<String>? _parseStringList(dynamic raw) {
    if (raw == null) {
      return null;
    }
    if (raw is! List) {
      throw FormatException('allowedActions must be an array of strings');
    }
    final items = <String>[];
    for (final item in raw) {
      if (item is! String) {
        throw FormatException('allowedActions must be an array of strings');
      }
      items.add(item);
    }
    return items;
  }

  static int? _parseMemoryLimit(dynamic raw) {
    if (raw == null) {
      return null;
    }
    if (raw is int) {
      return raw;
    }
    if (raw is num) {
      return raw.toInt();
    }
    throw FormatException('memoryLimit must be a number');
  }
}

class IntentKitJobHandleDto {
  final String jobId;
  final String status;

  const IntentKitJobHandleDto({
    required this.jobId,
    required this.status,
  });

  factory IntentKitJobHandleDto.fromHandle(JobHandle handle) {
    return IntentKitJobHandleDto(
      jobId: handle.jobId,
      status: handle.status.name,
    );
  }

  Map<String, dynamic> toJson() => {
        'jobId': jobId,
        'status': status,
      };
}
