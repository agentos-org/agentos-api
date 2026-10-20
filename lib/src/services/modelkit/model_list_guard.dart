import '../../locator.dart';

/// 装配期发现的 id 冲突：[dropped] 因与 [kept] 的 id 相同而被排除出路由。
class ModelIdConflict {
  const ModelIdConflict({
    required this.id,
    required this.kept,
    required this.dropped,
  });

  /// 冲突的 id。
  final String id;

  /// 保留的模型。
  final LlmModelInfo kept;

  /// 被丢弃的模型。
  final LlmModelInfo dropped;
}

/// [dedupeModelsById] 的结果。
class ModelListDedupResult {
  const ModelListDedupResult({required this.models, required this.conflicts});

  /// 去重后的模型列表，保持输入的相对顺序。
  final List<LlmModelInfo> models;

  /// 被丢弃的重复项；没有冲突时为空。
  final List<ModelIdConflict> conflicts;
}

/// 按 id 对模型列表去重：同一个 id 只保留一个，其余排除出路由。
///
/// 保留规则：第一方模型（本地 / 平台 / 自定义）优先于应用模型；同一层级内取列表中先出现的。
/// 这样应用模型即使与第一方模型 id 相同，也只会被丢弃，而不是反过来遮蔽第一方模型，
/// 或者在路由里静默地“先到先得”。空 id 不参与去重。
ModelListDedupResult dedupeModelsById(List<LlmModelInfo> models) {
  final winners = <String, LlmModelInfo>{};
  for (final model in models) {
    if (model.id.isEmpty || model.isAppModel) continue;
    winners.putIfAbsent(model.id, () => model);
  }
  for (final model in models) {
    if (model.id.isEmpty || !model.isAppModel) continue;
    winners.putIfAbsent(model.id, () => model);
  }

  final kept = <LlmModelInfo>[];
  final conflicts = <ModelIdConflict>[];
  for (final model in models) {
    if (model.id.isEmpty) {
      kept.add(model);
      continue;
    }
    final winner = winners[model.id]!;
    if (identical(winner, model)) {
      kept.add(model);
    } else {
      conflicts.add(
        ModelIdConflict(id: model.id, kept: winner, dropped: model),
      );
    }
  }
  return ModelListDedupResult(models: kept, conflicts: conflicts);
}

/// 为 OpenAI 兼容的模型列表（`/modelkit/chat/models`）确定每个模型最终输出的 `id`。
///
/// [labels] 与 [models] 一一对应，是各模型的菜单标签（`alias (name)` / `name`，可为 null）。
/// 标签在整个列表内唯一时输出标签；标签缺失，或与其他模型的标签冲突时，
/// 冲突项都回退为真实 id（真实 id 在列表内唯一，客户端一定能精确寻址）。
List<String> resolveMenuIds({
  required List<LlmModelInfo> models,
  required List<String?> labels,
}) {
  assert(models.length == labels.length);
  final counts = <String, int>{};
  for (final label in labels) {
    if (label == null) continue;
    counts[label] = (counts[label] ?? 0) + 1;
  }
  return [
    for (var i = 0; i < models.length; i++)
      (labels[i] != null && counts[labels[i]] == 1) ? labels[i]! : models[i].id,
  ];
}
