import 'package:logging/logging.dart';
import 'package:shelf/shelf.dart';

const String bearerTokenContextKey = 'bearerToken';

final Logger requestLogger = Logger('agentos_server');

Middleware cors() {
  const corsHeaders = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
    'Access-Control-Allow-Headers':
        'Origin, Content-Type, Accept, Authorization',
    'Access-Control-Max-Age': '86400',
  };

  return (Handler innerHandler) {
    return (Request request) async {
      if (request.method == 'OPTIONS') {
        return Response.ok('', headers: corsHeaders);
      }
      final response = await innerHandler(request);
      return response.change(headers: corsHeaders);
    };
  };
}

String? extractBearerToken(Request request) {
  final header =
      request.headers['authorization'] ?? request.headers['Authorization'];
  if (header == null) {
    return null;
  }
  const prefix = 'bearer ';
  if (header.length >= prefix.length &&
      header.toLowerCase().startsWith(prefix)) {
    return header.substring(prefix.length).trim();
  }
  return null;
}

Response unauthorizedResponse([
  String message = 'Missing or invalid bearer token',
]) {
  return Response(401, body: message);
}

Middleware requireBearer() {
  return (Handler inner) {
    return (Request request) {
      final token = extractBearerToken(request);
      if (token == null || token.isEmpty) {
        return unauthorizedResponse();
      }
      final updated = request.change(context: {bearerTokenContextKey: token});
      return inner(updated);
    };
  };
}

String? bearerTokenFrom(Request request) {
  final token = request.context[bearerTokenContextKey];
  return token is String ? token : null;
}
