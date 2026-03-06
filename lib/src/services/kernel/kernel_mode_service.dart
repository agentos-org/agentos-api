import 'package:agentos_kernel/agentos_kernel.dart';

enum AgentOSKernelMode { economy, balanced, performance }

class KernelModeService {
  KernelModeService({required Future<KernelService?> kernelFuture})
    : _kernelFuture = kernelFuture;

  final Future<KernelService?> _kernelFuture;

  Future<AgentOSKernelMode> getMode() async {
    final kernel = await _resolveKernel();
    return _toAgentOSMode(kernel.getMode());
  }

  Future<void> setMode(AgentOSKernelMode mode) async {
    final kernel = await _resolveKernel();
    kernel.setMode(_toKernelMode(mode));
  }

  Future<KernelService?> resolveKernel() => _kernelFuture;

  Future<KernelService> _resolveKernel() async {
    final kernel = await _kernelFuture;
    if (kernel == null) {
      throw StateError('Kernel is not configured.');
    }
    return kernel;
  }

  AgentOSKernelMode _toAgentOSMode(KernelMode mode) {
    switch (mode) {
      case KernelMode.economy:
        return AgentOSKernelMode.economy;
      case KernelMode.balanced:
        return AgentOSKernelMode.balanced;
      case KernelMode.performance:
        return AgentOSKernelMode.performance;
    }
  }

  KernelMode _toKernelMode(AgentOSKernelMode mode) {
    switch (mode) {
      case AgentOSKernelMode.economy:
        return KernelMode.economy;
      case AgentOSKernelMode.balanced:
        return KernelMode.balanced;
      case AgentOSKernelMode.performance:
        return KernelMode.performance;
    }
  }
}
