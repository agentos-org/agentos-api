A server app built using [Shelf](https://pub.dev/packages/shelf),
configured to enable running with [Docker](https://www.docker.com/).

This gateway provides a single entry point for all local AI services:
- **AgentKit**: Agent management and chat (implemented via LiteAgent SDK)
- **CronKit**: Cron task management (powered by agentos_kernel)
- **AppKit**: Application registration and subscription
- **ToolKit**: Tool execution (proxies to OpenTool)
- **LLMKit**: LLM services (text generation, vision, embedding, TTS, ASR)

# Running the sample

## Configuration

- `PORT`: Port to bind; defaults to `20261` when not provided.
- `AGENTOS_BASEURL`: Base URL advertised by the service; defaults to
  `http://127.0.0.1:20261`. The helper script below sets it for you.

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

## CronKit API

CronKit exposes kernel-backed cron task management endpoints. All CronKit
routes require a Bearer token issued by `POST /appkit/register`.
`POST /appkit/register` accepts `bundleId` and an optional `appGroupId`.
If `appGroupId` is omitted, the server defaults it to `bundleId`.
Cron task ownership is derived from the bearer token:
reads are shared within the same `appGroupId`, while write operations remain
restricted to the owner `bundleId`.

- `GET /cronkit/task?cronId=<id>`
- `GET /cronkit/task/list?enabled=<bool>&offset=<n>&limit=<n>`
- `POST /cronkit/task/create`
- `POST /cronkit/task/update`
- `POST /cronkit/task/delete`
- `POST /cronkit/task/setEnabled`
- `POST /cronkit/task/runNow`
- `GET /cronkit/run?runId=<id>`
- `GET /cronkit/run/list?cronId=<id>&after=<iso>&before=<iso>&offset=<n>&limit=<n>`
- `GET /cronkit/run/messages?runId=<id>&offset=<n>&limit=<n>`

CronKit request bodies use the kernel cron schema. Task `spec` now uses:

```json
{
  "systemPrompt": "You are a scheduled agent.",
  "content": [
    {"type": "text", "message": "Generate the daily summary."}
  ],
  "timeoutSeconds": 3600
}
```

`GET /cronkit/run` returns one run record. The response includes `trigger`
to indicate how the run was started (for example, `manual` or `scheduler`).
`GET /cronkit/run/messages` returns the persisted `AgentMessage[]` for that
run. CronKit does not expose SSE or subscribe-based cron execution streaming.

If kernel cron is unavailable, CronKit returns `503`.

## ToolKit API


- `ALL /toolkit/*` - Transparently proxies all requests to OpenTool backend.

## LLMKit API


- `ALL /llmkit/text/*` - Text generation (chat completions)
- `ALL /llmkit/vision/*` - Image-text-to-text
- `ALL /llmkit/embedding/*` - Text embeddings
- `ALL /llmkit/tts/*` - Text-to-speech
- `ALL /llmkit/asr/*` - Speech-to-text

## AppKit API

- `POST /appkit/register` registers an app bundle:
  `{"bundleId": "com.demo.desktop", "appGroupId": "com.demo"}` ->
  `{"token": "sk-...", "bundleId": "com.demo.desktop", "appGroupId": "com.demo"}`.
- If `appGroupId` is omitted, the server uses `bundleId` as the effective group.
- `GET /appkit/subscribe` (Bearer required) streams SSE events shaped like
  `event: welcome\ndata: {"bundleId": "..."}\n\n`.
- When kernel triggers app invocation, subscribed app may receive
  `event: callApp\ndata: {"bundleId":"...","contentList":[...]}\n\n`.
