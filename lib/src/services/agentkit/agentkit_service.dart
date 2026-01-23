import 'dart:convert';

import '../../models/agent/agent_models.dart';
import 'liteagent_client.dart';

class AgentKitService {
  AgentKitService({LiteagentClient? client})
      : _client = client ?? LiteagentClient();

  final LiteagentClient _client;

  Future<LiteagentClientResponse> presetOpenSpec(
    PresetOpenSpec presetOpenSpec,
  ) {
    final body = utf8.encode(jsonEncode(presetOpenSpec.toJson()));
    return _client.send(
      method: 'POST',
      path: '/presetOpenSpec',
      headers: const {'content-type': 'application/json'},
      body: body,
    );
  }
}
