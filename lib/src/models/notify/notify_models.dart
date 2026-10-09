/// Public NotifyKit request and response models.
library;

enum NotifyKitLevel { info, success, warning, error }

/// The only event fields an App is allowed to provide to NotifyKit.
///
/// Grouping, deduplication, rate limiting and presentation priority are
/// deliberately not part of this model. They are platform policy decisions.
class NotifyKitAppEvent {
  const NotifyKitAppEvent({
    required this.eventType,
    required this.title,
    required this.message,
    this.subjectId,
  });

  final String eventType;
  final String title;
  final String message;
  final String? subjectId;
}

class NotifyKitNotification {
  const NotifyKitNotification({
    required this.id,
    required this.source,
    required this.sourceType,
    required this.eventType,
    required this.category,
    required this.title,
    required this.message,
    required this.level,
    required this.createdAt,
    required this.updatedAt,
    required this.count,
    this.subjectId,
  });

  final String id;
  final String source;
  final String sourceType;
  final String eventType;
  final String category;
  final String title;
  final String message;
  final NotifyKitLevel level;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int count;
  final String? subjectId;

  NotifyKitNotification copyWith({
    String? title,
    String? message,
    NotifyKitLevel? level,
    DateTime? updatedAt,
    int? count,
  }) {
    return NotifyKitNotification(
      id: id,
      source: source,
      sourceType: sourceType,
      eventType: eventType,
      category: category,
      title: title ?? this.title,
      message: message ?? this.message,
      level: level ?? this.level,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      count: count ?? this.count,
      subjectId: subjectId,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'source': source,
    'sourceType': sourceType,
    'eventType': eventType,
    'category': category,
    'title': title,
    'message': message,
    'level': level.name,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'count': count,
    if (subjectId != null) 'subjectId': subjectId,
  };
}

class NotifyKitGroup {
  const NotifyKitGroup({
    required this.id,
    required this.source,
    required this.category,
    required this.title,
    required this.message,
    required this.level,
    required this.updatedAt,
    required this.itemCount,
    required this.eventCount,
    required this.items,
  });

  final String id;
  final String source;
  final String category;
  final String title;
  final String message;
  final NotifyKitLevel level;
  final DateTime updatedAt;
  final int itemCount;
  final int eventCount;
  final List<NotifyKitNotification> items;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'source': source,
    'category': category,
    'title': title,
    'message': message,
    'level': level.name,
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'itemCount': itemCount,
    'eventCount': eventCount,
    'items': [for (final item in items) item.toJson()],
  };
}

class NotifyKitSnapshot {
  const NotifyKitSnapshot({required this.groups, required this.lastSeenAt});

  final List<NotifyKitGroup> groups;
  final DateTime? lastSeenAt;

  bool get hasUnread {
    final seenAt = lastSeenAt;
    if (seenAt == null) return groups.isNotEmpty;
    return groups.any((group) => group.updatedAt.isAfter(seenAt));
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'hasUnread': hasUnread,
    if (lastSeenAt != null) 'lastSeenAt': lastSeenAt!.toUtc().toIso8601String(),
    'groups': [for (final group in groups) group.toJson()],
  };
}
