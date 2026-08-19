import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../../middleware.dart';
import '../../services/authkit/authkit_bridge.dart';
import '../../services/appkit/appkit_service.dart';

/// 新 AuthKit 流程的本机投递入口。
///
/// 只有一个职责：把第三方 Client 通过 SDK 传来的 `launchUri` 交给 Desktop 展示。
/// 不实现任何 OAuth 端点 —— token 兑换、ID Token 验证都在第三方 Server 与
/// AgentOS Server 之间完成。
///
/// 挂载在 [ApiConfig.authkitPath] 下，与登录态 [AuthKitService] 共用 AuthKit 命名。
class AuthKitController {
  AuthKitController({
    required AuthKitBridge bridge,
    required AppKitService appKitService,
  })  : _bridge = bridge,
        _appKitService = appKitService;

  final AuthKitBridge _bridge;
  final AppKitService _appKitService;

  /// 等待用户决定的上限，同时也是响应的兜底时限。
  static const Duration maxDecisionWait = Duration(minutes: 3);

  Router get router {
    final router = Router();
    final guard = requireBearer();
    router.post('/open', guard(_open));
    router.get('/status', guard(_status));
    return router;
  }

  Future<Response> _open(Request request) async {
    final token = bearerTokenFrom(request);
    if (token == null || !_appKitService.isTokenValid(token)) {
      return unauthorizedResponse('Invalid app token');
    }

    final Map<String, dynamic> body;
    try {
      final raw = await request.readAsString();
      body = raw.trim().isEmpty
          ? <String, dynamic>{}
          : Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return _errorResponse(
        400,
        AuthKitErrorCodes.invalidLaunchUri,
        'Request body must be a JSON object',
      );
    }

    final launchUriRaw = body['launchUri'];
    if (launchUriRaw is! String || launchUriRaw.trim().isEmpty) {
      return _errorResponse(
        400,
        AuthKitErrorCodes.invalidLaunchUri,
        'launchUri is required',
      );
    }

    // 只信任 AgentOS Server 生成的形状；原样透传，不重写 query。
    final launchUri = AuthKitLaunchUri.tryParse(launchUriRaw);
    if (launchUri == null) {
      return _errorResponse(
        400,
        AuthKitErrorCodes.invalidLaunchUri,
        'launchUri must look like '
        '${AuthKitLaunchUri.scheme}://'
        '${AuthKitLaunchUri.host}'
        '${AuthKitLaunchUri.path}'
        '?${AuthKitLaunchUri.requestIdParam}=...',
      );
    }

    final waitForDecision = body['waitForDecision'] == true;
    final decisionTimeout = _parseTimeout(body['timeoutMs']);

    final presentation = await _bridge.deliver(
      AuthKitDelivery(
        launchUri: launchUri.raw,
        requestId: launchUri.requestId,
        bundleId: _appKitService.bundleIdForToken(token),
      ),
      waitForDecision: waitForDecision,
      decisionTimeout: decisionTimeout,
    );

    final statusCode = presentation.errorCode ==
            AuthKitErrorCodes.desktopNotReady
        ? 503
        : 200;
    return Response(
      statusCode,
      body: jsonEncode(presentation.toJson()),
      headers: _jsonHeaders,
    );
  }

  /// 供 SDK 探测本机是否已具备承载授权界面的能力。
  Future<Response> _status(Request request) async {
    final token = bearerTokenFrom(request);
    if (token == null || !_appKitService.isTokenValid(token)) {
      return unauthorizedResponse('Invalid app token');
    }
    return Response.ok(
      jsonEncode(<String, dynamic>{'ready': _bridge.hasHandler}),
      headers: _jsonHeaders,
    );
  }

  Duration _parseTimeout(Object? raw) {
    final ms = raw is int ? raw : int.tryParse('${raw ?? ''}');
    if (ms == null || ms <= 0) return maxDecisionWait;
    final requested = Duration(milliseconds: ms);
    return requested > maxDecisionWait ? maxDecisionWait : requested;
  }

  Response _errorResponse(int statusCode, String errorCode, String message) {
    return Response(
      statusCode,
      body: jsonEncode(
        AuthKitPresentation.failed(
          errorCode: errorCode,
          message: message,
        ).toJson(),
      ),
      headers: _jsonHeaders,
    );
  }

  static const Map<String, String> _jsonHeaders = {
    'content-type': 'application/json',
  };
}
