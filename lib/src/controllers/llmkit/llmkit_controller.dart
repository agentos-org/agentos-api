import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../../services/llmkit/llm_client.dart';

/// LLMKit Controller
///
/// Proxies requests to various LLM services
class LLMKitController {
  LLMKitController({LLMClient? client}) : _client = client ?? LLMClient();

  final LLMClient _client;

  Router get router {
    final router = Router();

    // Text generation
    router.all('/text/<path|.*>', _createForward(LLMServiceType.text));

    // Image-text understanding
    router.all('/vision/<path|.*>', _createForward(LLMServiceType.vision));

    // Text embedding
    router.all('/embedding/<path|.*>', _createForward(LLMServiceType.embedding));

    // Text-to-speech
    router.all('/tts/<path|.*>', _createForward(LLMServiceType.tts));

    // Speech-to-text
    router.all('/asr/<path|.*>', _createForward(LLMServiceType.asr));

    return router;
  }

  /// Creates forward handler
  Handler _createForward(LLMServiceType serviceType) {
    return (Request request) async {
      final path = request.params['path'] ?? '';
      return _proxy(request, serviceType: serviceType, path: '/$path');
    };
  }

  Future<Response> _proxy(
    Request request, {
    required LLMServiceType serviceType,
    required String path,
  }) async {
    try {
      final bodyBytes = await _readBodyBytes(request);

      // Detect if streaming response is needed
      // LLM services typically include stream: true in request body or specify via Accept header
      final isStream = _detectStreamRequest(request, bodyBytes);

      final response = await _client.send(
        serviceType: serviceType,
        method: request.method,
        path: path,
        queryParameters: request.url.queryParameters,
        headers: request.headers,
        body: bodyBytes,
        streamResponse: isStream,
      );

      if (response.bodyStream != null) {
        return Response(
          response.statusCode,
          body: response.bodyStream,
          headers: response.headers,
          context: const {'shelf.io.buffer_output': false},
        );
      }
      return Response(
        response.statusCode,
        body: response.bodyBytes,
        headers: response.headers,
      );
    } on Exception catch (error) {
      return Response(502, body: 'LLM proxy error: $error');
    }
  }

  /// Detects if this is a streaming request
  bool _detectStreamRequest(Request request, List<int>? bodyBytes) {
    // Check Accept header
    final accept = request.headers['accept'] ?? '';
    if (accept.contains('text/event-stream')) {
      return true;
    }

    // Check stream field in request body
    if (bodyBytes != null && bodyBytes.isNotEmpty) {
      try {
        final bodyString = String.fromCharCodes(bodyBytes);
        if (bodyString.contains('"stream":true') ||
            bodyString.contains('"stream": true')) {
          return true;
        }
      } catch (_) {
        // Ignore parsing errors
      }
    }

    return false;
  }

  Future<List<int>?> _readBodyBytes(Request request) async {
    if (request.method == 'GET' || request.method == 'HEAD') {
      return null;
    }
    final bytes = await request.read().fold<List<int>>(
      <int>[],
      (buffer, data) {
        buffer.addAll(data);
        return buffer;
      },
    );
    return bytes.isEmpty ? null : bytes;
  }
}
