import '../../locator.dart';

/// 一次模型标识解析的结果。
class ModelResolution {
  const ModelResolution({this.model, this.warnings = const []});

  /// 命中的模型；未命中为 null。
  final LlmModelInfo? model;

  /// 解析过程中产生的告警（同层级多个匹配等），
  /// 由调用方决定如何记录。
  final List<String> warnings;

  /// 是否命中模型。
  bool get found => model != null;
}

/// 把客户端给出的模型标识展开为可能命中 [LlmModelInfo] 的候选列表。
///
/// 兼容菜单标签格式 `alias (name)`：除原文外，还会依次给出括号内的 name 与括号前的 alias。
List<String> modelIdentifierCandidates(String identifier) {
  final trimmed = identifier.trim();
  if (trimmed.isEmpty) return const [];

  final candidates = <String>[trimmed];

  if (trimmed.endsWith(')')) {
    final open = trimmed.lastIndexOf('(');
    if (open > 0) {
      final inner = trimmed.substring(open + 1, trimmed.length - 1).trim();
      final outer = trimmed.substring(0, open).trim();
      if (inner.isNotEmpty) candidates.add(inner);
      if (outer.isNotEmpty) candidates.add(outer);
    }
  }

  return candidates;
}

/// 按分层规则把客户端给出的模型标识解析为模型。
///
/// 解析顺序（前一层命中即返回）：
/// 1. 精确匹配 id（应用模型的 id 是网关生成的 12 位 hashid）；
/// 2. 第一方模型（本地 / 平台 / 自定义）的 alias，再 name；
/// 3. 应用模型的 alias，再 name。
///
/// 这样应用注册的 alias / name 都不可能压过第一方模型：例如应用把 alias 设成
/// `gpt-4o`，按 name 寻址 `gpt-4o` 的请求依然命中第一方模型。
///
/// 同一层级匹配到多个模型时取列表中的第一个，并在 [ModelResolution.warnings] 里给出告警。
ModelResolution resolveModelIdentifier(
  List<LlmModelInfo> models,
  String identifier,
) {
  return _resolve(
    models,
    modelIdentifierCandidates(identifier),
    includeAliasAndName: true,
  );
}

/// 按 id 解析模型：只做精确匹配 id。
///
/// 供只接受“模型 id”的调用方使用（AgentKit / CronKit 的 `modelId`），不做 alias / name 匹配。
ModelResolution resolveModelId(List<LlmModelInfo> models, String id) {
  if (id.isEmpty) return const ModelResolution();
  return _resolve(models, [id], includeAliasAndName: false);
}

ModelResolution _resolve(
  List<LlmModelInfo> models,
  List<String> candidates, {
  required bool includeAliasAndName,
}) {
  if (candidates.isEmpty) return const ModelResolution();
  final warnings = <String>[];

  // 1. 精确 id。列表顺序即第一方优先（应用模型 hashid 与第一方 id 极小概率重复时第一方胜出）。
  for (final candidate in candidates) {
    for (final model in models) {
      if (model.id == candidate) return ModelResolution(model: model);
    }
  }

  final firstParty = models.where((m) => !m.isAppModel).toList(growable: false);
  final apps = models.where((m) => m.isAppModel).toList(growable: false);

  // 2. 第一方 alias → name。
  if (includeAliasAndName) {
    final byAlias = _matchByField(
      firstParty,
      candidates,
      (m) => m.alias,
      field: 'alias',
      tier: '第一方',
      warnings: warnings,
    );
    if (byAlias != null) {
      return ModelResolution(model: byAlias, warnings: warnings);
    }
    final byName = _matchByField(
      firstParty,
      candidates,
      (m) => m.name,
      field: 'name',
      tier: '第一方',
      warnings: warnings,
    );
    if (byName != null) {
      return ModelResolution(model: byName, warnings: warnings);
    }
  }

  // 3. 应用模型 alias → name。
  if (includeAliasAndName) {
    final byAlias = _matchByField(
      apps,
      candidates,
      (m) => m.alias,
      field: 'alias',
      tier: '应用',
      warnings: warnings,
    );
    if (byAlias != null) {
      return ModelResolution(model: byAlias, warnings: warnings);
    }
    final byName = _matchByField(
      apps,
      candidates,
      (m) => m.name,
      field: 'name',
      tier: '应用',
      warnings: warnings,
    );
    if (byName != null) {
      return ModelResolution(model: byName, warnings: warnings);
    }
  }

  return ModelResolution(warnings: warnings);
}

/// 在 [pool] 内按 [field] 匹配 [candidates]（按候选顺序），命中多个时取第一个并追加告警。
LlmModelInfo? _matchByField(
  List<LlmModelInfo> pool,
  List<String> candidates,
  String Function(LlmModelInfo) valueOf, {
  required String field,
  required String tier,
  required List<String> warnings,
}) {
  for (final candidate in candidates) {
    final matches = pool
        .where((m) {
          final value = valueOf(m);
          return value.isNotEmpty && value == candidate;
        })
        .toList(growable: false);
    if (matches.isEmpty) continue;
    if (matches.length > 1) {
      warnings.add(
        '标识 "$candidate" 按 $field 匹配到 ${matches.length} 个$tier模型'
        '（${matches.map((m) => m.id).join(", ")}），将使用列表中的第一个 ${matches.first.id}；'
        '建议改用完整 id',
      );
    }
    return matches.first;
  }
  return null;
}
