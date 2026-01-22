import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../version.dart';

class RootController {
  Router get router {
    final router = Router();
    router.get('/version', _version);
    return router;
  }

  Response _version(Request request) {
    final body = jsonEncode({'version': packageVersion});
    return Response.ok(body, headers: {'content-type': 'application/json'});
  }
}
