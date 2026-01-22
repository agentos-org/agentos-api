class AppBundleDto {
  AppBundleDto({required this.bundleId});

  final String bundleId;

  factory AppBundleDto.fromJson(Map<String, dynamic> json) {
    return AppBundleDto(bundleId: (json['bundleId'] ?? '').toString());
  }
}

class TokenInfo {
  TokenInfo({required this.token});

  final String token;

  Map<String, dynamic> toJson() => {'token': token};
}

class EventDto {
  EventDto({required this.event, required this.data});

  final String event;
  final String data;
}
