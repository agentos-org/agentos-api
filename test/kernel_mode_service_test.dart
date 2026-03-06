import 'package:agentos_api/agentos_api.dart';
import 'package:agentos_kernel/agentos_kernel.dart';
import 'package:test/test.dart';

class _FakeKernelService implements KernelService {
  _FakeKernelService({this.mode = KernelMode.balanced});

  KernelMode mode;

  @override
  KernelMode getMode() => mode;

  @override
  void setMode(KernelMode mode) {
    this.mode = mode;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not mocked');
}

void main() {
  test('KernelModeService reads performance mode from kernel', () async {
    final service = KernelModeService(
      kernelFuture: Future.value(
        _FakeKernelService(mode: KernelMode.performance),
      ),
    );

    expect(await service.getMode(), AgentOSKernelMode.performance);
  });

  test('KernelModeService writes performance mode to kernel', () async {
    final kernel = _FakeKernelService();
    final service = KernelModeService(kernelFuture: Future.value(kernel));

    await service.setMode(AgentOSKernelMode.performance);

    expect(kernel.mode, KernelMode.performance);
  });
}
