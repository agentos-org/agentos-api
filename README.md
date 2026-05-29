A server app built using [Shelf](https://pub.dev/packages/shelf),
configured to enable running with [Docker](https://www.docker.com/).

This gateway provides a single entry point for all local AI services:
- **AgentKit**: Agent management and chat (implemented via LiteAgent SDK)
- **CronKit**: Cron task management (powered by agentos_kernel)
- **RagKit**: RAG knowledge base management and query (powered by agentos_kernel)
- **AppKit**: Application registration and subscription
- **ToolKit**: Tool execution through the gateway
- **ModelKit**: Task-oriented model services (chat, embedding, ASR, TTS)
- **LLMKit** *(deprecated)*: legacy LLM services, superseded by ModelKit

Detailed HTTP API reference:
- [API.md](API.md)
- [API-zh_CN.md](API-zh_CN.md)

# Running the sample

## Configuration

- `PORT`: Port to bind; defaults to `8888` when not provided.
- `AGENTOS_BASEURL`: Base URL advertised by the service; defaults to
  `http://127.0.0.1:8888`. The helper script below sets it for you.

## Running with the Dart SDK

You can run the example with the [Dart SDK](https://dart.dev/get-dart)
like this:

```
$ ./tool/run_server.sh
Server listening on port 8888
AGENTOS_BASEURL=http://127.0.0.1:8888
```

And then from a second terminal:
```
$ curl http://127.0.0.1:8888/version
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
$ docker run -it -p 8888:8888 myserver
Server listening on port 8888
AGENTOS_BASEURL=http://127.0.0.1:8888
```

And then from a second terminal:
```
$ curl http://0.0.0.0:8888/version
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

To verify that `streamCallback` is forwarded from AgentKit to LiteAgent SDK,
run:

```
$ dart run example/agentkit_stream_callback_example.dart
streamCallback forwarded successfully.
```

To run a full LLM-triggered `streamCallback` flow, similar to
`liteagent_server_dart/example/stream_call_example.dart`, start LiteAgent first:

```
$ cd ../liteagent_server_dart
$ dart run bin/server.dart
```

Then return to this repository, configure the model, and run:

```
$ cp example/.env.example example/.env
$ # Edit example/.env and fill baseUrl / apiKey / model.
$ dart run example/agentkit_stream_callback_llm_example.dart
```

The example starts a temporary AgentKit gateway, connects to
`liteAgentBaseUrl` from `.env`, registers `callbackOpenTool` via `initSession`,
and calls `/agentkit/chat`. When LiteAgent emits a stream functionCall over SSE,
the example runs the local `sequentiallyRead` mock tool and posts `data` and
`done` events back through `/agentkit/streamCallback`.

LLM settings are passed to LiteAgent through the AgentKit request body's
`llmConfig`:

```json
{
  "llmConfig": {
    "baseUrl": "https://api.openai.com/v1",
    "apiKey": "sk-...",
    "model": "gpt-4o-mini"
  }
}
```

This repository includes an example env template:

```
$ cp example/.env.example example/.env
```

The `baseUrl`, `apiKey`, and `model` names match the `liteagent_server_dart`
examples. Note that calling `streamCallback` by itself only forwards streamed
tool returns and does not call the LLM. In the full example, the LLM call
happens during `chat`; `streamCallback` carries streamed tool results back to
LiteAgent.

`POST /agentkit/initSession` and `POST /agentkit/initSimple` also support a
`skills` field on `Capability` / `SimpleCapability`. AgentKit forwards it
as-is to LiteAgent SDK. Each entry should be a complete Agent Skills markdown
document, not just a skill name. The source spec is the official Agent Skills
specification: [agentskills.io/specification](https://agentskills.io/specification).
In particular, the skill content should follow the `SKILL.md` format there:
YAML frontmatter first, then Markdown instructions. Example:

```json
{
  "systemPrompt": "You are a helpful planner.",
  "skills": [
    "---\nname: planner\ndescription: Plan before acting.\n---\n\nAlways produce a short plan before tool use.\n"
  ],
  "llmConfig": {
    "baseUrl": "http://127.0.0.1:52010",
    "model": "qwen3-8b"
  }
}
```

## CronKit API

CronKit exposes kernel-backed cron task management endpoints. All CronKit
routes require a Bearer token issued by `POST /appkit/register`.
`POST /appkit/register` accepts `bundleId` and an optional `appGroupId`.
If `appGroupId` is omitted, the server defaults it to `bundleId`.
Cron task ownership is derived from the bearer token:
all CronKit task and run operations are shared within the same `appGroupId`.

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

## RagKit API

RagKit exposes kernel-backed RAG base, document, sync, and query endpoints.
All RagKit routes require a Bearer token issued by `POST /appkit/register`.

RagKit authorization is split by app identity:

- Write operations are restricted to the owner `bundleId`
- Read and query operations are shared within the same `appGroupId`

That means the app that created a RAG base can update/delete/sync it, while
other apps in the same app group can still list and query that base.

Supported routes:

- `GET /ragkit/base?baseId=<id>`
- `GET /ragkit/base/list?offset=<n>&limit=<n>`
- `POST /ragkit/base/create`
- `POST /ragkit/base/update`
- `POST /ragkit/base/delete`
- `GET /ragkit/document?baseId=<id>&documentId=<id>`
- `GET /ragkit/document/list?baseId=<id>&offset=<n>&limit=<n>`
- `POST /ragkit/document/upsert`
- `POST /ragkit/document/upsertBatch`
- `POST /ragkit/document/delete`
- `POST /ragkit/sync/document`
- `POST /ragkit/sync/base`
- `POST /ragkit/sync/retryFailed`
- `POST /ragkit/query`

## ToolKit API

ToolKit is exposed through the AgentOS API Gateway. External clients should
call the gateway's `/toolkit/*` routes and do not need to connect to, configure,
or understand the internal tool runtime. ToolKit requests require the Bearer
token returned by `POST /appkit/register`.

Example:

```
$ TOKEN=$(curl -s http://127.0.0.1:8888/appkit/register \
    -H 'content-type: application/json' \
    -d '{"bundleId":"com.demo.app"}' | jq -r .token)
$ curl http://127.0.0.1:8888/toolkit/list \
    -H "authorization: Bearer $TOKEN"
```

Common endpoints:

- `GET /toolkit/list?all=0` - list running tools. Use `all=1` to include
  stopped tools. Returns `[{ "id", "alias", "host", "port", "status",
  "serverId" }]`.
- `GET /toolkit/{toolId}/load` - return the tool's OpenTool JSON
  description, including available functions and parameter schemas.
- `POST /toolkit/{toolId}/call` - call one function:
  `{"id":"call-001","name":"status","arguments":{"depth":1}}` ->
  `{"id":"call-001","result":{...}}`.
- `POST /toolkit/{toolId}/streamCall` - call one function and receive an
  SSE stream for long-running or incremental results.

## ModelKit API

Task-oriented model proxy. Vision models live behind `/modelkit/chat` and are
identified by `capabilities.vision` on the resolved model.

- `ALL /modelkit/chat/*` - Text/vision generation (chat completions)
- `ALL /modelkit/embedding/*` - Text embeddings
- `ALL /modelkit/asr/*` - Speech-to-text
- `ALL /modelkit/tts/*` - Text-to-speech
- `GET /modelkit/models` - Task-oriented model listing

## LLMKit API (Deprecated)

> Deprecated. Use the ModelKit endpoints above. The `/llmkit/*` mount is kept
> for backward compatibility and internally delegates to the same pipeline.

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
