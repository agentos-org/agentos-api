class AppBundleDto {
  AppBundleDto({required this.bundleId, this.appGroupId});

  final String bundleId;
  final String? appGroupId;

  factory AppBundleDto.fromJson(Map<String, dynamic> json) {
    final appGroupId = (json['appGroupId'] ?? '').toString().trim();
    return AppBundleDto(
      bundleId: (json['bundleId'] ?? '').toString(),
      appGroupId: appGroupId.isEmpty ? null : appGroupId,
    );
  }
}

class TokenInfo {
  TokenInfo({
    required this.token,
    required this.bundleId,
    required this.appGroupId,
  });

  final String token;
  final String bundleId;
  final String appGroupId;

  Map<String, dynamic> toJson() => {
    'token': token,
    'bundleId': bundleId,
    'appGroupId': appGroupId,
  };
}

class EventDto {
  EventDto({required this.event, required this.data});

  final String event;
  final String data;
}
