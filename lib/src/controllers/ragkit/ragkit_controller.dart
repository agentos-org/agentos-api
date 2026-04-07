import 'dart:convert';

import 'package:agentos_kernel/agentos_kernel.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../../middleware.dart';
import '../../services/appkit/appkit_service.dart';

class RagKitController {
  RagKitController({
    required Future<KernelService?> kernelFuture,
    required AppKitService appKitService,
  }) : _kernelFuture = kernelFuture,
       _appKitService = appKitService;

  final Future<KernelService?> _kernelFuture;
  final AppKitService _appKitService;

  static const String _ownerBundleIdKey = 'ownerBundleId';
  static const String _ownerAppGroupIdKey = 'ownerAppGroupId';

  Router get router {
    final router = Router();
    final guard = requireBearer();

    router.get('/base', guard(_getBase));
    router.get('/base/list', guard(_listBases));
    router.post('/base/create', guard(_createBase));
    router.post('/base/update', guard(_updateBase));
    router.post('/base/delete', guard(_deleteBase));

    router.get('/document', guard(_getDocument));
    router.get('/document/list', guard(_listDocuments));
    router.post('/document/upsert', guard(_upsertDocument));
    router.post('/document/upsertBatch', guard(_upsertDocuments));
    router.post('/document/delete', guard(_deleteDocument));

    router.post('/sync/document', guard(_syncDocument));
    router.post('/sync/base', guard(_syncBase));
    router.post('/sync/retryFailed', guard(_retryFailed));
    router.post('/query', guard(_query));

    return router;
  }

  Future<Response> _getBase(Request request) async {
    final scope = _requireAppScope(request);
    if (scope == null) {
      return unauthorizedResponse();
    }
    final kernel = await _resolveKernel();
    if (kernel == null) {
      return _notConfigured();
    }
    final baseId = request.url.queryParameters['baseId']?.trim();
    if (baseId == null || baseId.isEmpty) {
      return _badRequest('baseId is required');
    }
    try {
      final base = await kernel.getRagBase(baseId);
      if (!_isReadableByGroup(base, scope.appGroupId)) {
        return Response(404, body: 'Unknown baseId: $baseId');
      }
      return _jsonResponse(base.toJson());
    } catch (error) {
      return _handleError('getBase', error);
    }
  }

  Future<Response> _listBases(Request request) async {
    final scope = _requireAppScope(request);
    if (scope == null) {
      return unauthorizedResponse();
    }
    final kernel = await _resolveKernel();
    if (kernel == null) {
      return _notConfigured();
    }
    final offset = _parseQueryInt(
      request.url.queryParameters['offset'],
      fieldName: 'offset',
      defaultValue: 0,
    );
    final limit = _parseQueryInt(
      request.url.queryParameters['limit'],
      fieldName: 'limit',
      defaultValue: 50,
    );
    try {
      final items = await kernel.listRagBases(offset: 0, limit: 1000000);
      final visible = <Map<String, dynamic>>[];
      for (final item in items) {
        final base = await kernel.getRagBase(item.id);
        if (_isReadableByGroup(base, scope.appGroupId)) {
          visible.add(item.toJson());
        }
      }
      return _jsonResponse(
        visible.skip(offset).take(limit).toList(growable: false),
      );
    } catch (error) {
      return _handleError('listBases', error);
    }
  }

  Future<Response> _createBase(Request request) async {
    final scope = _requireAppScope(request);
    if (scope == null) {
      return unauthorizedResponse();
    }
    final kernel = await _resolveKernel();
    if (kernel == null) {
      return _notConfigured();
    }
    final payload = await _readJsonBody(request);
    if (payload == null) {
      return _badRequest('Invalid JSON payload.');
    }
    final name = (payload['name'] ?? '').toString().trim();
    if (name.isEmpty) {
      return _badRequest('name is required');
    }
    final baseId = (payload['baseId'] ?? '').toString().trim();
    final metadata = _parseJsonMap(payload['metadata']);
    try {
      final base = await kernel.createRagBase(
        baseId: baseId.isEmpty ? null : baseId,
        name: name,
        metadata: _withOwnerMetadata(metadata, scope),
      );
      return _jsonResponse(base.toJson());
    } catch (error) {
      return _handleError('createBase', error);
    }
  }

  Future<Response> _updateBase(Request request) async {
    final scope = _requireAppScope(request);
    if (scope == null) {
      return unauthorizedResponse();
    }
    final kernel = await _resolveKernel();
    if (kernel == null) {
      return _notConfigured();
    }
    final payload = await _readJsonBody(request);
    if (payload == null) {
      return _badRequest('Invalid JSON payload.');
    }
    final baseId = (payload['baseId'] ?? '').toString().trim();
    if (baseId.isEmpty) {
      return _badRequest('baseId is required');
    }
    try {
      final base = await kernel.getRagBase(baseId);
      final denied = _ensureWritable(base, scope);
      if (denied != null) {
        return denied;
      }
      final name = (payload['name'] ?? '').toString().trim();
      final metadata = _mergeUserMetadata(
        base.metadata,
        _parseJsonMap(payload['metadata']),
        scope,
      );
      final updated = await kernel.updateRagBase(
        baseId: baseId,
        name: name.isEmpty ? null : name,
        metadata: metadata,
      );
      return _jsonResponse(updated.toJson());
    } catch (error) {
      return _handleError('updateBase', error);
    }
  }

  Future<Response> _deleteBase(Request request) async {
    final scope = _requireAppScope(request);
    if (scope == null) {
      return unauthorizedResponse();
    }
    final kernel = await _resolveKernel();
    if (kernel == null) {
      return _notConfigured();
    }
    final payload = await _readJsonBody(request);
    if (payload == null) {
      return _badRequest('Invalid JSON payload.');
    }
    final baseId = (payload['baseId'] ?? '').toString().trim();
    if (baseId.isEmpty) {
      return _badRequest('baseId is required');
    }
    try {
      final base = await kernel.getRagBase(baseId);
      final denied = _ensureWritable(base, scope);
      if (denied != null) {
        return denied;
      }
      await kernel.deleteRagBase(baseId);
      return _jsonResponse(<String, dynamic>{
        'deleted': true,
        'baseId': baseId,
      });
    } catch (error) {
      return _handleError('deleteBase', error);
    }
  }

  Future<Response> _getDocument(Request request) async {
    final scope = _requireAppScope(request);
    if (scope == null) {
      return unauthorizedResponse();
    }
    final kernel = await _resolveKernel();
    if (kernel == null) {
      return _notConfigured();
    }
    final baseId = request.url.queryParameters['baseId']?.trim();
    final documentId = request.url.queryParameters['documentId']?.trim();
    if (baseId == null || baseId.isEmpty) {
      return _badRequest('baseId is required');
    }
    if (documentId == null || documentId.isEmpty) {
      return _badRequest('documentId is required');
    }
    try {
      final base = await kernel.getRagBase(baseId);
      if (!_isReadableByGroup(base, scope.appGroupId)) {
        return Response(404, body: 'Unknown baseId: $baseId');
      }
      final document = await kernel.getRagDocument(
        baseId: baseId,
        documentId: documentId,
      );
      return _jsonResponse(document.toJson());
    } catch (error) {
      return _handleError('getDocument', error);
    }
  }

  Future<Response> _listDocuments(Request request) async {
    final scope = _requireAppScope(request);
    if (scope == null) {
      return unauthorizedResponse();
    }
    final kernel = await _resolveKernel();
    if (kernel == null) {
      return _notConfigured();
    }
    final baseId = request.url.queryParameters['baseId']?.trim();
    if (baseId == null || baseId.isEmpty) {
      return _badRequest('baseId is required');
    }
    final offset = _parseQueryInt(
      request.url.queryParameters['offset'],
      fieldName: 'offset',
      defaultValue: 0,
    );
    final limit = _parseQueryInt(
      request.url.queryParameters['limit'],
      fieldName: 'limit',
      defaultValue: 50,
    );
    try {
      final base = await kernel.getRagBase(baseId);
      if (!_isReadableByGroup(base, scope.appGroupId)) {
        return Response(404, body: 'Unknown baseId: $baseId');
      }
      final documents = await kernel.listRagDocuments(
        baseId: baseId,
        offset: offset,
        limit: limit,
      );
      return _jsonResponse(
        documents.map((item) => item.toJson()).toList(growable: false),
      );
    } catch (error) {
      return _handleError('listDocuments', error);
    }
  }

  Future<Response> _upsertDocument(Request request) async {
    final scope = _requireAppScope(request);
    if (scope == null) {
      return unauthorizedResponse();
    }
    final kernel = await _resolveKernel();
    if (kernel == null) {
      return _notConfigured();
    }
    final payload = await _readJsonBody(request);
    if (payload == null) {
      return _badRequest('Invalid JSON payload.');
    }
    final baseId = (payload['baseId'] ?? '').toString().trim();
    final documentId = (payload['documentId'] ?? '').toString().trim();
    final title = (payload['title'] ?? '').toString();
    final markdown = (payload['markdown'] ?? '').toString();
    if (baseId.isEmpty) {
      return _badRequest('baseId is required');
    }
    if (documentId.isEmpty) {
      return _badRequest('documentId is required');
    }
    if (markdown.isEmpty) {
      return _badRequest('markdown is required');
    }
    final sync = _parseBool(payload['sync'], defaultValue: true);
    try {
      final base = await kernel.getRagBase(baseId);
      final denied = _ensureWritable(base, scope);
      if (denied != null) {
        return denied;
      }
      final document = await kernel.upsertRagMarkdownDocument(
        baseId: baseId,
        documentId: documentId,
        title: title,
        markdown: markdown,
        metadata: _parseJsonMap(payload['metadata']),
        sync: sync,
      );
      return _jsonResponse(document.toJson());
    } catch (error) {
      return _handleError('upsertDocument', error);
    }
  }

  Future<Response> _upsertDocuments(Request request) async {
    final scope = _requireAppScope(request);
    if (scope == null) {
      return unauthorizedResponse();
    }
    final kernel = await _resolveKernel();
    if (kernel == null) {
      return _notConfigured();
    }
    final payload = await _readJsonBody(request);
    if (payload == null) {
      return _badRequest('Invalid JSON payload.');
    }
    final baseId = (payload['baseId'] ?? '').toString().trim();
    if (baseId.isEmpty) {
      return _badRequest('baseId is required');
    }
    final rawDocuments = payload['documents'];
    if (rawDocuments is! List) {
      return _badRequest('documents must be a list');
    }
    final sync = _parseBool(payload['sync'], defaultValue: true);
    try {
      final base = await kernel.getRagBase(baseId);
      final denied = _ensureWritable(base, scope);
      if (denied != null) {
        return denied;
      }
      final documents = <RagMarkdownDocumentInputDto>[];
      for (final item in rawDocuments) {
        if (item is! Map) {
          return _badRequest('Each document must be an object');
        }
        documents.add(
          RagMarkdownDocumentInputDto.fromJson(Map<String, dynamic>.from(item)),
        );
      }
      final result = await kernel.upsertRagMarkdownDocuments(
        baseId: baseId,
        documents: documents,
        sync: sync,
      );
      return _jsonResponse(result.toJson());
    } catch (error) {
      return _handleError('upsertDocuments', error);
    }
  }

  Future<Response> _deleteDocument(Request request) async {
    final scope = _requireAppScope(request);
    if (scope == null) {
      return unauthorizedResponse();
    }
    final kernel = await _resolveKernel();
    if (kernel == null) {
      return _notConfigured();
    }
    final payload = await _readJsonBody(request);
    if (payload == null) {
      return _badRequest('Invalid JSON payload.');
    }
    final baseId = (payload['baseId'] ?? '').toString().trim();
    final documentId = (payload['documentId'] ?? '').toString().trim();
    if (baseId.isEmpty) {
      return _badRequest('baseId is required');
    }
    if (documentId.isEmpty) {
      return _badRequest('documentId is required');
    }
    try {
      final base = await kernel.getRagBase(baseId);
      final denied = _ensureWritable(base, scope);
      if (denied != null) {
        return denied;
      }
      await kernel.deleteRagDocument(baseId: baseId, documentId: documentId);
      return _jsonResponse(<String, dynamic>{
        'deleted': true,
        'baseId': baseId,
        'documentId': documentId,
      });
    } catch (error) {
      return _handleError('deleteDocument', error);
    }
  }

  Future<Response> _syncDocument(Request request) async {
    final scope = _requireAppScope(request);
    if (scope == null) {
      return unauthorizedResponse();
    }
    final kernel = await _resolveKernel();
    if (kernel == null) {
      return _notConfigured();
    }
    final payload = await _readJsonBody(request);
    if (payload == null) {
      return _badRequest('Invalid JSON payload.');
    }
    final baseId = (payload['baseId'] ?? '').toString().trim();
    final documentId = (payload['documentId'] ?? '').toString().trim();
    if (baseId.isEmpty) {
      return _badRequest('baseId is required');
    }
    if (documentId.isEmpty) {
      return _badRequest('documentId is required');
    }
    try {
      final base = await kernel.getRagBase(baseId);
      final denied = _ensureWritable(base, scope);
      if (denied != null) {
        return denied;
      }
      final result = await kernel.syncRagDocument(
        baseId: baseId,
        documentId: documentId,
      );
      return _jsonResponse(result.toJson());
    } catch (error) {
      return _handleError('syncDocument', error);
    }
  }

  Future<Response> _syncBase(Request request) async {
    return _handleBaseBatchAction(
      request,
      action: (kernel, baseId) => kernel.syncRagBase(baseId),
    );
  }

  Future<Response> _retryFailed(Request request) async {
    final scope = _requireAppScope(request);
    if (scope == null) {
      return unauthorizedResponse();
    }
    final kernel = await _resolveKernel();
    if (kernel == null) {
      return _notConfigured();
    }
    final payload = await _readJsonBody(request);
    if (payload == null) {
      return _badRequest('Invalid JSON payload.');
    }
    final rawBaseId = (payload['baseId'] ?? '').toString().trim();
    try {
      if (rawBaseId.isNotEmpty) {
        final base = await kernel.getRagBase(rawBaseId);
        final denied = _ensureWritable(base, scope);
        if (denied != null) {
          return denied;
        }
      }
      final result = await kernel.retryFailedRagDocuments(
        baseId: rawBaseId.isEmpty ? null : rawBaseId,
      );
      final filtered = rawBaseId.isEmpty
          ? _filterBatchReadable(result, scope.appGroupId, kernel)
          : Future.value(result);
      return _jsonResponse((await filtered).toJson());
    } catch (error) {
      return _handleError('retryFailed', error);
    }
  }

  Future<Response> _query(Request request) async {
    final scope = _requireAppScope(request);
    if (scope == null) {
      return unauthorizedResponse();
    }
    final kernel = await _resolveKernel();
    if (kernel == null) {
      return _notConfigured();
    }
    final payload = await _readJsonBody(request);
    if (payload == null) {
      return _badRequest('Invalid JSON payload.');
    }
    final baseId = (payload['baseId'] ?? '').toString().trim();
    final query = (payload['query'] ?? '').toString().trim();
    if (baseId.isEmpty) {
      return _badRequest('baseId is required');
    }
    if (query.isEmpty) {
      return _badRequest('query is required');
    }
    final limit = _parseIntValue(payload['limit'], defaultValue: 5);
    final candidateLimit = _parseIntValue(
      payload['candidateLimit'],
      defaultValue: 20,
    );
    try {
      final base = await kernel.getRagBase(baseId);
      if (!_isReadableByGroup(base, scope.appGroupId)) {
        return Response(404, body: 'Unknown baseId: $baseId');
      }
      final result = await kernel.queryRag(
        baseId: baseId,
        query: query,
        limit: limit,
        candidateLimit: candidateLimit,
      );
      return _jsonResponse(result.toJson());
    } catch (error) {
      return _handleError('query', error);
    }
  }

  Future<Response> _handleBaseBatchAction(
    Request request, {
    required Future<RagBatchResultDto> Function(
      KernelService kernel,
      String baseId,
    )
    action,
  }) async {
    final scope = _requireAppScope(request);
    if (scope == null) {
      return unauthorizedResponse();
    }
    final kernel = await _resolveKernel();
    if (kernel == null) {
      return _notConfigured();
    }
    final payload = await _readJsonBody(request);
    if (payload == null) {
      return _badRequest('Invalid JSON payload.');
    }
    final baseId = (payload['baseId'] ?? '').toString().trim();
    if (baseId.isEmpty) {
      return _badRequest('baseId is required');
    }
    try {
      final base = await kernel.getRagBase(baseId);
      final denied = _ensureWritable(base, scope);
      if (denied != null) {
        return denied;
      }
      final result = await action(kernel, baseId);
      return _jsonResponse(result.toJson());
    } catch (error) {
      return _handleError('baseBatchAction', error);
    }
  }

  Future<RagBatchResultDto> _filterBatchReadable(
    RagBatchResultDto result,
    String appGroupId,
    KernelService kernel,
  ) async {
    final items = <RagBatchItemResultDto>[];
    for (final item in result.items) {
      try {
        final base = await kernel.getRagBase(item.baseId);
        if (_isReadableByGroup(base, appGroupId)) {
          items.add(item);
        }
      } catch (_) {
        // Skip bases that no longer exist.
      }
    }
    return RagBatchResultDto(
      totalCount: items.length,
      successCount: items.where((e) => e.status == 'success').length,
      failedCount: items.where((e) => e.status == 'failed').length,
      skippedCount: items.where((e) => e.status == 'skipped').length,
      processedAt: result.processedAt,
      items: items,
    );
  }

  _AppScope? _requireAppScope(Request request) {
    final token = bearerTokenFrom(request);
    if (token == null || token.isEmpty) {
      requestLogger.warning('RagKit: missing bearer token.');
      return null;
    }
    final bundleId = _appKitService.bundleIdForToken(token)?.trim();
    final appGroupId = _appKitService
        .effectiveAppGroupIdForToken(token)
        ?.trim();
    if (bundleId == null ||
        bundleId.isEmpty ||
        appGroupId == null ||
        appGroupId.isEmpty) {
      requestLogger.warning('RagKit: invalid app token.');
      return null;
    }
    return _AppScope(bundleId: bundleId, appGroupId: appGroupId);
  }

  bool _isReadableByGroup(RagBaseDto base, String appGroupId) {
    final ownerGroup = _ownerAppGroupId(base.metadata);
    return ownerGroup == appGroupId;
  }

  Response? _ensureWritable(RagBaseDto base, _AppScope scope) {
    if (_ownerBundleId(base.metadata) != scope.bundleId) {
      return Response(
        403,
        body: 'Only the owner bundleId can modify this base',
      );
    }
    return null;
  }

  Map<String, dynamic> _withOwnerMetadata(
    Map<String, dynamic>? metadata,
    _AppScope scope,
  ) {
    return <String, dynamic>{
      if (metadata != null) ...metadata,
      _ownerBundleIdKey: scope.bundleId,
      _ownerAppGroupIdKey: scope.appGroupId,
    };
  }

  Map<String, dynamic> _mergeUserMetadata(
    Map<String, dynamic>? existing,
    Map<String, dynamic>? incoming,
    _AppScope scope,
  ) {
    return <String, dynamic>{
      if (existing != null) ...existing,
      if (incoming != null) ...incoming,
      _ownerBundleIdKey: scope.bundleId,
      _ownerAppGroupIdKey: scope.appGroupId,
    };
  }

  String _ownerBundleId(Map<String, dynamic>? metadata) {
    return (metadata?[_ownerBundleIdKey] ?? '').toString();
  }

  String _ownerAppGroupId(Map<String, dynamic>? metadata) {
    final value = (metadata?[_ownerAppGroupIdKey] ?? '').toString().trim();
    if (value.isNotEmpty) {
      return value;
    }
    return _ownerBundleId(metadata);
  }

  Future<KernelService?> _resolveKernel() => _kernelFuture;

  Response _notConfigured() {
    return Response(
      503,
      body: 'RagKit is unavailable because kernel is not configured.',
    );
  }

  Response _badRequest(String message) => Response(400, body: message);

  Response _jsonResponse(Object payload, {int statusCode = 200}) {
    return Response(
      statusCode,
      body: jsonEncode(payload),
      headers: const {'content-type': 'application/json'},
    );
  }

  Response _handleError(String action, Object error) {
    if (error is StateError) {
      return Response(404, body: error.message.toString());
    }
    if (error is ArgumentError) {
      return _badRequest(error.message?.toString() ?? '$action failed');
    }
    requestLogger.warning('RagKit $action failed: $error');
    return Response(500, body: 'RagKit $action failed: $error');
  }

  Future<Map<String, dynamic>?> _readJsonBody(Request request) async {
    try {
      final rawBody = await request.readAsString();
      if (rawBody.isEmpty) {
        return <String, dynamic>{};
      }
      final decoded = jsonDecode(rawBody);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic>? _parseJsonMap(Object? raw) {
    if (raw == null) {
      return null;
    }
    if (raw is Map<String, dynamic>) {
      return raw;
    }
    if (raw is Map) {
      return Map<String, dynamic>.from(raw);
    }
    throw ArgumentError('metadata must be an object');
  }

  int _parseQueryInt(
    String? raw, {
    required String fieldName,
    required int defaultValue,
  }) {
    if (raw == null || raw.trim().isEmpty) {
      return defaultValue;
    }
    final value = int.tryParse(raw.trim());
    if (value == null || value < 0) {
      throw ArgumentError('$fieldName must be a non-negative integer');
    }
    return value;
  }

  int _parseIntValue(Object? raw, {required int defaultValue}) {
    if (raw == null) {
      return defaultValue;
    }
    if (raw is int) {
      return raw;
    }
    final value = int.tryParse(raw.toString());
    if (value == null) {
      return defaultValue;
    }
    return value;
  }

  bool _parseBool(Object? raw, {required bool defaultValue}) {
    if (raw == null) {
      return defaultValue;
    }
    if (raw is bool) {
      return raw;
    }
    final normalized = raw.toString().trim().toLowerCase();
    if (normalized == 'true') {
      return true;
    }
    if (normalized == 'false') {
      return false;
    }
    return defaultValue;
  }
}

class _AppScope {
  const _AppScope({required this.bundleId, required this.appGroupId});

  final String bundleId;
  final String appGroupId;
}
