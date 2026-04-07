import 'dart:convert';

import 'package:agentos_api/src/controllers/ragkit/ragkit_controller.dart';
import 'package:agentos_api/src/models/app/app_models.dart';
import 'package:agentos_api/src/services/appkit/appkit_service.dart';
import 'package:agentos_kernel/agentos_kernel.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

void main() {
  group('RagKitController', () {
    late AppKitService appKitService;
    late _FakeKernelService kernel;
    late RagKitController controller;
    late String ownerToken;
    late String groupPeerToken;
    late String otherGroupToken;

    setUp(() {
      appKitService = AppKitService();
      kernel = _FakeKernelService();
      controller = RagKitController(
        kernelFuture: Future<KernelService?>.value(kernel),
        appKitService: appKitService,
      );
      ownerToken = appKitService
          .registerBundle(
            AppBundleDto(
              bundleId: 'com.demo.owner',
              appGroupId: 'com.demo.group',
            ),
          )
          .token;
      groupPeerToken = appKitService
          .registerBundle(
            AppBundleDto(
              bundleId: 'com.demo.peer',
              appGroupId: 'com.demo.group',
            ),
          )
          .token;
      otherGroupToken = appKitService
          .registerBundle(
            AppBundleDto(
              bundleId: 'com.other.app',
              appGroupId: 'com.other.group',
            ),
          )
          .token;
    });

    test('create base stores owner metadata', () async {
      final response = await _post(
        controller,
        '/base/create',
        ownerToken,
        <String, dynamic>{'name': 'docs'},
      );
      expect(response.statusCode, 200);
      final payload = await _decode(response);
      expect(payload['metadata']['ownerBundleId'], 'com.demo.owner');
      expect(payload['metadata']['ownerAppGroupId'], 'com.demo.group');
    });

    test('same appGroup can list base but cannot modify it', () async {
      await _post(controller, '/base/create', ownerToken, <String, dynamic>{
        'baseId': 'base-1',
        'name': 'docs',
      });

      final listResponse = await _get(controller, '/base/list', groupPeerToken);
      expect(listResponse.statusCode, 200);
      final listPayload = await _decodeList(listResponse);
      expect(listPayload, hasLength(1));
      expect(listPayload.first['id'], 'base-1');

      final updateResponse = await _post(
        controller,
        '/base/update',
        groupPeerToken,
        <String, dynamic>{'baseId': 'base-1', 'name': 'peer-update'},
      );
      expect(updateResponse.statusCode, 403);
    });

    test('different appGroup cannot see the base', () async {
      await _post(controller, '/base/create', ownerToken, <String, dynamic>{
        'baseId': 'base-1',
        'name': 'docs',
      });

      final getResponse = await _get(
        controller,
        '/base?baseId=base-1',
        otherGroupToken,
      );
      expect(getResponse.statusCode, 404);

      final listResponse = await _get(
        controller,
        '/base/list',
        otherGroupToken,
      );
      expect(await _decodeList(listResponse), isEmpty);
    });

    test('only owner bundle can upsert and delete documents', () async {
      await _post(controller, '/base/create', ownerToken, <String, dynamic>{
        'baseId': 'base-1',
        'name': 'docs',
      });

      final deniedUpsert = await _post(
        controller,
        '/document/upsert',
        groupPeerToken,
        <String, dynamic>{
          'baseId': 'base-1',
          'documentId': 'doc-1',
          'title': 'Doc',
          'markdown': '# Hello',
        },
      );
      expect(deniedUpsert.statusCode, 403);

      final allowedUpsert = await _post(
        controller,
        '/document/upsert',
        ownerToken,
        <String, dynamic>{
          'baseId': 'base-1',
          'documentId': 'doc-1',
          'title': 'Doc',
          'markdown': '# Hello',
        },
      );
      expect(allowedUpsert.statusCode, 200);

      final deniedDelete = await _post(
        controller,
        '/document/delete',
        groupPeerToken,
        <String, dynamic>{'baseId': 'base-1', 'documentId': 'doc-1'},
      );
      expect(deniedDelete.statusCode, 403);
    });

    test('same appGroup can query shared base', () async {
      await _post(controller, '/base/create', ownerToken, <String, dynamic>{
        'baseId': 'base-1',
        'name': 'docs',
      });

      final response = await _post(
        controller,
        '/query',
        groupPeerToken,
        <String, dynamic>{'baseId': 'base-1', 'query': 'markdown'},
      );
      expect(response.statusCode, 200);
      final payload = await _decode(response);
      expect(payload['baseId'], 'base-1');
      expect((payload['hits'] as List).first['documentId'], 'doc-1');
    });
  });
}

Future<Response> _get(RagKitController controller, String path, String token) {
  final request = Request(
    'GET',
    Uri.parse('http://localhost$path'),
    headers: <String, String>{'authorization': 'Bearer $token'},
  );
  return controller.router.call(request);
}

Future<Response> _post(
  RagKitController controller,
  String path,
  String token,
  Map<String, dynamic> body,
) {
  final request = Request(
    'POST',
    Uri.parse('http://localhost$path'),
    headers: <String, String>{
      'authorization': 'Bearer $token',
      'content-type': 'application/json',
    },
    body: jsonEncode(body),
  );
  return controller.router.call(request);
}

Future<Map<String, dynamic>> _decode(Response response) async {
  return jsonDecode(await response.readAsString()) as Map<String, dynamic>;
}

Future<List<Map<String, dynamic>>> _decodeList(Response response) async {
  final values = jsonDecode(await response.readAsString()) as List<dynamic>;
  return values
      .map((item) => Map<String, dynamic>.from(item as Map))
      .toList(growable: false);
}

class _FakeKernelService implements KernelService {
  final Map<String, RagBaseDto> bases = <String, RagBaseDto>{};
  final Map<String, Map<String, RagDocumentDto>> documentsByBase =
      <String, Map<String, RagDocumentDto>>{};
  final DateTime now = DateTime.parse('2026-04-07T12:00:00Z');

  @override
  Future<RagBaseDto> createRagBase({
    String? baseId,
    required String name,
    Map<String, dynamic>? metadata,
  }) async {
    final id = baseId ?? 'base-${bases.length + 1}';
    final base = RagBaseDto(
      id: id,
      name: name,
      docsName: 'rag_$id',
      docsId: 'docs_$id',
      metadata: metadata,
      createdAt: now,
      updatedAt: now,
    );
    bases[id] = base;
    return base;
  }

  @override
  Future<RagBaseDto> getRagBase(String baseId) async {
    final base = bases[baseId];
    if (base == null) {
      throw StateError('Unknown baseId: $baseId');
    }
    return base;
  }

  @override
  Future<List<RagBaseListItemDto>> listRagBases({
    int offset = 0,
    int limit = 50,
  }) async {
    return bases.values
        .skip(offset)
        .take(limit)
        .map(
          (base) => RagBaseListItemDto(
            id: base.id,
            name: base.name,
            createdAt: base.createdAt,
            updatedAt: base.updatedAt,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<RagBaseDto> updateRagBase({
    required String baseId,
    String? name,
    Map<String, dynamic>? metadata,
  }) async {
    final base = await getRagBase(baseId);
    final updated = RagBaseDto(
      id: base.id,
      name: name ?? base.name,
      docsName: base.docsName,
      docsId: base.docsId,
      metadata: metadata ?? base.metadata,
      createdAt: base.createdAt,
      updatedAt: now,
    );
    bases[baseId] = updated;
    return updated;
  }

  @override
  Future<void> deleteRagBase(String baseId) async {
    bases.remove(baseId);
    documentsByBase.remove(baseId);
  }

  @override
  Future<RagDocumentDto> upsertRagMarkdownDocument({
    required String baseId,
    required String documentId,
    required String title,
    required String markdown,
    Map<String, dynamic>? metadata,
    bool sync = true,
  }) async {
    await getRagBase(baseId);
    final docs = documentsByBase.putIfAbsent(
      baseId,
      () => <String, RagDocumentDto>{},
    );
    final document = RagDocumentDto(
      id: documentId,
      baseId: baseId,
      title: title,
      markdown: markdown,
      contentHash: 'hash',
      metadata: metadata,
      createdAt: now,
      updatedAt: now,
      syncStatus: sync ? 'synced' : 'pending',
    );
    docs[documentId] = document;
    return document;
  }

  @override
  Future<RagBatchResultDto> upsertRagMarkdownDocuments({
    required String baseId,
    required List<RagMarkdownDocumentInputDto> documents,
    bool sync = true,
  }) async {
    final items = <RagBatchItemResultDto>[];
    for (final document in documents) {
      await upsertRagMarkdownDocument(
        baseId: baseId,
        documentId: document.documentId,
        title: document.title,
        markdown: document.markdown,
        metadata: document.metadata,
        sync: sync,
      );
      items.add(
        RagBatchItemResultDto(
          baseId: baseId,
          documentId: document.documentId,
          status: 'success',
          syncStatus: sync ? 'synced' : 'pending',
        ),
      );
    }
    return RagBatchResultDto(
      totalCount: items.length,
      successCount: items.length,
      failedCount: 0,
      skippedCount: 0,
      processedAt: now,
      items: items,
    );
  }

  @override
  Future<RagDocumentDto> getRagDocument({
    required String baseId,
    required String documentId,
  }) async {
    final document = documentsByBase[baseId]?[documentId];
    if (document == null) {
      throw StateError('Unknown documentId: $documentId');
    }
    return document;
  }

  @override
  Future<List<RagDocumentListItemDto>> listRagDocuments({
    required String baseId,
    int offset = 0,
    int limit = 50,
  }) async {
    return (documentsByBase[baseId] ?? const <String, RagDocumentDto>{}).values
        .skip(offset)
        .take(limit)
        .map(
          (document) => RagDocumentListItemDto(
            id: document.id,
            baseId: document.baseId,
            title: document.title,
            updatedAt: document.updatedAt,
            indexedAt: document.indexedAt,
            syncStatus: document.syncStatus,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<void> deleteRagDocument({
    required String baseId,
    required String documentId,
  }) async {
    documentsByBase[baseId]?.remove(documentId);
  }

  @override
  Future<RagDocumentSyncResultDto> syncRagDocument({
    required String baseId,
    required String documentId,
  }) async {
    return RagDocumentSyncResultDto(
      baseId: baseId,
      documentId: documentId,
      syncStatus: 'synced',
      keptCount: 0,
      updatedCount: 0,
      insertedCount: 1,
      deletedCount: 0,
      syncedAt: now,
    );
  }

  @override
  Future<RagBatchResultDto> syncRagBase(String baseId) async {
    return RagBatchResultDto(
      totalCount: 1,
      successCount: 1,
      failedCount: 0,
      skippedCount: 0,
      processedAt: now,
      items: <RagBatchItemResultDto>[
        RagBatchItemResultDto(
          baseId: baseId,
          documentId: 'doc-1',
          status: 'success',
          syncStatus: 'synced',
        ),
      ],
    );
  }

  @override
  Future<RagBatchResultDto> retryFailedRagDocuments({String? baseId}) async {
    final targetBaseId = baseId ?? 'base-1';
    return RagBatchResultDto(
      totalCount: 1,
      successCount: 1,
      failedCount: 0,
      skippedCount: 0,
      processedAt: now,
      items: <RagBatchItemResultDto>[
        RagBatchItemResultDto(
          baseId: targetBaseId,
          documentId: 'doc-1',
          status: 'success',
          syncStatus: 'synced',
        ),
      ],
    );
  }

  @override
  Future<RagQueryResultDto> queryRag({
    required String baseId,
    required String query,
    int limit = 5,
    int candidateLimit = 20,
  }) async {
    return RagQueryResultDto(
      baseId: baseId,
      query: query,
      hits: <RagDocumentHitDto>[
        RagDocumentHitDto(
          documentId: 'doc-1',
          title: 'Doc 1',
          score: 1.0,
          snippet: 'markdown hit',
          segments: <RagSegmentHitDto>[
            const RagSegmentHitDto(
              segmentId: 'seg-1',
              score: 1.0,
              text: 'markdown hit',
              headingPath: 'Intro',
            ),
          ],
        ),
      ],
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not mocked');
}
