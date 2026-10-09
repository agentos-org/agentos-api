A server app built using [Shelf](https://pub.dev/packages/shelf),
configured to enable running with [Docker](https://www.docker.com/).

This gateway provides a single entry point for all local AI services:
- **AgentKit**: Session initialization and chat (implemented via LiteAgent SDK)
- **CronKit**: Cron task management (powered by agentos_kernel)
- **RagKit**: RAG knowledge base management and query (powered by agentos_kernel)
- **AppKit**: Application registration and subscription
- **ToolKit**: Tool execution through the gateway
- **ModelKit**: Task-oriented model services (chat, embedding, ASR, TTS)
- **HarnessKit**: AppKit-authenticated routing to the AgentOS-managed Harness runtime
- **AuthKit**: Third-party app OAuth-like authentication
- **DiscoveryKit**: Nearby AgentOS device discovery
- **TransferKit**: Cross-device file transfer

Detailed HTTP API reference:
- [API.md](API.md)
- [API-zh_CN.md](API-zh_CN.md)

## HarnessKit runtime routing

AgentOS Runtime manages one host-wide Harness process and runtime. Installable
process Apps that declare `harnessKit` are registered with the Gateway after
their backend is healthy, then share that process and database with the built-in
Harness App. The Gateway scopes external Apps' threads, runs, and event access
by the authenticated AppKit `bundleId`; the built-in Harness and Shell sidebar
keep sharing their existing default namespace. Only the built-in Harness App
may access runtime controls and the global operational snapshot. Apps call
`/harnesskit/*` with their AppKit token and do not implement a Harness HTTP
server. Custom hosts may still inject HarnessKit clients through
`HarnessKitClientRegistry`.

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
- `POST /agentkit/initSession`
- `POST /agentkit/initSimple`
- `POST /agentkit/chat` (SSE stream)
- `POST /agentkit/chat/simple`
- `GET /agentkit/history` (optional paired `page` and `pageSize` query params)
- `GET /agentkit/history/summary` (summary-first task history)
- `GET /agentkit/history/process` (lazy process messages by `originalTaskId`)
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

`example/.env.example` is a hidden dotfile. If you do not see it in Finder or a
basic file listing, run `ls -la example`.

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

Both `/agentkit/chat` and `/agentkit/chat/simple` also accept `llmConfig` in
the `UserTask` body. It overrides the session default for that request only
and does not update the session. Direct overrides should include the complete
LiteAgent-compatible config; the AgentKit-only `modelId` lookup is supported as
well.

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

`Capability` execution limits (`maxLlmRequests`, `maxToolRounds`,
`maxToolCalls`, `maxConsecutiveIdenticalToolRounds`, and
`maxTaskDurationSeconds`) are also forwarded by `/agentkit/initSession`.

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

`sessionId` is optional. When provided on task creation, scheduled runs reuse
that LiteAgent session; when omitted, the kernel initializes a session when the
task runs. `timezone` accepts an IANA timezone name such as `Asia/Shanghai`;
the scheduler evaluates the cron expression in that timezone while scheduling
timestamps are returned in UTC.

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

- `GET /toolkit/list?all=0` - list callable tools. `all=1` also includes
  stopped `opentool-server` tools. `opentool-server` entries include `host`,
  `port`, `status`, and optional server metadata. App entries use the same
  `id`/`alias`/`status` shape but omit `host` and `port` because AgentOS
  proxies their calls.
- `GET /toolkit/{toolId}/load` - return the tool's OpenTool JSON
  description, including available functions and parameter schemas.
- `POST /toolkit/{toolId}/call` - call one function:
  `{"id":"call-001","name":"status","arguments":{"depth":1}}` ->
  `{"id":"call-001","result":{...}}`.
- `POST /toolkit/{toolId}/streamCall` - call one function and receive an
  SSE stream for long-running or incremental results.

ToolKit also lists explicitly opted-in process Apps as `app:{bundleId}` tools
after the user enables at least one currently declared function. Use `/load` to
fetch the App's current schema; the App backend is started only
when its schema or a function is requested. Each function must be enabled by
the user in Settings → App before `/load` includes it or `/call` accepts
it. Apps without `rpc.discovery: "runtime"` (or the legacy `rpc.systemMethods`
opt-in) are not listed. These App tools are proxied by AgentOS and are separate
from `opentool-server` tools managed by OpenTool Daemon.
An App entry's `status: "running"` means its ToolKit provider is available;
the App's dedicated backend can still be stopped until the first `/load` or
function call.
For App tools, the gateway converts ToolKit `FunctionCall` requests to the
App's JSON-RPC wire format and adapts call responses and SSE frames back to
ToolKit result shapes.

## ModelKit API

Task-oriented model proxy. Vision models live behind `/modelkit/chat` and are
identified by `capabilities.vision` on the resolved model.

- `ALL /modelkit/chat/*` - Text/vision generation (chat completions)
- `ALL /modelkit/embedding/*` - Text embeddings
- `ALL /modelkit/asr/*` - Speech-to-text
- `ALL /modelkit/tts/*` - Text-to-speech
- `GET /modelkit/models` - Task-oriented model listing

## AppKit API

- `POST /appkit/register` registers an app bundle:
  `{"bundleId": "com.demo.desktop", "appGroupId": "com.demo"}` ->
  `{"token": "sk-...", "bundleId": "com.demo.desktop", "appGroupId": "com.demo"}`.
- The request may include
  `"opentoolServers":[{"ref":"websearch","name":"opentool-server-websearch"}]`.
  Registration always selects the highest installed semantic version.
  This requires OpenTool daemon 0.5.0+ with the `artifactRegistryV2` and
  `startToolTerminalV1` capabilities.
  Registration returns `running` with an `id`, `starting` without an `id`, or
  `notFound` without an `id` for each declaration.
- If `appGroupId` is omitted, the server uses `bundleId` as the effective group.
- `GET /appkit/subscribe` (Bearer required) streams SSE events shaped like
  `event: welcome\ndata: {"bundleId": "..."}\n\n`.
- Asynchronous provisioning results use `event: appEvent`; ToolKit emits
  `toolkit.provision.succeeded` with the ready tool `id`, or
  `toolkit.provision.failed` with error details.
- After provisioning, AgentOS keeps monitoring every declared tool. A daemon or
  tool-process outage emits `toolkit.tool.unavailable`; a later healthy check
  emits `toolkit.tool.available`. Repeated checks in the same state are deduped.

## AuthKit API

AuthKit provides OAuth-like authentication for third-party apps accessing
AgentOS user data. All AuthKit routes require the Bearer token returned by
`POST /appkit/register`.

Supported routes:

- `POST /authkit/authorize` - Initiate an authorization request (returns a
  `requestId` and authorization URL for user consent)
- `GET /authkit/authorize/<requestId>/status` - Poll authorization status
- `POST /authkit/token` - Exchange an authorization code for an access token
- `GET /authkit/userinfo` - Get user profile (requires the access token from
  token exchange)
- `POST /authkit/revoke` - Revoke an access token
The flow: the app calls `/authorize` with desired `scopes` and optional
`appName`, presents the authorization URL to the user, polls `/status` until
approved/denied, then exchanges the code via `/token`. The resulting access
token can query `/userinfo`. User information is automatically refreshed when
updates occur.

## DiscoveryKit API

DiscoveryKit enables nearby AgentOS device discovery via mDNS/TLS. All
DiscoveryKit routes require the Bearer token returned by `POST /appkit/register`.

Supported routes:

- `GET /discoverykit/peers` - List currently discovered nearby peers
- `GET /discoverykit/peers/stream` - SSE stream of real-time peer
  discovery/departure events
- `GET /discoverykit/self` - Get this device's discovery identity
- `POST /discoverykit/register` - Register this device for discovery (accepts
  optional `receivePolicy`: `auto` | `confirmation`)
- `POST /discoverykit/unregister` - Unregister this device from discovery

The peer stream emits events in real time as nearby devices appear or disappear.
Discovery status refreshes are propagated immediately.

## TransferKit API

TransferKit provides secure cross-device file transfer between AgentOS devices.
All TransferKit routes require the Bearer token returned by
`POST /appkit/register`.

Supported routes:

- `POST /transferkit/send` - Initiate a file transfer to a discovered peer
- `GET /transferkit/transfers` - List active/recent transfers
- `GET /transferkit/transfers/<transferId>/status` - Get transfer status
- `GET /transferkit/transfers/<transferId>/stream` - SSE stream of transfer
  progress events
- `POST /transferkit/transfers/<transferId>/cancel` - Cancel an active transfer
- `POST /transferkit/transfers/<transferId>/respond` - Accept or reject an
  incoming transfer request (for `confirmation` receive policy)
- `GET /transferkit/receive/stream` - SSE stream of incoming transfer requests
- `PUT /transferkit/receive/policy` - Set the file receive policy
- `GET /transferkit/receive/policy` - Get the current receive policy
- `GET /transferkit/history` - List transfer history records
- `DELETE /transferkit/history/<recordId>` - Delete a specific history record
- `DELETE /transferkit/history` - Clear all transfer history

Receive policies:
- `autoAccept`: automatically accept incoming transfers
- `requireConfirm`: require explicit user/app confirmation per transfer
