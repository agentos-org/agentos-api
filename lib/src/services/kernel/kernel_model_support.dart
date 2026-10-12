import 'package:agentos_kernel/agentos_kernel.dart' as kernel;

import '../../locator.dart';

const Set<String> _nonTextInferenceModelDenylist = {
  'embedding',
  'llm_embedding',
  // 决策模型只回答打分题，不生成文本，不能同步给 Kernel 作为文本推理模型。
  'decision',
  'llm_decision',
  'text_to_speech',
  'texttospeech',
  'tts',
  'audio_text_to_text',
  'audiotexttotext',
  'asr',
};

List<kernel.KernelLlmModel> buildKernelLlmModels(
  List<LlmModelInfo> models, {
  String? llmBaseUrl,
  String? llmApiKey,
  String? fallbackModel,
}) {
  final mapped = models
      .where(supportsTextInference)
      .where((model) {
        if (model.isRemote) return true;
        return llmBaseUrl != null && llmBaseUrl.isNotEmpty;
      })
      .map(
        (model) => kernel.KernelLlmModel(
          baseUrl: model.baseUrl ?? llmBaseUrl!,
          apiKey: model.apiKey ?? llmApiKey ?? '',
          model: model.name,
          type: model.type,
          description: model.description,
          parameters: model.parameters,
          paramsB: model.paramsB,
          quantization: model.quantization,
          sizeGB: model.sizeGB,
          contextWindowSize: model.contextWindowSize,
          provider: model.provider,
        ),
      )
      .toList();
  if (mapped.isNotEmpty) {
    return mapped;
  }
  final fallback = fallbackModel?.trim();
  if (fallback == null || fallback.isEmpty || llmBaseUrl == null) {
    return const [];
  }
  return [
    kernel.KernelLlmModel(
      baseUrl: llmBaseUrl,
      apiKey: llmApiKey ?? '',
      model: fallback,
      description: 'Configured model',
      parameters: fallback,
      paramsB: 0,
      quantization: 'unknown',
      sizeGB: 0,
    ),
  ];
}

bool supportsTextInference(LlmModelInfo model) {
  final normalizedTask = model.task?.trim().toLowerCase();
  if (normalizedTask != null && normalizedTask.isNotEmpty) {
    return normalizedTask == 'chat';
  }
  final normalizedType = model.type.trim().toLowerCase();
  if (normalizedType.isEmpty) {
    return true;
  }
  if (_nonTextInferenceModelDenylist.contains(normalizedType)) {
    return false;
  }
  if (normalizedType.contains('embedding') ||
      normalizedType.contains('speech') ||
      normalizedType.contains('audio') ||
      normalizedType.contains('asr') ||
      normalizedType.contains('tts')) {
    return false;
  }
  return true;
}

bool supportsEmbeddingInference(LlmModelInfo model) {
  final normalizedTask = model.task?.trim().toLowerCase();
  if (normalizedTask == 'embedding') {
    return true;
  }
  final normalizedType = model.type.trim().toLowerCase();
  final normalizedParameters = model.parameters.trim().toLowerCase();
  if (normalizedType.contains('embedding') ||
      normalizedParameters.contains('embedding')) {
    return true;
  }
  return model.tags.any(
    (tag) => tag.trim().toLowerCase().contains('embedding'),
  );
}
