import 'package:agentos_kernel/agentos_kernel.dart';
import 'package:liteagent_sdk_dart/liteagent_sdk_dart.dart';

class IntentKitService {
  IntentKitService({required Future<KernelService?> kernelFuture})
      : _kernelFuture = kernelFuture;

  final Future<KernelService?> _kernelFuture;

  Future<JobHandle> submitRaw({
    required String source,
    required List<Content> content,
    Map<String, dynamic>? data,
  }) async {
    final kernel = await _resolveKernel();
    return kernel.submitRaw(source: source, content: content, data: data);
  }

  Future<JobHandle> submitIntent({
    required String source,
    required IntentCandidateDto intent,
  }) async {
    final kernel = await _resolveKernel();
    return kernel.submitIntent(source: source, intent: intent);
  }

  Future<JobHandle> confirmJob({
    required String jobId,
    required bool confirmed,
  }) async {
    final kernel = await _resolveKernel();
    return kernel.confirmJob(jobId, confirmed: confirmed);
  }

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
