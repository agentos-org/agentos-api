class AgentConfigDto {
  AgentConfigDto({required this.config});

  final String config;

  factory AgentConfigDto.fromJson(Map<String, dynamic> json) {
    return AgentConfigDto(config: (json['config'] ?? '').toString());
  }
}

class AgentInfoDto {
  AgentInfoDto({required this.id});

  final String id;

  factory AgentInfoDto.fromJson(Map<String, dynamic> json) {
    return AgentInfoDto(id: (json['id'] ?? '').toString());
  }

  Map<String, dynamic> toJson() => {'id': id};
}

class SessionInitResponse {
  SessionInitResponse({required this.sessionId, this.status = 'initialized'});

  final String sessionId;
  final String status;

  Map<String, dynamic> toJson() => {'sessionId': sessionId, 'status': status};
}

class ChatRequestDto {
  ChatRequestDto({this.sessionId, this.message});

  final String? sessionId;
  final String? message;

  factory ChatRequestDto.fromJson(Map<String, dynamic> json) {
    return ChatRequestDto(
      sessionId: (json['sessionId'] ?? '').toString().trim().isEmpty
          ? null
          : (json['sessionId'] ?? '').toString(),
      message: (json['message'] ?? '').toString(),
    );
  }
}

class ChatResponseDto {
  ChatResponseDto({required this.sessionId, required this.reply});

  final String sessionId;
  final String reply;

  Map<String, dynamic> toJson() => {'sessionId': sessionId, 'reply': reply};
}
