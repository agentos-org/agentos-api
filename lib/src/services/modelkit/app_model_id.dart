/// 应用模型 id 的命名空间规则。
///
/// 第三方应用注册模型时自带的 `id`（下称 localId）只在其 bundle 内有意义；
/// 网关对外（`/modelkit/models`、路由）使用的 id 是 `localId@bundleId`
/// （下称 qualifiedId），因此不同应用可以使用同一个 localId，也不可能与本地 /
/// 平台 / 自定义模型的 id 冲突。
///
/// localId 与 bundleId 都不允许包含 [separator]，所以 qualifiedId 的拆分没有歧义。
class AppModelId {
  AppModelId._();

  /// localId 与 bundleId 之间的分隔符。
  static const String separator = '@';

  /// localId 的最大长度。
  static const int maxLocalIdLength = 64;

  /// bundleId 的最大长度。
  static const int maxBundleIdLength = 128;

  static final RegExp _allowedChars = RegExp(r'^[A-Za-z0-9._-]+$');

  /// [localId] 是否符合 `[A-Za-z0-9._-]{1,64}`。
  static bool isValidLocalId(String localId) =>
      localId.length <= maxLocalIdLength && _allowedChars.hasMatch(localId);

  /// [bundleId] 是否符合 `[A-Za-z0-9._-]{1,128}`。
  static bool isValidBundleId(String bundleId) =>
      bundleId.length <= maxBundleIdLength && _allowedChars.hasMatch(bundleId);

  /// 由 [localId] 与 [bundleId] 组成对外使用的 qualifiedId：`localId@bundleId`。
  static String qualify({required String bundleId, required String localId}) =>
      '$localId$separator$bundleId';

  /// 从 [qualifiedId] 中去掉 `@bundleId` 后缀，得到 localId。
  ///
  /// [qualifiedId] 不以 `@bundleId` 结尾，或去掉后缀后为空时返回 null。
  /// 按调用方给出的 [bundleId] 去后缀（而不是按 `@` 切分），因此历史遗留的、
  /// localId 本身含 `@` 的记录也能正确还原。
  static String? localIdOf(String qualifiedId, {required String bundleId}) {
    final suffix = '$separator$bundleId';
    if (!qualifiedId.endsWith(suffix)) return null;
    final localId = qualifiedId.substring(
      0,
      qualifiedId.length - suffix.length,
    );
    return localId.isEmpty ? null : localId;
  }

  /// localId 不合法时的提示文案（用于 400 响应）。
  static String localIdRequirement() =>
      'id must be 1-$maxLocalIdLength characters of [A-Za-z0-9._-]';

  /// bundleId 不合法时的提示文案（用于 400 响应）。
  static String bundleIdRequirement(String bundleId) =>
      'bundleId "$bundleId" cannot be used to register app models: '
      'only 1-$maxBundleIdLength characters of [A-Za-z0-9._-] are allowed';
}
