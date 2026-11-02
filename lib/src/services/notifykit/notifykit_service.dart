import 'dart:async';

import 'package:unique_id_dart/unique_id_dart.dart';

import '../../models/notify/notify_models.dart';

class NotifyKitRateLimitException implements Exception {
  const NotifyKitRateLimitException(this.source, this.retryAfterSeconds);

  final String source;
  final int retryAfterSeconds;

  @override
  String toString() =>
      'NotifyKit rate limit exceeded for $source; retry after '
      '$retryAfterSeconds seconds';
}

/// Platform-owned notification policy and in-memory notification center.
///
/// Apps only provide event content. This service owns the grouping key,
/// deduplication key, level policy, history bound and per-source rate limit.
class NotifyKitService {
  NotifyKitService({
    DateTime Function()? clock,
    this.maxHistory = 512,
    this.maxGroupsPerSource = 4,
    this.maxEventsPerSourcePerMinute = 30,
    this.deduplicationWindow = const Duration(seconds: 30),
  }) : _clock = clock ?? DateTime.now;

  static const Set<String> _knownCategories = <String>{
    'auth',
    'chat',
    'download',
    'model',
    'service',
    'sync',
    'task',
    'transfer',
    'update',
  };

  final DateTime Function() _clock;
  final int maxHistory;
  final int maxGroupsPerSource;
  final int maxEventsPerSourcePerMinute;
  final Duration deduplicationWindow;
  final List<NotifyKitNotification> _items = <NotifyKitNotification>[];
  final Map<String, List<DateTime>> _sourceEvents = <String, List<DateTime>>{};
  final StreamController<NotifyKitSnapshot> _events =
      StreamController<NotifyKitSnapshot>.broadcast();
  final StreamController<NotifyKitNotification> _published =
      StreamController<NotifyKitNotification>.broadcast();
  DateTime? _lastSeenAt;
  bool _disposed = false;

  Stream<NotifyKitSnapshot> get stream => _events.stream;

  /// Emits every accepted publication (a new record or a folded repeat) as the
  /// platform-owned record. Unlike [stream], this carries exactly the delta,
  /// so shell presenters (for example native OS notifications) do not need to
  /// diff snapshots. It is a broadcast stream without replay.
  Stream<NotifyKitNotification> get published => _published.stream;

  NotifyKitSnapshot snapshot({int limit = 100}) {
    final groups = _buildGroups();
    final boundedLimit = limit.clamp(1, 100).toInt();
    return NotifyKitSnapshot(
      groups: List<NotifyKitGroup>.unmodifiable(groups.take(boundedLimit)),
      lastSeenAt: _lastSeenAt,
    );
  }

  /// Publishes an App event after applying the platform App policy.
  NotifyKitNotification publishApp({
    required String bundleId,
    required NotifyKitAppEvent event,
  }) {
    final source = _boundedRequired(bundleId, 160, 'bundleId');
    _checkRateLimit(source);
    final normalized = _normalizeEvent(event);
    final category = _categoryFor(normalized.eventType);
    final level = _levelForAppEvent(normalized.eventType);
    final groupCategory = _groupCategoryFor(source, category);
    return _publish(
      source: source,
      sourceType: 'app',
      eventType: normalized.eventType,
      subjectId: normalized.subjectId,
      title: normalized.title,
      message: normalized.message,
      level: level,
      category: groupCategory,
    );
  }

  /// Publishes a trusted system/runtime event. Only platform code should call
  /// this method; Apps are routed through [publishApp] and cannot set [level].
  NotifyKitNotification publishSystem({
    required String source,
    required String eventType,
    required String title,
    required String message,
    NotifyKitLevel level = NotifyKitLevel.info,
    String? subjectId,
  }) {
    final normalizedSource = _boundedRequired(source, 160, 'source');
    final normalizedEventType = _boundedRequired(eventType, 80, 'eventType');
    return _publish(
      source: normalizedSource,
      sourceType: 'system',
      eventType: normalizedEventType,
      subjectId: _boundedOptional(subjectId, 256),
      title: _boundedRequired(title, 180, 'title'),
      message: _boundedRequired(message, 4000, 'message'),
      level: level,
      category: normalizedSource == 'runtime'
          ? 'runtime'
          : _categoryFor(normalizedEventType),
    );
  }

  NotifyKitSnapshot markSeen() {
    _lastSeenAt = _clock().toUtc();
    final result = snapshot();
    _emit(result);
    return result;
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _events.close();
    await _published.close();
  }

  NotifyKitNotification _publish({
    required String source,
    required String sourceType,
    required String eventType,
    required String? subjectId,
    required String title,
    required String message,
    required NotifyKitLevel level,
    required String category,
  }) {
    final now = _clock().toUtc();
    final existingIndex = _findDeduplicationCandidate(
      source: source,
      sourceType: sourceType,
      eventType: eventType,
      subjectId: subjectId,
      title: title,
      message: message,
      now: now,
    );

    late final NotifyKitNotification notification;
    if (existingIndex == null) {
      notification = NotifyKitNotification(
        id: 'ntf-${uniqueId(shorter: true)}',
        source: source,
        sourceType: sourceType,
        eventType: eventType,
        category: category,
        title: title,
        message: message,
        level: level,
        createdAt: now,
        updatedAt: now,
        count: 1,
        subjectId: subjectId,
      );
      _items.add(notification);
    } else {
      final old = _items[existingIndex];
      notification = old.copyWith(
        title: title,
        message: message,
        level: _moreSevere(old.level, level),
        updatedAt: now,
        count: old.count + 1,
      );
      _items[existingIndex] = notification;
    }

    _items.sort((a, b) => a.updatedAt.compareTo(b.updatedAt));
    while (_items.length > maxHistory) {
      _items.removeAt(0);
    }
    _emit(snapshot());
    if (!_disposed && !_published.isClosed) _published.add(notification);
    return notification;
  }

  int? _findDeduplicationCandidate({
    required String source,
    required String sourceType,
    required String eventType,
    required String? subjectId,
    required String title,
    required String message,
    required DateTime now,
  }) {
    for (var index = _items.length - 1; index >= 0; index--) {
      final item = _items[index];
      if (item.source != source ||
          item.sourceType != sourceType ||
          item.eventType != eventType) {
        continue;
      }
      if (subjectId != null && subjectId.isNotEmpty) {
        if (item.subjectId == subjectId) return index;
        continue;
      }
      if (now.difference(item.updatedAt) > deduplicationWindow) break;
      if (_fingerprint(item.title, item.message) ==
          _fingerprint(title, message)) {
        return index;
      }
    }
    return null;
  }

  void _checkRateLimit(String source) {
    final now = _clock().toUtc();
    final events = _sourceEvents.putIfAbsent(source, () => <DateTime>[]);
    events.removeWhere(
      (time) => now.difference(time) >= const Duration(minutes: 1),
    );
    if (events.length >= maxEventsPerSourcePerMinute) {
      final retryAfter = events.isEmpty
          ? 1
          : mathMax(
              1,
              const Duration(minutes: 1).inSeconds -
                  now.difference(events.first).inSeconds,
            );
      throw NotifyKitRateLimitException(source, retryAfter);
    }
    events.add(now);
  }

  List<NotifyKitGroup> _buildGroups() {
    final grouped = <String, List<NotifyKitNotification>>{};
    for (final item in _items) {
      final key = '${item.source}::${item.category}';
      grouped.putIfAbsent(key, () => <NotifyKitNotification>[]).add(item);
    }

    final result = <NotifyKitGroup>[];
    for (final entry in grouped.entries) {
      final items = entry.value.toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      final latest = items.first;
      result.add(
        NotifyKitGroup(
          id: entry.key,
          source: latest.source,
          category: latest.category,
          title: latest.title,
          message: latest.message,
          level: items.fold<NotifyKitLevel>(
            NotifyKitLevel.info,
            (current, item) => _moreSevere(current, item.level),
          ),
          updatedAt: latest.updatedAt,
          itemCount: items.length,
          eventCount: items.fold<int>(0, (sum, item) => sum + item.count),
          items: List.unmodifiable(items),
        ),
      );
    }
    result.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return result;
  }

  String _groupCategoryFor(String source, String category) {
    if (category == 'other') return category;
    final existing = <String>{
      for (final item in _items)
        if (item.source == source) item.category,
    };
    if (existing.contains(category)) return category;
    // Reserve one bounded bucket for unknown/overflow events. This keeps the
    // total number of top-level groups capped even when an App deliberately
    // cycles through many event namespaces.
    final knownGroupCount = existing.where((item) => item != 'other').length;
    final maxKnownGroups = mathMax(0, maxGroupsPerSource - 1);
    if (knownGroupCount < maxKnownGroups) return category;
    return 'other';
  }

  static NotifyKitLevel _levelForAppEvent(String eventType) {
    // Only platform-defined event names receive a non-neutral visual level.
    // An App cannot manufacture a high-urgency event by appending `.error` or
    // `.warning` to an arbitrary namespace.
    const appEventLevels = <String, NotifyKitLevel>{
      'task.completed': NotifyKitLevel.success,
      'task.succeeded': NotifyKitLevel.success,
      'task.failed': NotifyKitLevel.warning,
      'task.error': NotifyKitLevel.warning,
      'download.completed': NotifyKitLevel.success,
      'download.succeeded': NotifyKitLevel.success,
      'download.failed': NotifyKitLevel.warning,
      'download.error': NotifyKitLevel.warning,
      'sync.completed': NotifyKitLevel.success,
      'sync.succeeded': NotifyKitLevel.success,
      'sync.failed': NotifyKitLevel.warning,
      'sync.error': NotifyKitLevel.warning,
    };
    return appEventLevels[eventType] ?? NotifyKitLevel.info;
  }

  static NotifyKitLevel _moreSevere(
    NotifyKitLevel first,
    NotifyKitLevel second,
  ) {
    int rank(NotifyKitLevel level) => switch (level) {
      NotifyKitLevel.info => 0,
      NotifyKitLevel.success => 1,
      NotifyKitLevel.warning => 2,
      NotifyKitLevel.error => 3,
    };
    return rank(second) > rank(first) ? second : first;
  }

  static String _categoryFor(String eventType) {
    final first = eventType.split('.').first.toLowerCase();
    return _knownCategories.contains(first) ? first : 'other';
  }

  static NotifyKitAppEvent _normalizeEvent(NotifyKitAppEvent event) {
    final eventType = _boundedRequired(
      event.eventType,
      80,
      'eventType',
    ).toLowerCase();
    if (!RegExp(r'^[a-z][a-z0-9_-]*(?:\.[a-z0-9_-]+)*$').hasMatch(eventType)) {
      throw const FormatException('eventType must be a dotted lowercase name');
    }
    return NotifyKitAppEvent(
      eventType: eventType,
      title: _boundedRequired(event.title, 180, 'title'),
      message: _boundedRequired(event.message, 4000, 'message'),
      subjectId: _boundedOptional(event.subjectId, 256),
    );
  }

  static String _fingerprint(String title, String message) =>
      '${title.trim().toLowerCase()}\u0000${message.trim().toLowerCase()}';

  static String _boundedRequired(String value, int maximum, String field) {
    final normalized = value.trim();
    if (normalized.isEmpty ||
        normalized.length > maximum ||
        _hasControl(normalized)) {
      throw FormatException('$field is invalid');
    }
    return normalized;
  }

  static String? _boundedOptional(String? value, int maximum) {
    if (value == null) return null;
    final normalized = value.trim();
    if (normalized.isEmpty) return null;
    if (normalized.length > maximum || _hasControl(normalized)) {
      throw const FormatException('optional notification field is invalid');
    }
    return normalized;
  }

  static bool _hasControl(String value) => value.codeUnits.any(
    (unit) => unit < 0x20 && unit != 0x09 || unit == 0x7f,
  );

  static int mathMax(int first, int second) => first > second ? first : second;

  void _emit(NotifyKitSnapshot value) {
    if (!_disposed && !_events.isClosed) _events.add(value);
  }
}
