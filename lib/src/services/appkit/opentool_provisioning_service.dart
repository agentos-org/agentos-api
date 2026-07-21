import 'dart:async';

import 'package:opentool_daemon/opentool_daemon_client.dart';
import 'package:pub_semver/pub_semver.dart';

import '../../config.dart';
import '../../locator.dart';
import '../../models/app/app_models.dart';

const String _runningToolStatus = 'running';

typedef OpenToolProvisionFailureHandler =
    void Function(OpenToolProvisioningFailure failure);
typedef OpenToolProvisionSuccessHandler =
    void Function(OpenToolProvisioningSuccess success);

abstract interface class OpenToolProvisioner {
  Future<OpenToolRegistrationDto> ensureRunning(
    OpenToolServerDeclarationDto declaration, {
    required OpenToolProvisionSuccessHandler onSuccess,
    required OpenToolProvisionFailureHandler onFailure,
  });
}

class OpenToolProvisioningSuccess {
  const OpenToolProvisioningSuccess({
    required this.declaration,
    required this.server,
    required this.id,
  });

  final OpenToolServerDeclarationDto declaration;
  final OpenToolResolvedServerDto server;
  final String id;

  Map<String, dynamic> toEventData() => {
    'ref': declaration.ref,
    'name': declaration.name,
    'status': OpenToolRegistrationStatus.running,
    'server': server.toJson(),
    'id': id,
  };
}

class OpenToolProvisioningFailure {
  const OpenToolProvisioningFailure({
    required this.declaration,
    required this.code,
    required this.message,
    this.server,
  });

  final OpenToolServerDeclarationDto declaration;
  final OpenToolResolvedServerDto? server;
  final String code;
  final String message;

  Map<String, dynamic> toEventData() => {
    'ref': declaration.ref,
    'name': declaration.name,
    'status': 'failed',
    if (server != null) 'server': server!.toJson(),
    'error': {'code': code, 'message': message},
  };
}

abstract interface class OpenToolDaemonGateway {
  Future<List<OpenToolServerDto>> listServers();

  Future<List<ToolDto>> listTools();

  Future<bool> isReady(String toolId);

  Future<String> waitUntilReady(String toolId);

  Future<String> startAndWait(String toolId);

  Future<String> createAndWait(String serverId);
}

typedef OpenToolDaemonGatewayFactory =
    Future<OpenToolDaemonGateway?> Function();

class OpenToolProvisioningService implements OpenToolProvisioner {
  OpenToolProvisioningService({
    required AgentOSServiceLocator serviceLocator,
    OpenToolDaemonGatewayFactory? gatewayFactory,
    this.lookupTimeout = const Duration(seconds: 2),
  }) : _serviceLocator = serviceLocator,
       _gatewayFactory = gatewayFactory;

  final AgentOSServiceLocator _serviceLocator;
  final OpenToolDaemonGatewayFactory? _gatewayFactory;
  final Duration lookupTimeout;
  final Map<String, Future<_OpenToolProvisionAttemptResult>> _inFlight = {};

  @override
  Future<OpenToolRegistrationDto> ensureRunning(
    OpenToolServerDeclarationDto declaration, {
    required OpenToolProvisionSuccessHandler onSuccess,
    required OpenToolProvisionFailureHandler onFailure,
  }) async {
    OpenToolDaemonGateway? gateway;
    try {
      gateway = await _createGateway().timeout(lookupTimeout);
    } catch (error) {
      _reportLater(
        onFailure,
        OpenToolProvisioningFailure(
          declaration: declaration,
          code: 'daemonUnavailable',
          message: error.toString(),
        ),
      );
      return _starting(declaration);
    }

    if (gateway == null) {
      _reportLater(
        onFailure,
        OpenToolProvisioningFailure(
          declaration: declaration,
          code: 'daemonUnavailable',
          message: 'OpenTool daemon is not available',
        ),
      );
      return _starting(declaration);
    }

    try {
      final servers = await gateway.listServers().timeout(lookupTimeout);
      final server = _resolveServer(servers, declaration.name);
      if (server == null) {
        return OpenToolRegistrationDto(
          ref: declaration.ref,
          name: declaration.name,
          status: OpenToolRegistrationStatus.notFound,
        );
      }

      final resolvedServer = _resolvedServer(server);
      final tools = await gateway.listTools().timeout(lookupTimeout);
      final matchingTools = tools
          .where((tool) => _toolMatchesServer(tool, server))
          .toList();
      final runningTools = matchingTools
          .where((tool) => tool.status == _runningToolStatus)
          .toList();
      final candidateTools = [
        ...runningTools,
        ...matchingTools.where((tool) => tool.status != _runningToolStatus),
      ];
      ToolDto? readyTool;
      for (final tool in candidateTools) {
        if (await gateway.isReady(tool.id).timeout(lookupTimeout)) {
          readyTool = tool;
          break;
        }
      }

      if (readyTool != null) {
        return OpenToolRegistrationDto(
          ref: declaration.ref,
          name: declaration.name,
          server: resolvedServer,
          status: OpenToolRegistrationStatus.running,
          id: readyTool.id,
        );
      }

      final existingTool = runningTools.isNotEmpty
          ? runningTools.first
          : (matchingTools.isEmpty ? null : matchingTools.first);
      final action = existingTool == null
          ? () => gateway!.createAndWait(server.id)
          : () => gateway!.startAndWait(existingTool.id);
      final failureCode = existingTool == null ? 'createFailed' : 'startFailed';

      final provisionKey = server.id;
      final task = _inFlight.putIfAbsent(
        provisionKey,
        () => _runProvisioning(
          server: resolvedServer,
          failureCode: failureCode,
          action: action,
        ),
      );
      unawaited(
        task.then((result) {
          final toolId = result.toolId;
          if (toolId != null) {
            onSuccess(
              OpenToolProvisioningSuccess(
                declaration: declaration,
                server: result.server,
                id: toolId,
              ),
            );
          } else {
            onFailure(
              OpenToolProvisioningFailure(
                declaration: declaration,
                server: result.server,
                code: result.failureCode!,
                message: result.failureMessage!,
              ),
            );
          }
        }),
      );
      unawaited(
        task.whenComplete(() {
          if (identical(_inFlight[provisionKey], task)) {
            _inFlight.remove(provisionKey);
          }
        }),
      );

      return OpenToolRegistrationDto(
        ref: declaration.ref,
        name: declaration.name,
        server: resolvedServer,
        status: OpenToolRegistrationStatus.starting,
      );
    } catch (error) {
      _reportLater(
        onFailure,
        OpenToolProvisioningFailure(
          declaration: declaration,
          code: 'provisionFailed',
          message: error.toString(),
        ),
      );
      return _starting(declaration);
    }
  }

  Future<OpenToolDaemonGateway?> _createGateway() async {
    final factory = _gatewayFactory;
    if (factory != null) {
      return factory();
    }
    final port = await _serviceLocator.getServicePort(
      ApiConfig.serviceOpentool,
    );
    if (port == null) {
      return null;
    }
    return DaemonOpenToolGateway(
      DaemonClient(host: _serviceLocator.openToolDaemonHost, port: port),
    );
  }

  Future<_OpenToolProvisionAttemptResult> _runProvisioning({
    required OpenToolResolvedServerDto server,
    required String failureCode,
    required Future<String> Function() action,
  }) async {
    try {
      final toolId = await action();
      return _OpenToolProvisionAttemptResult.success(
        server: server,
        toolId: toolId,
      );
    } catch (error) {
      return _OpenToolProvisionAttemptResult.failure(
        server: server,
        failureCode: failureCode,
        failureMessage: error.toString(),
      );
    }
  }

  void _reportLater(
    OpenToolProvisionFailureHandler handler,
    OpenToolProvisioningFailure failure,
  ) {
    scheduleMicrotask(() => handler(failure));
  }

  OpenToolRegistrationDto _starting(OpenToolServerDeclarationDto declaration) {
    return OpenToolRegistrationDto(
      ref: declaration.ref,
      name: declaration.name,
      status: OpenToolRegistrationStatus.starting,
    );
  }

  OpenToolServerDto? _resolveServer(
    List<OpenToolServerDto> servers,
    String name,
  ) {
    final matching = servers.where((server) => server.name == name).toList();
    if (matching.isEmpty) return null;
    if (matching.length == 1) return matching.first;

    final versioned = <({OpenToolServerDto server, Version version})>[];
    for (final server in matching) {
      try {
        versioned.add((server: server, version: Version.parse(server.tag)));
      } on FormatException {
        // Non-semver tags keep the daemon's existing ordering fallback.
      }
    }
    if (versioned.isEmpty) return matching.first;

    versioned.sort((left, right) => right.version.compareTo(left.version));
    return versioned.first.server;
  }

  bool _toolMatchesServer(ToolDto tool, OpenToolServerDto server) {
    if (tool.serverId == server.id) return true;
    final source = tool.server;
    return source != null &&
        source.repo == server.repo &&
        source.name == server.name &&
        source.tag == server.tag;
  }

  OpenToolResolvedServerDto _resolvedServer(OpenToolServerDto server) {
    return OpenToolResolvedServerDto(
      repo: server.repo,
      name: server.name,
      tag: server.tag,
    );
  }
}

class _OpenToolProvisionAttemptResult {
  const _OpenToolProvisionAttemptResult.success({
    required this.server,
    required this.toolId,
  }) : failureCode = null,
       failureMessage = null;

  const _OpenToolProvisionAttemptResult.failure({
    required this.server,
    required this.failureCode,
    required this.failureMessage,
  }) : toolId = null,
       assert(failureCode != null),
       assert(failureMessage != null);

  final OpenToolResolvedServerDto server;
  final String? toolId;
  final String? failureCode;
  final String? failureMessage;
}

class DaemonOpenToolGateway implements OpenToolDaemonGateway {
  DaemonOpenToolGateway(
    this._client, {
    this.readinessTimeout = const Duration(seconds: 90),
    this.pollInterval = const Duration(seconds: 1),
    this.startupGracePeriod = const Duration(seconds: 5),
  });

  final DaemonClient _client;
  final Duration readinessTimeout;
  final Duration pollInterval;
  final Duration startupGracePeriod;

  @override
  Future<List<OpenToolServerDto>> listServers() => _client.listServer();

  @override
  Future<List<ToolDto>> listTools() => _client.listTool('1');

  @override
  Future<bool> isReady(String toolId) async {
    try {
      return await _client.loadTool(toolId) != null;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<String> createAndWait(String serverId) async {
    final existingIds = (await listTools())
        .where((tool) => tool.serverId == serverId)
        .map((tool) => tool.id)
        .toSet();
    await _client.runServer(serverId, null).timeout(readinessTimeout);
    final tools = await listTools();
    final createdId = await _firstReadyToolId(
      tools.where(
        (tool) => tool.serverId == serverId && !existingIds.contains(tool.id),
      ),
    );
    if (createdId != null) {
      return createdId;
    }
    final readyId = await _firstReadyToolId(
      tools.where((tool) => tool.serverId == serverId),
    );
    if (readyId != null) {
      return readyId;
    }
    throw StateError(
      'OpenTool daemon completed server $serverId without a ready tool',
    );
  }

  @override
  Future<String> startAndWait(String toolId) async {
    Object? streamFailure;
    StackTrace? streamFailureStack;
    await _client.startTool(
      toolId,
      timeoutSeconds: 0,
      onData: (_) {},
      onError: (result) {
        streamFailure = StateError(result.error ?? 'OpenTool start failed');
      },
      onStreamError: (error, stackTrace) {
        streamFailure = error;
        streamFailureStack = stackTrace;
      },
    );
    if (streamFailure != null) {
      Error.throwWithStackTrace(
        streamFailure!,
        streamFailureStack ?? StackTrace.current,
      );
    }
    return waitUntilReady(toolId);
  }

  @override
  Future<String> waitUntilReady(String toolId) async {
    final deadline = DateTime.now().add(readinessTimeout);
    final startupDeadline = DateTime.now().add(startupGracePeriod);
    var observedRunning = false;
    while (DateTime.now().isBefore(deadline)) {
      if (await isReady(toolId)) {
        return toolId;
      }
      final tools = await listTools();
      final tool = _toolWithId(tools, toolId);
      if (tool == null) {
        throw StateError('OpenTool $toolId was removed before becoming ready');
      }
      if (tool.status == _runningToolStatus) {
        observedRunning = true;
      } else if (observedRunning || !DateTime.now().isBefore(startupDeadline)) {
        throw StateError('OpenTool $toolId stopped before becoming ready');
      }
      await Future<void>.delayed(pollInterval);
    }
    throw TimeoutException(
      'OpenTool $toolId did not become ready',
      readinessTimeout,
    );
  }

  Future<String?> _firstReadyToolId(Iterable<ToolDto> tools) async {
    for (final tool in tools) {
      if (tool.status == _runningToolStatus && await isReady(tool.id)) {
        return tool.id;
      }
    }
    return null;
  }

  ToolDto? _toolWithId(List<ToolDto> tools, String toolId) {
    for (final tool in tools) {
      if (tool.id == toolId) {
        return tool;
      }
    }
    return null;
  }
}
