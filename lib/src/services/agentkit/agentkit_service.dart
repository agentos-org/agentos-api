import '../../controllers/dto.dart';
import '../../models/agent/agent_models.dart';
import 'package:unique_id_dart/unique_id_dart.dart';

class AgentKitService {
  AgentKitStatusResponse getStatus() {
    return AgentKitStatusResponse(status: 'ready', version: '0.0.1');
  }

  AgentInfoDto createAgent(AgentConfigDto config) {
    final id = _nextId('agent');
    return AgentInfoDto(id: id);
  }

  SessionInitResponse initSession() {
    final sessionId = _nextId('sess');
    return SessionInitResponse(sessionId: sessionId);
  }

  ChatResponseDto chat(ChatRequestDto request) {
    final sessionId = request.sessionId ?? _nextId('sess');
    final reply = request.message?.isNotEmpty == true
        ? 'echo: ${request.message}'
        : 'no message provided';
    return ChatResponseDto(sessionId: sessionId, reply: reply);
  }

  String _nextId(String prefix) {
    final value = uniqueId(shorter: true);
    return '$prefix-$value';
  }
}
