import 'dart:async';
import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../../middleware.dart';
import '../../services/appkit/appkit_service.dart';
import '../../services/authkit/authkit_service.dart';

/// AuthKit controller providing OAuth-like authentication for third-party apps.
class AuthKitController {
  AuthKitController({
    required AuthKitService authKitService,
    required AppKitService appKitService,
  }) : _service = authKitService,
       _appKitService = appKitService;

  final AuthKitService _service;
  final AppKitService _appKitService;

  Router get router {
    final router = Router();
    router.post('/authorize', requireBearer()(_authorize));
    router.get('/authorize/<requestId>/status', _getStatusHandler);
    router.post('/token', requireBearer()(_exchangeToken));
    router.get('/userinfo', _getUserInfo);
    router.get('/avatar', _getAvatar);
    router.post('/revoke', requireBearer()(_revoke));
    router.get('/grants', requireBearer()(_listGrants));
    return router;
  }

  Future<Response> _getStatusHandler(Request request, String requestId) async {
    final token = extractBearerToken(request);
    if (token == null || token.isEmpty) return unauthorizedResponse();
    if (!_appKitService.isTokenValid(token)) return unauthorizedResponse();
    return _getStatus(request, requestId);
  }

  Future<Response> _authorize(Request request) async {
    final token = bearerTokenFrom(request);
    if (token == null) return unauthorizedResponse();

    final bundleId = _appKitService.bundleIdForToken(token);
    if (bundleId == null) return unauthorizedResponse('Invalid app token');

    final body = await request.readAsString();
    Map<String, dynamic> payload = {};
    if (body.isNotEmpty) {
      try {
        payload = jsonDecode(body) as Map<String, dynamic>;
      } catch (_) {}
    }

    final scopes = (payload['scopes'] as List?)?.cast<String>() ?? ['profile'];
    final appName = (payload['appName'] as String?)?.trim();

    final authRequest = await _service.authorize(
      bundleId: bundleId,
      appName: (appName != null && appName.isNotEmpty) ? appName : null,
      scopes: scopes,
    );

    final responseData = <String, dynamic>{
      'requestId': authRequest.requestId,
      'status': authRequest.status.name,
    };
    if (authRequest.authCode != null) {
      responseData['authCode'] = authRequest.authCode;
    }

    final statusCode = authRequest.status == AuthRequestStatus.granted ? 200 : 202;
    return Response(statusCode,
      body: jsonEncode(responseData),
      headers: {'content-type': 'application/json'},
    );
  }

  Future<Response> _getStatus(Request request, String requestId) async {
    final authRequest = _service.getRequestStatus(requestId);
    if (authRequest == null) {
      return Response.notFound(jsonEncode({'error': 'Request not found'}),
        headers: {'content-type': 'application/json'},
      );
    }

    final responseData = <String, dynamic>{
      'requestId': authRequest.requestId,
      'status': authRequest.status.name,
    };
    if (authRequest.authCode != null) {
      responseData['authCode'] = authRequest.authCode;
    }

    return Response.ok(
      jsonEncode(responseData),
      headers: {'content-type': 'application/json'},
    );
  }

  Future<Response> _exchangeToken(Request request) async {
    final body = await request.readAsString();
    if (body.isEmpty) {
      return Response(400, body: 'Missing request body');
    }

    Map<String, dynamic> payload;
    try {
      payload = jsonDecode(body) as Map<String, dynamic>;
    } catch (_) {
      return Response(400, body: 'Invalid JSON');
    }

    final authCode = payload['authCode'] as String?;
    if (authCode == null || authCode.isEmpty) {
      return Response(400, body: 'authCode is required');
    }

    final result = await _service.exchangeToken(authCode);
    if (result == null) {
      return Response(400,
        body: jsonEncode({'error': 'Invalid or expired authCode'}),
        headers: {'content-type': 'application/json'},
      );
    }

    return Response.ok(
      jsonEncode(result),
      headers: {'content-type': 'application/json'},
    );
  }

  Future<Response> _getUserInfo(Request request) async {
    final authHeader = request.headers['authorization'] ?? '';
    final accessToken = authHeader.startsWith('Bearer ')
        ? authHeader.substring(7).trim()
        : null;

    if (accessToken == null) {
      return _errorResponse(401, 'invalid_token', 'Missing access token');
    }

    final validation = await _service.validateAccessToken(accessToken);
    switch (validation) {
      case TokenValidationResult.valid:
        break;
      case TokenValidationResult.authExpired:
        return _errorResponse(401, 'auth_expired', 'AgentOS user logged out');
      case TokenValidationResult.tokenRevoked:
        return _errorResponse(401, 'token_revoked', 'Authorization revoked');
      case TokenValidationResult.invalidToken:
        return _errorResponse(401, 'invalid_token', 'Invalid access token');
    }

    final userInfo = await _service.getUserInfo(accessToken);
    if (userInfo == null) {
      return Response.notFound(
        jsonEncode({'error': 'not_found', 'message': 'User not found'}),
        headers: {'content-type': 'application/json'},
      );
    }

    return Response.ok(
      jsonEncode(userInfo.toJson()),
      headers: {'content-type': 'application/json'},
    );
  }

  Response _errorResponse(int statusCode, String error, String message) {
    return Response(statusCode,
      body: jsonEncode({'error': error, 'message': message}),
      headers: {'content-type': 'application/json'},
    );
  }

  Future<Response> _getAvatar(Request request) async {
    final profile = await _service.getAvatarProfile();
    if (profile == null || profile.avatarUrl == null) {
      return Response.notFound('No avatar available');
    }

    if (profile.avatarBase64 != null) {
      final bytes = base64Decode(profile.avatarBase64!);
      return Response.ok(
        bytes,
        headers: {'content-type': 'image/png'},
      );
    }

    return Response.ok(
      jsonEncode({'avatarUrl': profile.avatarUrl}),
      headers: {'content-type': 'application/json'},
    );
  }

  Future<Response> _revoke(Request request) async {
    final token = bearerTokenFrom(request);
    if (token == null) return unauthorizedResponse();

    final body = await request.readAsString();
    Map<String, dynamic> payload = {};
    if (body.isNotEmpty) {
      try {
        payload = jsonDecode(body) as Map<String, dynamic>;
      } catch (_) {
        return Response(400, body: 'Invalid JSON');
      }
    }

    final bundleId = payload['bundleId'] as String? ??
        _appKitService.bundleIdForToken(token);
    if (bundleId == null) {
      return Response(400, body: 'bundleId is required');
    }

    await _service.revokeGrant(bundleId);
    return Response.ok(jsonEncode({'status': 'revoked'}),
      headers: {'content-type': 'application/json'},
    );
  }

  Future<Response> _listGrants(Request request) async {
    final grants = await _service.listGrants();
    return Response.ok(
      jsonEncode(grants.map((g) => g.toJson()).toList()),
      headers: {'content-type': 'application/json'},
    );
  }
}
