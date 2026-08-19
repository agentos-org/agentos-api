import 'dart:async';

import 'package:logging/logging.dart';

/// 第三方 App 授权请求的本机投递桥（新 AuthKit 流程）。
///
/// 新流程中授权权威在 AgentOS Server：第三方 Server 先向 Server 创建授权请求
/// 并拿到 `launchUri`，第三方 Client 通过 SDK 把 `launchUri` 投递到本机，
/// 由 AgentOS Desktop 与 Server 交互并展示可信授权页。
///
/// 本类只负责「投递」这一段，刻意不做以下事情：
/// - 不与 AgentOS Server 通信（由 Desktop 用自己的会话凭证完成）
/// - 不签发/持有任何 OAuth 凭证
/// - 不持久化授权记录
///
/// 因此它与将被下线的本地 `AuthKitService` 无关，可独立存活。
class AuthKitBridge {
  AuthKitBridge({Logger? logger})
      : _logger = logger ?? Logger('agentos_api.authkit');

  final Logger _logger;

  AuthKitHandler? _handler;

  /// 宿主（Desktop）是否已注册处理器。
  bool get hasHandler => _handler != null;

  /// 由宿主在 UI 就绪后注册；重复注册会覆盖旧处理器。
  void registerHandler(AuthKitHandler handler) {
    _handler = handler;
    _logger.info('AuthKit handler registered');
  }

  void unregisterHandler() {
    _handler = null;
    _logger.info('AuthKit handler unregistered');
  }

  /// 把授权请求投递给宿主展示。
  ///
  /// [waitForDecision] 为 false（默认）时，宿主一旦成功展示授权页即返回
  /// [AuthKitPresentationStatus.opened]，不等待用户操作 —— 第三方 Client 应以
  /// 自己 Server 的事务状态为准，而不是依赖本机返回值。
  ///
  /// [waitForDecision] 为 true 时最多等待 [decisionTimeout]；超时仍返回
  /// `opened`（表示已展示但尚无结论），不视为失败。
  Future<AuthKitPresentation> deliver(
    AuthKitDelivery delivery, {
    bool waitForDecision = false,
    Duration decisionTimeout = const Duration(minutes: 3),
  }) async {
    final handler = _handler;
    if (handler == null) {
      _logger.warning(
        'AuthKit delivery rejected: no handler registered '
        '(bundleId=${delivery.bundleId})',
      );
      return AuthKitPresentation.failed(
        errorCode: AuthKitErrorCodes.desktopNotReady,
        message: 'AgentOS Desktop is not ready to present authorization',
      );
    }

    AuthKitPresentationHandle handle;
    try {
      handle = await handler(delivery);
    } catch (e, s) {
      _logger.severe('AuthKit handler threw: $e', e, s);
      return AuthKitPresentation.failed(
        errorCode: AuthKitErrorCodes.deliveryFailed,
        message: 'Failed to present authorization request',
      );
    }

    if (handle.presentation.status != AuthKitPresentationStatus.opened) {
      return handle.presentation;
    }

    final decision = handle.decision;
    if (!waitForDecision || decision == null) {
      return handle.presentation;
    }

    try {
      return await decision.timeout(decisionTimeout);
    } on TimeoutException {
      _logger.info(
        'AuthKit decision wait timed out, reporting opened '
        '(requestId=${delivery.requestId})',
      );
      return handle.presentation;
    } catch (e, s) {
      _logger.warning('AuthKit decision failed: $e', e, s);
      return AuthKitPresentation.failed(
        errorCode: AuthKitErrorCodes.deliveryFailed,
        message: 'Authorization decision could not be completed',
      );
    }
  }
}

/// 宿主处理器：接收投递，返回展示结果 + 可选的决定 Future。
typedef AuthKitHandler = Future<AuthKitPresentationHandle>
    Function(AuthKitDelivery delivery);

/// 一次投递的载荷。
class AuthKitDelivery {
  const AuthKitDelivery({
    required this.launchUri,
    required this.requestId,
    this.bundleId,
  });

  /// 由第三方 Server 从 AgentOS Server 取得的原始唤起地址，原样透传。
  final String launchUri;

  /// 从 [launchUri] 解析出的授权请求标识，对本机是不透明值。
  final String requestId;

  /// 投递方的 AppKit bundleId。仅用于日志与本机识别（例如把窗口带到前台），
  /// **不是**授权主体 —— 授权主体是 Server 侧的 `client_id`。
  final String? bundleId;
}

/// 展示阶段的结果，以及（可选）用户决定的后续结果。
class AuthKitPresentationHandle {
  const AuthKitPresentationHandle({
    required this.presentation,
    this.decision,
  });

  AuthKitPresentationHandle.opened({this.decision})
      : presentation = const AuthKitPresentation(
          status: AuthKitPresentationStatus.opened,
        );

  final AuthKitPresentation presentation;

  /// 用户做出选择后完成；不支持时为 null。
  final Future<AuthKitPresentation>? decision;
}

/// 本机交互状态。
///
/// 刻意不含任何 OAuth 凭证：`submitted` 只表示 Desktop 已把用户决定提交给
/// AgentOS Server，不代表第三方登录已完成。
enum AuthKitPresentationStatus { opened, submitted, denied, failed }

class AuthKitPresentation {
  const AuthKitPresentation({
    required this.status,
    this.errorCode,
    this.message,
  });

  const AuthKitPresentation.failed({
    required this.errorCode,
    this.message,
  }) : status = AuthKitPresentationStatus.failed;

  final AuthKitPresentationStatus status;
  final String? errorCode;
  final String? message;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'status': status.name,
        if (errorCode != null) 'errorCode': errorCode,
        if (message != null) 'message': message,
      };
}

/// 投递与展示阶段的错误码。SDK 侧枚举需与此保持一致。
class AuthKitErrorCodes {
  AuthKitErrorCodes._();

  /// 本机网关不可达（由 SDK 侧根据连接失败判定）。
  static const String desktopNotRunning = 'desktop_not_running';

  /// 网关在运行，但 Desktop 尚未注册授权处理器（UI 未就绪）。
  static const String desktopNotReady = 'desktop_not_ready';

  /// Desktop 未登录 AgentOS 账号。
  static const String desktopNotLoggedIn = 'desktop_not_logged_in';

  /// `launchUri` 不合法（scheme/host 不符或缺少 request_id）。
  static const String invalidLaunchUri = 'invalid_launch_uri';

  /// 授权请求已过期。
  static const String authorizationExpired = 'authorization_expired';

  /// 授权请求不存在或已被处理。
  static const String authorizationNotFound = 'authorization_not_found';

  /// 无法访问 AgentOS Server。
  static const String serverUnavailable = 'server_unavailable';

  /// 投递通道失败。
  static const String deliveryFailed = 'delivery_failed';

  /// 等待本机交互超时。
  static const String timeout = 'timeout';
}

/// `agentos://oauth2/authorize?request_id=...` 的解析与校验。
///
/// Desktop 与网关共用同一实现，避免两处校验规则漂移。合法性只看 scheme /
/// host / path / `request_id` 是否存在，`request_id` 本身按不透明值处理。
class AuthKitLaunchUri {
  const AuthKitLaunchUri({
    required this.raw,
    required this.requestId,
  });

  static const String scheme = 'agentos';
  static const String host = 'oauth2';
  static const String path = '/authorize';
  static const String requestIdParam = 'request_id';

  final String raw;
  final String requestId;

  /// 解析失败返回 null（非法 scheme/host/path 或缺少 `request_id`）。
  static AuthKitLaunchUri? tryParse(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;

    final uri = Uri.tryParse(trimmed);
    if (uri == null) return null;
    if (uri.scheme.toLowerCase() != scheme) return null;
    if (uri.host.toLowerCase() != host) return null;

    final normalizedPath = uri.path.isEmpty ? path : uri.path;
    if (normalizedPath.toLowerCase() != path) return null;

    final requestId = uri.queryParameters[requestIdParam]?.trim();
    if (requestId == null || requestId.isEmpty) return null;

    return AuthKitLaunchUri(raw: trimmed, requestId: requestId);
  }

  static bool matches(Uri uri) {
    if (uri.scheme.toLowerCase() != scheme) return false;
    if (uri.host.toLowerCase() != host) return false;
    final normalizedPath = uri.path.isEmpty ? path : uri.path;
    return normalizedPath.toLowerCase() == path;
  }
}
