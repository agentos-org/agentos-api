import 'dart:async';
import 'dart:convert';

import '../../models/agent/agent_models.dart';
import '../../models/app/app_models.dart';
import 'package:unique_id_dart/unique_id_dart.dart';

class AppKitService {
  final List<String> _apps = [];
  final Map<String, String> _bundleTokens = {};
  final Map<String, List<String>> _bundleAgents = {};

  List<String> listApps() => List.unmodifiable(_apps);

  bool isTokenValid(String token) => _bundleIdForToken(token) != null;

  String? bundleIdForToken(String token) => _bundleIdForToken(token);

  void registerApp(String rawDefinition) {
    // Legacy placeholder registration.
    if (rawDefinition.isNotEmpty) {
      _apps.add(rawDefinition);
    }
  }

  TokenInfo registerBundle(AppBundleDto bundle) {
    final token = _issueToken();
    _bundleTokens[bundle.bundleId] = token;
    return TokenInfo(token: token);
  }

  bool bindAgents({required String token, required List<AgentInfoDto> agents}) {
    final bundleId = _bundleIdForToken(token);
    if (bundleId == null) {
      return false;
    }
    _bundleAgents[bundleId] = agents.map((e) => e.id).toList();
    return true;
  }

  Stream<EventDto> subscribe(String token) {
    final bundleId = _bundleIdForToken(token);
    if (bundleId == null) {
      return const Stream<EventDto>.empty();
    }

    late final StreamController<EventDto> controller;
    controller = StreamController<EventDto>(
      onListen: () {
        controller.add(
          EventDto(
            event: 'welcome',
            data: jsonEncode({'bundleId': bundleId}),
          ),
        );
      },
      onCancel: () {
        controller.close();
      },
    );
    return controller.stream;
  }

  String _issueToken() {
    final generated = uniqueId(shorter: true);
    return 'sk-$generated';
  }

  String? _bundleIdForToken(String token) {
    for (final entry in _bundleTokens.entries) {
      if (entry.value == token) {
        return entry.key;
      }
    }
    return null;
  }
}
