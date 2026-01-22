import 'package:hive/hive.dart';

import 'dao.dart';

class HiveDao<T> implements Dao<T> {
  HiveDao(this._boxName);

  final String _boxName;
  Box<T>? _box;

  @override
  Future<void> init() async {
    _box ??= await Hive.openBox<T>(_boxName);
  }

  @override
  Future<void> upsert(String id, T value) async {
    await _ensureReady();
    await _box!.put(id, value);
  }

  @override
  Future<T?> getById(String id) async {
    await _ensureReady();
    return _box!.get(id);
  }

  @override
  Future<void> delete(String id) async {
    await _ensureReady();
    await _box!.delete(id);
  }

  Future<void> _ensureReady() async {
    if (_box == null || !_box!.isOpen) {
      await init();
    }
  }
}
