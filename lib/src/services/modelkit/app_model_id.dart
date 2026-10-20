import 'dart:convert';

import 'package:crypto/crypto.dart';

/// 应用模型 id（hashid）的生成规则。
///
/// 第三方应用注册模型时，网关根据 `bundleId + name` 生成一个确定性的
/// 12 位 hex hashid（SHA-256 前 12 位，与本地 / 平台模型的 id 同形），
/// 并在注册成功时返回给调用方。这个 hashid 同时是：
///
/// - `GET /modelkit/models` 与 `GET /modelkit/app-models` 里的 `id`；
/// - `PUT` / `DELETE` / `toggle /modelkit/app-models/<id>` 的路径参数；
/// - 调用 chat / embedding / ... 等代理路由时请求里的 `model`。
///
/// 默认认为同一个应用注册的模型 name 互不相同，所以同一应用重复注册同名模型
/// 得到同一个 hashid（幂等）；不同应用即使 name 相同，hashid 也不同。
class AppModelId {
  AppModelId._();

  /// hashid 的长度（hex 字符数）。
  static const int hashLength = 12;

  /// bundleId 的最大长度。
  static const int maxBundleIdLength = 128;

  static final RegExp _allowedChars = RegExp(r'^[A-Za-z0-9._-]+$');
  static final RegExp _hashPattern = RegExp(r'^[0-9a-f]{12}$');

  /// [bundleId] 是否符合 `[A-Za-z0-9._-]{1,128}`。
  ///
  /// 这个字符集不包含 `:`，所以 [generate] 里 `bundleId:name` 的拼接没有歧义。
  static bool isValidBundleId(String bundleId) =>
      bundleId.length <= maxBundleIdLength && _allowedChars.hasMatch(bundleId);

  /// [id] 是否是 [generate] 产生的 hashid 形态（12 位小写 hex）。
  static bool isHashId(String id) => _hashPattern.hasMatch(id);

  /// 由 [bundleId] 与 [name] 生成应用模型的 hashid：
  /// `sha256("<bundleId>:<name>")` 的前 [hashLength] 位 hex。
  ///
  /// 两个参数都会先 trim；name 区分大小写。
  static String generate({required String bundleId, required String name}) {
    final input = '${bundleId.trim()}:${name.trim()}';
    return sha256
        .convert(utf8.encode(input))
        .toString()
        .substring(0, hashLength);
  }

  /// bundleId 不合法时的提示文案（用于 400 响应）。
  static String bundleIdRequirement(String bundleId) =>
      'bundleId "$bundleId" cannot be used to register app models: '
      'only 1-$maxBundleIdLength characters of [A-Za-z0-9._-] are allowed';
}
