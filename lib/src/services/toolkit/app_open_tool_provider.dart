import 'package:shelf/shelf.dart';

/// Host supplied bridge for process Apps that expose an App-owned OpenTool
/// endpoint. The AgentOS API package does not depend on AppDaemon itself.
abstract interface class AppOpenToolProvider {
  Future<List<Map<String, Object?>>> listTools({required bool all});

  /// Returns null when [toolId] is not an App-owned tool.
  Future<Response?> handleToolRequest({
    required Request request,
    required String toolId,
    required String operation,
  });
}
