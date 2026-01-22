import 'package:json_annotation/json_annotation.dart';

part 'dto.g.dart';

@JsonSerializable()
class AgentKitStatusResponse {
  AgentKitStatusResponse({required this.status, required this.version});

  final String status;
  final String version;

  factory AgentKitStatusResponse.fromJson(Map<String, dynamic> json) =>
      _$AgentKitStatusResponseFromJson(json);

  Map<String, dynamic> toJson() => _$AgentKitStatusResponseToJson(this);
}
