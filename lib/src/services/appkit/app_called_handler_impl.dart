import 'dart:convert';

import 'package:agentos_kernel/agentos_kernel.dart';
import 'package:liteagent_sdk_dart/liteagent_sdk_dart.dart';

import '../../models/app/app_models.dart';
import 'appkit_service.dart';

/// AppCalledHandler implementation
///
/// When Kernel decides to call an App via callApp:
/// 1. Check if the App is online (subscribed via SSE) using AppKitService
/// 2. Push the call request as an SSE event to the corresponding App
/// 3. Return the push result (success/failure)
class AppCalledHandlerImpl implements AppCalledHandler {
  final AppKitService _appKitService;

  AppCalledHandlerImpl({required AppKitService appKitService})
      : _appKitService = appKitService;

  @override
  Future<AppCallResult> callApp({
    required String bundleId,
    required List<Content> contentList,
  }) async {
    if (!_appKitService.isAppOnline(bundleId)) {
      return AppCallResult.failure('App is not online: $bundleId');
    }

    final payload = {
      'bundleId': bundleId,
      'contentList': contentList.map((c) => c.toJson()).toList(),
    };

    final pushed = _appKitService.pushEvent(
      bundleId,
      EventDto(
        event: 'callApp',
        data: jsonEncode(payload),
      ),
    );

    if (!pushed) {
      return AppCallResult.failure('Failed to push event to app: $bundleId');
    }

    return const AppCallResult.success();
  }
}
