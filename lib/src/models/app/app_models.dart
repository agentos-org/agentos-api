class AppBundleDto {
  AppBundleDto({
    required this.bundleId,
    this.appGroupId,
    this.opentoolServers = const [],
  });

  final String bundleId;
  final String? appGroupId;
  final List<OpenToolServerDeclarationDto> opentoolServers;

  factory AppBundleDto.fromJson(Map<String, dynamic> json) {
    final appGroupId = (json['appGroupId'] ?? '').toString().trim();
    final rawOpenToolServers = json['opentoolServers'];
    if (rawOpenToolServers != null && rawOpenToolServers is! List) {
      throw const FormatException('opentoolServers must be an array');
    }

    final opentoolServers = <OpenToolServerDeclarationDto>[];
    final refs = <String>{};
    for (final rawDeclaration in rawOpenToolServers as List? ?? const []) {
      if (rawDeclaration is! Map) {
        throw const FormatException(
          'opentoolServers entries must be JSON objects',
        );
      }
      if (rawDeclaration.containsKey('tag') ||
          rawDeclaration.containsKey('version')) {
        throw const FormatException(
          'opentoolServers.version is not supported; the latest version is always selected',
        );
      }
      final declaration = OpenToolServerDeclarationDto.fromJson(
        Map<String, dynamic>.from(rawDeclaration),
      );
      if (declaration.ref.isEmpty) {
        throw const FormatException('opentoolServers.ref is required');
      }
      if (declaration.name.isEmpty) {
        throw const FormatException('opentoolServers.name is required');
      }
      if (!refs.add(declaration.ref)) {
        throw FormatException(
          'opentoolServers.ref must be unique: ${declaration.ref}',
        );
      }
      opentoolServers.add(declaration);
    }

    return AppBundleDto(
      bundleId: (json['bundleId'] ?? '').toString().trim(),
      appGroupId: appGroupId.isEmpty ? null : appGroupId,
      opentoolServers: List.unmodifiable(opentoolServers),
    );
  }
}

class OpenToolServerDeclarationDto {
  const OpenToolServerDeclarationDto({required this.ref, required this.name});

  final String ref;
  final String name;

  factory OpenToolServerDeclarationDto.fromJson(Map<String, dynamic> json) {
    return OpenToolServerDeclarationDto(
      ref: (json['ref'] ?? '').toString().trim(),
      name: (json['name'] ?? '').toString().trim(),
    );
  }

  Map<String, dynamic> toJson() => {'ref': ref, 'name': name};
}

class OpenToolResolvedServerDto {
  const OpenToolResolvedServerDto({
    required this.namespace,
    required this.name,
    required this.version,
  });

  final String namespace;
  final String name;
  final String version;

  Map<String, dynamic> toJson() => {
    'namespace': namespace,
    // Deprecated AppKit aliases retained for clients compiled against the
    // pre-OpenTool-V2 response shape. Keep these at the public API boundary;
    // daemon-facing code continues to use namespace/version exclusively.
    'repo': namespace,
    'name': name,
    'version': version,
    'tag': version,
  };
}

class OpenToolRegistrationDto {
  const OpenToolRegistrationDto({
    required this.ref,
    required this.name,
    required this.status,
    this.server,
    this.id,
  });

  final String ref;
  final String name;
  final String status;
  final OpenToolResolvedServerDto? server;
  final String? id;

  Map<String, dynamic> toJson() => {
    'ref': ref,
    if (server == null) 'name': name,
    if (server != null) 'server': server!.toJson(),
    'status': status,
    if (status == OpenToolRegistrationStatus.running && id != null) 'id': id,
  };
}

class OpenToolRegistrationStatus {
  static const String notFound = 'notFound';
  static const String running = 'running';
  static const String starting = 'starting';
}

class TokenInfo {
  TokenInfo({
    required this.token,
    required this.bundleId,
    required this.appGroupId,
    this.opentoolServers = const [],
  });

  final String token;
  final String bundleId;
  final String appGroupId;
  final List<OpenToolRegistrationDto> opentoolServers;

  Map<String, dynamic> toJson() => {
    'token': token,
    'bundleId': bundleId,
    'appGroupId': appGroupId,
    if (opentoolServers.isNotEmpty)
      'opentoolServers': opentoolServers.map((item) => item.toJson()).toList(),
  };

  TokenInfo withOpenToolServers(List<OpenToolRegistrationDto> servers) {
    return TokenInfo(
      token: token,
      bundleId: bundleId,
      appGroupId: appGroupId,
      opentoolServers: List.unmodifiable(servers),
    );
  }
}

class EventDto {
  EventDto({required this.event, required this.data, this.id});

  final String event;
  final String data;
  final String? id;
}

class AppEventDto {
  const AppEventDto({
    required this.id,
    required this.type,
    required this.source,
    required this.time,
    required this.subject,
    required this.data,
    this.version = 1,
  });

  final int version;
  final String id;
  final String type;
  final String source;
  final DateTime time;
  final String subject;
  final Map<String, dynamic> data;

  Map<String, dynamic> toJson() => {
    'version': version,
    'id': id,
    'type': type,
    'source': source,
    'time': time.toUtc().toIso8601String(),
    'subject': subject,
    'data': data,
  };
}

class AppEventType {
  static const String toolkitProvisionSucceeded = 'toolkit.provision.succeeded';
  static const String toolkitProvisionFailed = 'toolkit.provision.failed';
  static const String toolkitToolAvailable = 'toolkit.tool.available';
  static const String toolkitToolUnavailable = 'toolkit.tool.unavailable';

  /// Reserved for future AgentKit-to-app commands.
  static const String appCommandRequested = 'app.command.requested';

  /// AuthKit user login state changed (login / logout / account switch).
  static const String authkitUserChanged = 'authkit.user.changed';
}
