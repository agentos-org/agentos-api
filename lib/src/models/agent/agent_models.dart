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

class PresetOpenSpec {
  PresetOpenSpec({required this.systemPrompt, this.openSpec});

  final String systemPrompt;
  final OpenSpec? openSpec;

  factory PresetOpenSpec.fromJson(Map<String, dynamic> json) {
    return PresetOpenSpec(
      systemPrompt: (json['systemPrompt'] ?? '').toString(),
      openSpec: json['openSpec'] is Map<String, dynamic>
          ? OpenSpec.fromJson(json['openSpec'] as Map<String, dynamic>)
          : json['openSpec'] is Map
              ? OpenSpec.fromJson(
                  Map<String, dynamic>.from(json['openSpec'] as Map),
                )
              : null,
    );
  }

  Map<String, dynamic> toJson() {
    final payload = <String, dynamic>{'systemPrompt': systemPrompt};
    if (openSpec != null) {
      payload['openSpec'] = openSpec!.toJson();
    }
    return payload;
  }
}

class OpenSpec {
  OpenSpec({
    required this.openSpec,
    required this.protocol,
    this.serverUrl,
    this.apiKey,
  });

  final String openSpec;
  final String protocol;
  final String? serverUrl;
  final ApiKey? apiKey;

  factory OpenSpec.fromJson(Map<String, dynamic> json) {
    return OpenSpec(
      openSpec: (json['openSpec'] ?? '').toString(),
      protocol: (json['protocol'] ?? '').toString(),
      serverUrl: (json['serverUrl'] ?? '').toString().trim().isEmpty
          ? null
          : (json['serverUrl'] ?? '').toString(),
      apiKey: json['apiKey'] is Map<String, dynamic>
          ? ApiKey.fromJson(json['apiKey'] as Map<String, dynamic>)
          : json['apiKey'] is Map
              ? ApiKey.fromJson(Map<String, dynamic>.from(json['apiKey'] as Map))
              : null,
    );
  }

  Map<String, dynamic> toJson() {
    final payload = <String, dynamic>{
      'openSpec': openSpec,
      'protocol': protocol,
    };
    if (serverUrl != null) {
      payload['serverUrl'] = serverUrl;
    }
    if (apiKey != null) {
      payload['apiKey'] = apiKey!.toJson();
    }
    return payload;
  }
}

class ApiKey {
  ApiKey({required this.type, required this.apiKey});

  final String type;
  final String apiKey;

  factory ApiKey.fromJson(Map<String, dynamic> json) {
    return ApiKey(
      type: (json['type'] ?? '').toString(),
      apiKey: (json['apiKey'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'type': type,
        'apiKey': apiKey,
      };
}
