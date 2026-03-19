import 'package:hive/hive.dart';

import '../../repository/hive/hive_provider.dart';

class CronKitModelRef {
  const CronKitModelRef({
    required this.cronId,
    required this.modelId,
    required this.bundleId,
    required this.appGroupId,
    required this.updatedAt,
  });

  final String cronId;
  final String modelId;
  final String bundleId;
  final String appGroupId;
  final DateTime updatedAt;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'cronId': cronId,
    'modelId': modelId,
    'bundleId': bundleId,
    'appGroupId': appGroupId,
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory CronKitModelRef.fromJson(Map<dynamic, dynamic> json) {
    return CronKitModelRef(
      cronId: json['cronId'] as String,
      modelId: json['modelId'] as String,
      bundleId: json['bundleId'] as String,
      appGroupId: json['appGroupId'] as String,
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }
}

abstract class CronKitModelRefStore {
  Future<void> put(CronKitModelRef ref);

  Future<CronKitModelRef?> get(String cronId);

  Future<void> delete(String cronId);
}

class HiveCronKitModelRefStore implements CronKitModelRefStore {
  HiveCronKitModelRefStore({
    HiveProvider? hiveProvider,
    String boxName = 'cronkit_model_refs',
  }) : _hiveProvider = hiveProvider ?? HiveProvider(),
       _boxName = boxName;

  final HiveProvider _hiveProvider;
  final String _boxName;
  Box<Map>? _box;

  @override
  Future<void> put(CronKitModelRef ref) async {
    final box = await _ensureBox();
    await box.put(ref.cronId, ref.toJson());
  }

  @override
  Future<CronKitModelRef?> get(String cronId) async {
    final box = await _ensureBox();
    final value = box.get(cronId);
    if (value == null) {
      return null;
    }
    return CronKitModelRef.fromJson(value);
  }

  @override
  Future<void> delete(String cronId) async {
    final box = await _ensureBox();
    await box.delete(cronId);
  }

  Future<Box<Map>> _ensureBox() async {
    final current = _box;
    if (current != null && current.isOpen) {
      return current;
    }
    await _hiveProvider.init();
    _box = await Hive.openBox<Map>(_boxName);
    return _box!;
  }
}
