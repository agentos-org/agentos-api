A server app built using [Shelf](https://pub.dev/packages/shelf),
configured to enable running with [Docker](https://www.docker.com/).

This gateway provides a single entry point for all local AI services:
- **AgentKit**: Agent management and chat (implemented via LiteAgent SDK)
- **IntentKit**: Intent detection (powered by agentos_kernel, disabled by default)
- **AppKit**: Application registration and subscription
- **ToolKit**: Tool execution (proxies to OpenTool)
- **LLMKit**: LLM services (text generation, vision, embedding, TTS, ASR)

# Running the sample

## Configuration

- `PORT`: Port to bind; defaults to `20261` when not provided.
- `AGENTOS_BASEURL`: Base URL advertised by the service; defaults to
  `http://127.0.0.1:20261`. The helper script below sets it for you.
- `ENABLE_INTENTKIT`: Whether to expose `/intentkit/*` routes. Defaults to
  disabled. Set to `true` to enable.

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

To expose IntentKit explicitly:
```
$ ENABLE_INTENTKIT=true dart run bin/server.dart
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

System endpoints provide gateway information.

- `GET /` returns gateway information including all available endpoints.
- `GET /version` returns the package version: `{"version": "1.0.0"}`.

## AgentKit API

AgentKit exposes LiteAgent-compatible routes under `/agentkit/` and executes
them via LiteAgent SDK. By default, LiteAgent endpoint is
`http://127.0.0.1:9527/api/v1` from `DefaultServiceLocator`. All AgentKit
routes require a Bearer token.

Supported routes:

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
- `POST /agentkit/callback`
- `POST /agentkit/streamCallback`

`POST /agentkit/chat` SSE emits `message`, `chunk`, and `functionCall`.
When receiving `functionCall`, external callers can post a `ToolReturn` to
`POST /agentkit/callback?sessionId=...` to complete the pending callback.

## IntentKit API

IntentKit exposes kernel-backed intent detection endpoints for intent apps.
These routes are disabled by default and must be enabled explicitly with
`ENABLE_INTENTKIT=true`. All IntentKit routes require a Bearer token.
IntentKit is deprecated. Intent can trigger too frequently, and current LLM
response speed is not yet fast enough. To reserve model compute for direct user
interactions, prefer direct execution-oriented APIs.

- `POST /intentkit/submitRaw`
- `POST /intentkit/submitIntent`
- `POST /intentkit/confirmJob`
- `POST /intentkit/suggestNextAction`

## ToolKit API


- `ALL /toolkit/*` - Transparently proxies all requests to OpenTool backend.

## LLMKit API


- `ALL /llmkit/text/*` - Text generation (chat completions)
- `ALL /llmkit/vision/*` - Image-text-to-text
- `ALL /llmkit/embedding/*` - Text embeddings
- `ALL /llmkit/tts/*` - Text-to-speech
- `ALL /llmkit/asr/*` - Speech-to-text

## AppKit API

- `POST /appkit/register` registers an app bundle: `{"bundleId": "com.demo"}` -> `{"token": "sk-..."}`.
- `GET /appkit/subscribe` (Bearer required) streams SSE events shaped like
  `event: welcome\ndata: {"bundleId": "..."}\n\n`.
- When kernel triggers app invocation, subscribed app may receive
  `event: callApp\ndata: {"bundleId":"...","contentList":[...]}\n\n`.
