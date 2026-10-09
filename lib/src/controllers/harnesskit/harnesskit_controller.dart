import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../../middleware.dart';
import '../../services/appkit/appkit_service.dart';
import '../../services/harnesskit/harnesskit_client.dart';

/// Gateway bridge for authenticated HarnessKit App bundles.
///
/// Requests must carry a valid AppKit bundle token. The built-in Harness uses
/// the shared host runtime; opted-in process Apps are forwarded to that same
/// runtime. The App process never serves the HarnessKit protocol.
class HarnessKitController {
  HarnessKitController({
    HarnessKitClient? client,
    HarnessKitClientRegistry? clientRegistry,
    Map<String, bool>? harnessKitAppToolkits,
    required AppKitService appKitService,
    this.bundleId = defaultHarnessKitBundleId,
  }) : _client = client,
       _clientRegistry = clientRegistry,
       _harnessKitAppToolkits = harnessKitAppToolkits,
       _appKitService = appKitService {
    if (client == null &&
        clientRegistry == null &&
        harnessKitAppToolkits == null) {
      throw ArgumentError(
        'A HarnessKit client or client registry must be provided',
      );
    }
  }

  final HarnessKitClient? _client;
  final HarnessKitClientRegistry? _clientRegistry;
  final Map<String, bool>? _harnessKitAppToolkits;
  final AppKitService _appKitService;
  final String bundleId;
  final Map<String, String> _scopedRunOwners = <String, String>{};

  Router get router {
    final router = Router();
    final guard = requireBearer();
    router.all('/', guard(_forwardRoot));
    router.all('/<path|.*>', guard(_forwardPath));
    return router;
  }

  Future<Response> _forwardRoot(Request request) =>
      _forward(request, path: '/');

  Future<Response> _forwardPath(Request request) {
    final rawPath = request.params['path'] ?? '';
    return _forward(request, path: rawPath.isEmpty ? '/' : '/$rawPath');
  }

  Future<Response> _forward(Request request, {required String path}) async {
    final token = bearerTokenFrom(request);
    if (token == null || token.isEmpty || !_appKitService.isTokenValid(token)) {
      requestLogger.warning('HarnessKit: invalid bearer token.');
      return unauthorizedResponse();
    }
    final appBundleId = _appKitService.bundleIdForToken(token);
    if (appBundleId == null) {
      requestLogger.warning('HarnessKit: token has no AppKit bundle.');
      return unauthorizedResponse();
    }
    final isHarnessApp = appBundleId == bundleId;
    final scope = isHarnessApp ? null : _HarnessKitBundleScope(appBundleId);
    final isRegisteredHarnessKitApp =
        _harnessKitAppToolkits?.containsKey(appBundleId) ?? false;
    if (!isHarnessApp &&
        (RegExp(r'^/v1/runtime/harness-engine/*$').hasMatch(path) ||
            path == '/v1/ops/snapshot')) {
      requestLogger.warning(
        'HarnessKit: host runtime access denied for $appBundleId.',
      );
      return Response(
        403,
        body: jsonEncode({
          'error': {
            'code': 'harness_host_access_forbidden',
            'message':
                'Only the built-in Harness App can access host runtime controls',
          },
        }),
        headers: const {'content-type': 'application/json'},
      );
    }
    final client = isHarnessApp
        ? _client ?? _clientRegistry?.resolve(appBundleId)
        : _clientRegistry?.resolve(appBundleId) ??
              (isRegisteredHarnessKitApp ? _client : null);
    if (client == null) {
      requestLogger.warning('HarnessKit: no runtime for authorized bundle.');
      return unauthorizedResponse();
    }

    try {
      final requestBody = await _readBodyBytes(request);
      final scopedPath = scope?.scopeRequestPath(path) ?? path;
      final scopedQuery =
          scope?.scopeRequestQuery(path, request.url.queryParameters) ??
          request.url.queryParameters;
      final scopedBody = scope?.scopeRequestBody(requestBody) ?? requestBody;
      final response = await client.send(
        method: request.method,
        path: scopedPath,
        headers: request.headers,
        queryParameters: scopedQuery,
        body: _applyAppToolPolicy(
          method: request.method,
          path: scopedPath,
          body: scopedBody,
          toolkitEnabled: isHarnessApp
              ? true
              : _harnessKitAppToolkits?[appBundleId] ?? true,
        ),
        streamResponse: _isStreamingRequest(request, path),
        actorBundleId: appBundleId,
      );
      final runOwner = scope?.runOwnerFromResponse(path, response.bodyBytes);
      if (runOwner != null) {
        _scopedRunOwners[_runOwnerKey(appBundleId, runOwner.key)] =
            runOwner.value;
        if (_scopedRunOwners.length > 4096) {
          _scopedRunOwners.remove(_scopedRunOwners.keys.first);
        }
      }
      if (scope != null &&
          request.method.toUpperCase() == 'GET' &&
          RegExp(r'^/v1/runs/[^/]+/result$').hasMatch(path) &&
          response.statusCode >= 200 &&
          response.statusCode < 300) {
        final runtimeRunId = scope.runtimeRunIdFromResultPath(path);
        final knownThreadId = runtimeRunId == null
            ? null
            : _scopedRunOwners[_runOwnerKey(appBundleId, runtimeRunId)];
        if (!scope.runResultBelongsToBundle(
          response.bodyBytes,
          knownThreadId: knownThreadId,
        )) {
          return Response(
            404,
            body: jsonEncode({
              'error': {'code': 'not_found', 'message': 'Unknown run'},
            }),
            headers: const {'content-type': 'application/json'},
          );
        }
      }
      if (response.bodyStream != null) {
        final bodyStream = scope != null && path.endsWith('/events')
            ? _scopeEventStream(response.bodyStream!, scope)
            : response.bodyStream!;
        return Response(
          response.statusCode,
          body: bodyStream,
          headers: response.headers,
          context: const {'shelf.io.buffer_output': false},
        );
      }
      final bodyBytes = scope == null
          ? response.bodyBytes
          : scope.rewriteResponseBody(
              method: request.method,
              path: path,
              statusCode: response.statusCode,
              body: response.bodyBytes,
            );
      return Response(
        response.statusCode,
        body: bodyBytes,
        headers: response.headers,
      );
    } catch (error) {
      requestLogger.warning('HarnessKit proxy unavailable: $error');
      return Response(
        502,
        body: jsonEncode({
          'error': {
            'code': 'harness_unavailable',
            'message': 'Harness service unavailable',
          },
        }),
        headers: const {'content-type': 'application/json'},
      );
    }
  }

  String _runOwnerKey(String appBundleId, String runtimeRunId) =>
      '$appBundleId\u0000$runtimeRunId';

  Stream<List<int>> _scopeEventStream(
    Stream<List<int>> source,
    _HarnessKitBundleScope scope,
  ) async* {
    final frame = <String>[];
    var pending = '';

    await for (final chunk in source.transform(utf8.decoder)) {
      pending += chunk;
      while (true) {
        final newline = pending.indexOf('\n');
        if (newline < 0) break;
        var line = pending.substring(0, newline);
        pending = pending.substring(newline + 1);
        if (line.endsWith('\r')) line = line.substring(0, line.length - 1);
        if (line.isEmpty) {
          final rewritten = scope.rewriteSseFrame(frame);
          if (rewritten.isNotEmpty) yield utf8.encode('$rewritten\n\n');
          frame.clear();
        } else {
          frame.add(line);
        }
      }
    }
    if (pending.isNotEmpty) frame.add(pending);
    if (frame.isNotEmpty) {
      final rewritten = scope.rewriteSseFrame(frame);
      if (rewritten.isNotEmpty) yield utf8.encode('$rewritten\n\n');
    }
  }

  bool _isStreamingRequest(Request request, String path) {
    final accept = request.headers['accept']?.toLowerCase() ?? '';
    return accept.contains('text/event-stream') || path.endsWith('/events');
  }

  Future<List<int>?> _readBodyBytes(Request request) async {
    if (request.method == 'GET' || request.method == 'HEAD') return null;
    final bytes = await request.read().fold<List<int>>(<int>[], (buffer, data) {
      buffer.addAll(data);
      return buffer;
    });
    return bytes.isEmpty ? null : bytes;
  }

  List<int>? _applyAppToolPolicy({
    required String method,
    required String path,
    required List<int>? body,
    required bool toolkitEnabled,
  }) {
    if (toolkitEnabled ||
        method.toUpperCase() != 'POST' ||
        !RegExp(r'^/v1/threads/[^/]+/(runs|commands)$').hasMatch(path)) {
      return body;
    }

    Object? decoded;
    try {
      decoded = body == null || body.isEmpty
          ? <String, Object?>{}
          : jsonDecode(utf8.decode(body));
    } on FormatException {
      return body;
    }
    if (decoded is! Map) return body;

    final requestBody = decoded.map<String, Object?>(
      (key, value) => MapEntry(key.toString(), value),
    );
    final rawPolicy = requestBody['toolPolicy'];
    final toolPolicy = rawPolicy is Map
        ? rawPolicy.map<String, Object?>(
            (key, value) => MapEntry(key.toString(), value),
          )
        : <String, Object?>{};
    // A manifest-level opt-out must override any caller-supplied allow-list.
    toolPolicy['allowedToolIds'] = const <String>[];
    requestBody['toolPolicy'] = toolPolicy;
    return utf8.encode(jsonEncode(requestBody));
  }
}

/// Maps an authenticated external App's Harness identifiers into a private
/// namespace inside the shared Harness runtime. The built-in Harness skips
/// this adapter so it keeps its existing IDs and shared sidebar history.
final class _HarnessKitBundleScope {
  _HarnessKitBundleScope(String bundleId)
    : _prefix =
          '__agentos_bundle_${base64Url.encode(utf8.encode(bundleId)).replaceAll('=', '')}_';

  final String _prefix;

  String _encode(String value) =>
      base64Url.encode(utf8.encode(value)).replaceAll('=', '');

  String _decode(String value) {
    final padded = value.padRight(
      value.length + (4 - value.length % 4) % 4,
      '=',
    );
    return utf8.decode(base64Url.decode(padded));
  }

  String _toRuntimeId(String publicId) => '$_prefix${_encode(publicId)}';

  String _toPublicScopedId(String runtimeId) {
    if (!runtimeId.startsWith(_prefix)) return runtimeId;
    try {
      return _decode(runtimeId.substring(_prefix.length));
    } on FormatException {
      return runtimeId;
    }
  }

  String _toPublicRunId(String runtimeId) => '$_prefix${_encode(runtimeId)}';

  String _toRuntimeScopedId(String publicId) {
    if (!publicId.startsWith(_prefix)) return _toRuntimeId(publicId);
    try {
      return _decode(publicId.substring(_prefix.length));
    } on FormatException {
      return _toRuntimeId(publicId);
    }
  }

  String scopeRequestPath(String path) {
    final threadMatch = RegExp(r'^/v1/threads/([^/]+)(/.*)?$').firstMatch(path);
    if (threadMatch != null) {
      final rawId = Uri.decodeComponent(threadMatch.group(1)!);
      final suffix = threadMatch.group(2) ?? '';
      return '/v1/threads/${Uri.encodeComponent(_toRuntimeId(rawId))}$suffix';
    }

    final runMatch = RegExp(r'^/v1/runs/([^/]+)/result$').firstMatch(path);
    if (runMatch != null) {
      final rawId = Uri.decodeComponent(runMatch.group(1)!);
      return '/v1/runs/${Uri.encodeComponent(_toRuntimeScopedId(rawId))}/result';
    }
    return path;
  }

  Map<String, String> scopeRequestQuery(
    String path,
    Map<String, String> query,
  ) {
    if (!path.endsWith('/events') || !query.containsKey('runId')) return query;
    return <String, String>{
      ...query,
      'runId': _toRuntimeScopedId(query['runId']!),
    };
  }

  MapEntry<String, String>? runOwnerFromResponse(
    String requestPath,
    List<int>? body,
  ) {
    if (body == null ||
        !RegExp(r'^/v1/threads/[^/]+/(runs|commands)$').hasMatch(requestPath)) {
      return null;
    }
    try {
      final decoded = jsonDecode(utf8.decode(body));
      if (decoded is! Map) return null;
      final runId = decoded['runId'];
      final threadId = decoded['threadId'];
      if (runId is! String ||
          runId.isEmpty ||
          threadId is! String ||
          !threadId.startsWith(_prefix)) {
        return null;
      }
      return MapEntry(runId, threadId);
    } on FormatException {
      return null;
    }
  }

  String? runtimeRunIdFromResultPath(String path) {
    final match = RegExp(r'^/v1/runs/([^/]+)/result$').firstMatch(path);
    if (match == null) return null;
    return _toRuntimeScopedId(Uri.decodeComponent(match.group(1)!));
  }

  bool runResultBelongsToBundle(
    List<int>? body, {
    required String? knownThreadId,
  }) {
    String? resultThreadId;
    try {
      final decoded = body == null ? null : jsonDecode(utf8.decode(body));
      if (decoded is Map && decoded['summary'] is Map) {
        final summary = decoded['summary'] as Map;
        final threadId = summary['threadId'];
        if (threadId is String) resultThreadId = threadId;
      }
    } on FormatException {
      return false;
    }
    if (resultThreadId != null) {
      return resultThreadId.startsWith(_prefix) &&
          (knownThreadId == null || knownThreadId == resultThreadId);
    }
    return knownThreadId != null && knownThreadId.startsWith(_prefix);
  }

  List<int>? scopeRequestBody(List<int>? body) {
    if (body == null || body.isEmpty) return body;
    try {
      final decoded = jsonDecode(utf8.decode(body));
      if (decoded is! Map) return body;
      final value = decoded.map<String, Object?>(
        (key, value) => MapEntry(key.toString(), value),
      );
      for (final key in const <String>['threadId']) {
        final id = value[key];
        if (id is String) value[key] = _toRuntimeId(id);
      }
      for (final key in const <String>['runId', 'commandId', 'requestId']) {
        final id = value[key];
        if (id is String) value[key] = _toRuntimeId(id);
      }
      final targetRunId = value['targetRunId'];
      if (targetRunId is String) {
        value['targetRunId'] = _toRuntimeScopedId(targetRunId);
      }
      return utf8.encode(jsonEncode(value));
    } on FormatException {
      return body;
    }
  }

  List<int>? rewriteResponseBody({
    required String method,
    required String path,
    required int statusCode,
    required List<int>? body,
  }) {
    if (body == null || body.isEmpty || statusCode < 200 || statusCode >= 300) {
      return body;
    }
    Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(body));
    } on FormatException {
      return body;
    }
    if (decoded is! Map) return body;
    final value = decoded.map<String, Object?>(
      (key, value) => MapEntry(key.toString(), value),
    );

    if (method.toUpperCase() == 'GET' && path == '/v1/threads') {
      final threads = value['threads'];
      if (threads is List) {
        value['threads'] = threads
            .whereType<Map>()
            .where((thread) {
              if (thread['threadId'] is! String) return false;
              return (thread['threadId'] as String).startsWith(_prefix);
            })
            .map((thread) {
              final scopedThread = thread.map<String, Object?>(
                (key, value) => MapEntry(key.toString(), value),
              );
              scopedThread['threadId'] = _toPublicScopedId(
                scopedThread['threadId']! as String,
              );
              _rewriteProtocolFields(scopedThread);
              return scopedThread;
            })
            .toList();
      }
    } else {
      _rewriteProtocolFields(value);
      final summary = value['summary'];
      if (summary is Map) {
        final summaryMap = summary.map<String, Object?>(
          (key, value) => MapEntry(key.toString(), value),
        );
        _rewriteProtocolFields(summaryMap);
        value['summary'] = summaryMap;
      }
    }
    return utf8.encode(jsonEncode(value));
  }

  void _rewriteProtocolFields(Map<String, Object?> value) {
    for (final key in const <String>['threadId']) {
      final item = value[key];
      if (item is String) value[key] = _toPublicScopedId(item);
    }
    for (final key in const <String>['runId', 'activeRunId', 'commandId']) {
      final item = value[key];
      if (item is String) {
        value[key] = key == 'commandId'
            ? _toPublicScopedId(item)
            : _toPublicRunId(item);
      }
    }
    final events = value['events'];
    if (events is String) value['events'] = _rewriteEventsPath(events);
  }

  void _rewriteEventDataIds(Map<String, Object?> value) {
    _rewriteProtocolFields(value);
    for (final entry in value.entries.toList()) {
      final item = entry.value;
      if (item is Map) {
        final nested = item.map<String, Object?>(
          (key, value) => MapEntry(key.toString(), value),
        );
        _rewriteEventDataIds(nested);
        value[entry.key] = nested;
      } else if (item is List) {
        value[entry.key] = item.map((element) {
          if (element is Map) {
            final nested = element.map<String, Object?>(
              (key, value) => MapEntry(key.toString(), value),
            );
            _rewriteEventDataIds(nested);
            return nested;
          }
          return element;
        }).toList();
      }
    }
  }

  String _rewriteEventsPath(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null || !uri.path.startsWith('/v1/threads/')) return value;
    final segments = uri.pathSegments;
    if (segments.length != 4 ||
        segments[0] != 'v1' ||
        segments[1] != 'threads') {
      return value;
    }
    final threadId = _toPublicScopedId(segments[2]);
    final query = <String, String>{...uri.queryParameters};
    final runId = query['runId'];
    if (runId != null) query['runId'] = _toPublicRunId(runId);
    return uri
        .replace(
          pathSegments: <String>['v1', 'threads', threadId, segments[3]],
          queryParameters: query.isEmpty ? null : query,
        )
        .toString();
  }

  String rewriteSseFrame(List<String> lines) {
    final dataLines = lines
        .where((line) => line.startsWith('data:'))
        .toList(growable: false);
    if (dataLines.isEmpty) return lines.join('\n');
    final rawData = dataLines
        .map((line) {
          final value = line.substring(5);
          return value.startsWith(' ') ? value.substring(1) : value;
        })
        .join('\n');
    Object? decoded;
    try {
      decoded = jsonDecode(rawData);
    } on FormatException {
      return lines.join('\n');
    }
    if (decoded is! Map) return lines.join('\n');
    final data = decoded.map<String, Object?>(
      (key, value) => MapEntry(key.toString(), value),
    );
    _rewriteProtocolFields(data);
    final eventData = data['data'];
    if (eventData is Map) {
      final eventDataMap = eventData.map<String, Object?>(
        (key, value) => MapEntry(key.toString(), value),
      );
      _rewriteEventDataIds(eventDataMap);
      data['data'] = eventDataMap;
    }
    final output = <String>[];
    var wroteData = false;
    for (final line in lines) {
      if (!line.startsWith('data:')) {
        output.add(line);
      } else if (!wroteData) {
        output.add('data: ${jsonEncode(data)}');
        wroteData = true;
      }
    }
    return output.join('\n');
  }
}
