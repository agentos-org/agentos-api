import 'package:agentos_kernel/agentos_kernel.dart';
import 'package:liteagent_sdk_dart/liteagent_sdk_dart.dart';

class IntentKitService {
  IntentKitService({required Future<KernelService?> kernelFuture})
      : _kernelFuture = kernelFuture;

  final Future<KernelService?> _kernelFuture;

  @Deprecated(
    'IntentKit submitRaw is deprecated and will be removed in a future release. '
    'Intent triggers too frequently, and current LLM response speed is not yet '
    'fast enough. To reserve model compute for direct user interactions, prefer '
    'direct execution-oriented APIs.',
  )
  Future<JobHandle> submitRaw({
    required String source,
    required List<Content> content,
    Map<String, dynamic>? data,
  }) async {
    final kernel = await _resolveKernel();
    return kernel.submitRaw(source: source, content: content, data: data);
  }

  @Deprecated(
    'IntentKit submitIntent is deprecated and will be removed in a future release. '
    'Intent triggers too frequently, and current LLM response speed is not yet '
    'fast enough. To reserve model compute for direct user interactions, prefer '
    'direct execution-oriented APIs.',
  )
  Future<JobHandle> submitIntent({
    required String source,
    required IntentCandidateDto intent,
  }) async {
    final kernel = await _resolveKernel();
    return kernel.submitIntent(source: source, intent: intent);
  }

  @Deprecated(
    'IntentKit confirmJob is deprecated and will be removed in a future release. '
    'Intent triggers too frequently, and current LLM response speed is not yet '
    'fast enough. To reserve model compute for direct user interactions, prefer '
    'direct execution-oriented APIs.',
  )
  Future<JobHandle> confirmJob({
    required String jobId,
    required bool confirmed,
  }) async {
    final kernel = await _resolveKernel();
    return kernel.confirmJob(jobId, confirmed: confirmed);
  }

  @Deprecated(
    'IntentKit suggestNextAction is deprecated and will be removed in a future release. '
    'Intent triggers too frequently, and current LLM response speed is not yet '
    'fast enough. To reserve model compute for direct user interactions, prefer '
    'direct execution-oriented APIs.',
  )
  Future<IntentResponseDto> suggestNextAction({
    required String source,
    List<String>? allowedActions,
    int? memoryLimit,
  }) async {
    final kernel = await _resolveKernel();
    return kernel.suggestNextAction(
      source: source,
      allowedActions: allowedActions,
      memoryLimit: memoryLimit ?? 5,
    );
  }

  Future<KernelService?> resolveKernel() => _kernelFuture;

  Future<KernelService> _resolveKernel() async {
    final kernel = await _kernelFuture;
    if (kernel == null) {
      throw StateError('IntentKit is not configured.');
    }
    return kernel;
  }
}
