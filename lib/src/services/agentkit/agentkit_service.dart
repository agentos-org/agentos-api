import 'package:agentos_kernel/agentos_kernel.dart';
import 'package:liteagent_sdk_dart/liteagent_sdk_dart.dart';

class AgentKitService {
  final Future<KernelService?> _kernelFuture;

  const AgentKitService({required Future<KernelService?> kernelFuture})
    : _kernelFuture = kernelFuture;

  Future<void> archiveAgentMessage({
    required String sessionId,
    required String username,
    required String bundleId,
    required AgentMessage agentMessage,
  }) async {
    final kernel = await _kernelFuture;
    if (kernel == null) {
      return;
    }
    final normalizedSessionId = sessionId.trim();
    final normalizedTaskId = agentMessage.taskId.trim();
    if (normalizedSessionId.isEmpty || normalizedTaskId.isEmpty) {
      return;
    }
    final roleName = _normalizeName(agentMessage.role);
    final toName = _normalizeName(agentMessage.to);
    final actorType = _resolveActorType(roleName: roleName, toName: toName);
    if (actorType == null) {
      return;
    }
    final content = _extractContent(agentMessage);
    if (content.isEmpty) {
      return;
    }

    final actorId = actorType == AgentMemoryActorType.user
        ? username.trim()
        : bundleId.trim();
    if (actorId.isEmpty) {
      return;
    }

    await kernel.appendAgentMemoryMessage(
      sessionId: normalizedSessionId,
      taskId: normalizedTaskId,
      actorId: actorId,
      actorType: actorType,
      content: content,
      timestamp: agentMessage.createTime.toUtc(),
    );
  }

  List<String> _extractContent(AgentMessage agentMessage) {
    final typeName = _normalizeName(agentMessage.type);
    if (typeName == 'text') {
      final text = agentMessage.content;
      if (text is! String) {
        return const [];
      }
      final normalized = text.trim();
      if (normalized.isEmpty) {
        return const [];
      }
      return [normalized];
    }
    if (typeName == 'image') {
      return const ['[Image]'];
    }
    if (typeName == 'contentlist') {
      return _extractContentList(agentMessage.content);
    }
    return const [];
  }

  List<String> _extractContentList(Object? value) {
    if (value is! List) {
      return const [];
    }
    final items = <String>[];
    for (final item in value) {
      if (item is! Map) {
        continue;
      }
      final typeName = _normalizeName(item['type']);
      if (typeName == 'text') {
        final message = item['message'];
        if (message is String) {
          final normalized = message.trim();
          if (normalized.isNotEmpty) {
            items.add(normalized);
          }
        }
        continue;
      }
      if (typeName == 'image') {
        items.add('[Image]');
      }
    }
    return items;
  }

  AgentMemoryActorType? _resolveActorType({
    required String roleName,
    required String toName,
  }) {
    if (roleName == 'user') {
      return AgentMemoryActorType.user;
    }
    if ((roleName == 'agent' || roleName == 'assistant' || roleName == 'llm') &&
        toName == 'user') {
      return AgentMemoryActorType.app;
    }
    return null;
  }

  String _normalizeName(Object? value) {
    return value?.toString().trim().toLowerCase() ?? '';
  }
}
