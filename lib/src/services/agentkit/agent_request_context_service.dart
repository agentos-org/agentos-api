import 'dart:io';

import 'package:shelf/shelf.dart';

import '../../middleware.dart';
import '../appkit/appkit_service.dart';

class AgentRequestContext {
  final String username;
  final String bundleId;

  const AgentRequestContext({
    required this.username,
    required this.bundleId,
  });
}

class AgentRequestContextService {
  final AppKitService? _appKitService;

  const AgentRequestContextService({AppKitService? appKitService})
    : _appKitService = appKitService;

  AgentRequestContext? resolve(Request request) {
    final appKitService = _appKitService;
    if (appKitService == null) {
      return null;
    }
    final token = bearerTokenFrom(request);
    if (token == null || token.isEmpty) {
      return null;
    }
    final bundleId = appKitService.bundleIdForToken(token)?.trim();
    if (bundleId == null || bundleId.isEmpty) {
      return null;
    }
    final username = _resolveSystemUsername();
    if (username.isEmpty) {
      return null;
    }
    return AgentRequestContext(username: username, bundleId: bundleId);
  }

  String _resolveSystemUsername() {
    final candidates = [
      Platform.environment['USER'],
      Platform.environment['LOGNAME'],
      Platform.environment['USERNAME'],
    ];
    for (final candidate in candidates) {
      final normalized = candidate?.trim();
      if (normalized != null && normalized.isNotEmpty) {
        return normalized;
      }
    }
    return '';
  }
}
