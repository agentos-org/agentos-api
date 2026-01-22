import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'controllers/agentkit/agentkit_controller.dart';
import 'controllers/appkit/appkit_controller.dart';
import 'controllers/root_controller.dart';
import 'middleware.dart';

Handler createHandler() {
  final router = Router()
    ..mount('/', RootController().router)
    ..mount('/agentkit/', AgentKitController().router)
    ..mount('/appkit/', AppKitController().router);

  return Pipeline()
      .addMiddleware(
        logRequests(
          logger: (String message, bool isError) {
            if (isError) {
              requestLogger.severe(message);
            } else {
              requestLogger.info(message);
            }
          },
        ),
      )
      .addHandler(router);
}
