import 'dart:io';

import 'package:hive/hive.dart';

/// Initializes Hive for server-side usage with a configurable data path.
class HiveProvider {
  HiveProvider({String? dataPath}) : _dataPath = dataPath ?? '.data/hive';

  final String _dataPath;

  Future<void> init() async {
    final directory = Directory(_dataPath);
    if (!directory.existsSync()) {
      await directory.create(recursive: true);
    }
    Hive.init(directory.path);
  }
}
