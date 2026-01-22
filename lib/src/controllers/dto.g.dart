// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'dto.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

AgentKitStatusResponse _$AgentKitStatusResponseFromJson(
        Map<String, dynamic> json) =>
    AgentKitStatusResponse(
      status: json['status'] as String,
      version: json['version'] as String,
    );

Map<String, dynamic> _$AgentKitStatusResponseToJson(
        AgentKitStatusResponse instance) =>
    <String, dynamic>{
      'status': instance.status,
      'version': instance.version,
    };
