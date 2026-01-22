A server app built using [Shelf](https://pub.dev/packages/shelf),
configured to enable running with [Docker](https://www.docker.com/).

This app exposes a version endpoint for basic health/version checks.

# Running the sample

## Configuration

- `PORT`: Port to bind; defaults to `20261` when not provided.
- `AGENTOS_BASEURL`: Base URL advertised by the service; defaults to
  `http://127.0.0.1:20261`. The helper script below sets it for you.
- `LITEAGENT_BASEURL`: Base URL for the LiteAgent Server proxy used by
  AgentKit; defaults to `http://127.0.0.1:9527/api/v1`.

## Running with the Dart SDK

You can run the example with the [Dart SDK](https://dart.dev/get-dart)
like this:

```
$ ./tool/run_server.sh
Server listening on port 20261
AGENTOS_BASEURL=http://127.0.0.1:20261
```

And then from a second terminal:
```
$ curl http://127.0.0.1:20261/version
{"version":"1.0.0"}
```

To override the defaults explicitly:
```
$ PORT=8080 AGENTOS_BASEURL=http://127.0.0.1:8080 dart run bin/server.dart
Server listening on port 8080
AGENTOS_BASEURL=http://127.0.0.1:8080
```

## Running with Docker

If you have [Docker Desktop](https://www.docker.com/get-started) installed, you
can build and run with the `docker` command:

```
$ docker build . -t myserver
$ docker run -it -p 20261:20261 myserver
Server listening on port 20261
AGENTOS_BASEURL=http://127.0.0.1:20261
```

And then from a second terminal:
```
$ curl http://0.0.0.0:20261/version
{"version":"1.0.0"}
```

You should see the logging printed in the first terminal:
```
2021-05-06T15:47:04.620417  0:00:00.000158 GET     [200] /
2021-05-06T15:47:08.392928  0:00:00.001216 GET     [200] /echo/I_love_Dart
```

## Root API

- `/version` returns the package version from `pubspec.yaml`:
  `{"version": "1.0.0"}`.

## AgentKit API

AgentKit proxies LiteAgent Server endpoints under `/agentkit/`. Set
`LITEAGENT_BASEURL` to the LiteAgent server base URL (for example
`http://127.0.0.1:9527/api/v1`). All AgentKit routes require a Bearer token.

Supported proxy routes:

- `GET /agentkit/version`
- `GET /agentkit/agent`
- `POST /agentkit/agent/create`
- `POST /agentkit/agent/update`
- `GET /agentkit/agent/delete`
- `POST /agentkit/initSession`
- `POST /agentkit/initSimple`
- `POST /agentkit/chat` (SSE stream)
- `POST /agentkit/chat/simple`
- `GET /agentkit/history`
- `GET /agentkit/stop`
- `GET /agentkit/clear`
- `GET /agentkit/opentool-list`
- `POST /agentkit/callback`
- `POST /agentkit/streamCallback`

## Toolkit API

Toolkit is currently disabled.

## AppKit API

- `POST /appkit/register` registers an app bundle: `{"bundleId": "com.demo"}` -> `{"token": "sk-..."}`.
- `GET /appkit/subscribe` (Bearer required) streams SSE events shaped like
  `event: welcome\ndata: {"bundleId": "..."}\n\n`.

## Intent API

Intent is currently disabled.
