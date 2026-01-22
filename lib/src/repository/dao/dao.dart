abstract class Dao<T> {
  Future<void> init();
  Future<void> upsert(String id, T value);
  Future<T?> getById(String id);
  Future<void> delete(String id);
}
