# AgentOS HTTP API

Base URL: `http://<host>:<port>` (default port: `20261`).

## Authentication

Bearer token is required for all `/agentkit/*` and `/cronkit/*` routes, and for
`GET /appkit/subscribe`.

For `/cronkit/*`, the bearer token must be an AppKit-issued token from
`POST /appkit/register`. Cron task ownership is isolated by the token's
resolved app identity. Reads are shared within the same effective
`appGroupId`, while writes stay restricted to the owner `bundleId`.

```
Authorization: Bearer <token>
```

## AgentKit (LiteAgent-Compatible Gateway)

AgentKit exposes LiteAgent-compatible routes and executes them via
LiteAgent SDK. Default LiteAgent endpoint is
`http://127.0.0.1:9527/api/v1` from `DefaultServiceLocator`.
All routes below require a Bearer token.
If backend/sdk operation fails, the gateway may return `502`.

### Schemas

#### LLMConfig

| Field | Type | Required | Description |
| --- | --- | --- | --- |
| `baseUrl` | `string` | Yes | LLM endpoint base URL. |
| `apiKey` | `string` | Yes | LLM API key. |
| `model` | `string` | Yes | Model name. |
| `temperature` | `number` | No | Sampling temperature. |
| `maxTokens` | `number` | No | Max tokens. |
| `contextWindowSize` | `number` | No | Context window size. |
| `topP` | `number` | No | Top-p. |
| `supportsToolCall` | `boolean` | No | Whether tool calling is supported. |
| `supportsReasoning` | `boolean` | No | Whether reasoning mode is supported. |

#### ApiKey

| Field | Type | Required | Description |
| --- | --- | --- | --- |
| `type` | `string` | Yes | `basic`, `bearer`, or `original`. |
| `apiKey` | `string` | Yes | API key string. |

#### OpenSpec

| Field | Type | Required | Description |
| --- | --- | --- | --- |
| `openSpec` | `string` | Yes | JSON spec string. |
| `protocol` | `string` | Yes | `openapi`, `jsonrpcHttp`, `opentool`, `mcpStdio`, `mcpHttp`. |
| `serverUrl` | `string` | No | Override server URL. |
| `apiKey` | `ApiKey` | No | API key config. |

#### CallbackOpenTool

| Field | Type | Required | Description |
| --- | --- | --- | --- |
| `opentool` | `string` | Yes | OpenTool JSON. |
| `timeout` | `number` | No | Timeout seconds. |

#### SessionName

| Field | Type | Required | Description |
| --- | --- | --- | --- |
| `sessionId` | `string` | Yes | Session ID. |
| `name` | `string` | No | Sub-agent name (`[a-zA-Z0-9_-]{1,64}`). |
| `description` | `string` | No | Sub-agent description. |

#### ReflectPrompt

| Field | Type | Required | Description |
| --- | --- | --- | --- |
| `llmConfig` | `LLMConfig` | Yes | LLM config for reflection. |
| `prompt` | `string` | Yes | Reflection prompt. |

#### Capability

| Field | Type | Required | Description |
| --- | --- | --- | --- |
| `llmConfig` | `LLMConfig` | No | LLM config. If omitted, gateway may inject an available config from kernel. |
| `systemPrompt` | `string` | Yes | System prompt. |
| `openSpecList` | `OpenSpec[]` | No | Tool specs. |
| `callbackOpenTool` | `CallbackOpenTool` | No | Client callback tool. |
| `sessionList` | `SessionName[]` | No | Sub-sessions. |
| `reflectPromptList` | `ReflectPrompt[]` | No | Reflection prompts. |
| `timeoutSeconds` | `number` | No | Default `3600`. |
| `taskPipelineStrategy` | `string` | No | `parallel`, `serial`, `reject`. |
| `toolPipelineStrategy` | `string` | No | `parallel`, `serial`, `reject`. |
| `auto` | `boolean` | No | Auto-run tasks. |
| `llmConfigList` | `LLMConfig[]` | No | Candidate LLM configs for model selection/fallback. |
| `enableThinking` | `boolean` | No | Enable reasoning output. |
| `toolReturnPackMinLength` | `number` | No | Minimum packed length before returning tool output. |

#### SimpleCapability

| Field | Type | Required | Description |
| --- | --- | --- | --- |
| `llmConfig` | `LLMConfig` | No | LLM config. If omitted, gateway may inject an available config from kernel. |
| `systemPrompt` | `string` | Yes | System prompt. |

#### Agent

| Field | Type | Required | Description |
| --- | --- | --- | --- |
| `name` | `string` | Yes | Agent name. |
| `capability` | `Capability` | Yes | Agent capability. |

#### AgentId

| Field | Type | Required | Description |
| --- | --- | --- | --- |
| `agentId` | `string` | Yes | Agent ID. |

#### Session

| Field | Type | Required | Description |
| --- | --- | --- | --- |
| `sessionId` | `string` | Yes | Session ID. |

#### SessionTask

| Field | Type | Required | Description |
| --- | --- | --- | --- |
| `sessionId` | `string` | Yes | Session ID. |
| `taskId` | `string` | No | Task ID. |

#### Content

| Field | Type | Required | Description |
| --- | --- | --- | --- |
| `type` | `string` | Yes | `text` or `imageUrl`. |
| `message` | `string` | Yes | Text or image URL/base64. |

#### UserTask

| Field | Type | Required | Description |
| --- | --- | --- | --- |
| `content` | `Content[]` | Yes | Message content list. |
| `isChunk` | `boolean` | No | Emit chunk events when true. |
| `extraSystemPrompt` | `string` | No | Extra system prompt applied for this task only. |
| `llmConfig` | `LLMConfig` | No | Per-task LLM override. |

#### ToolReturn

| Field | Type | Required | Description |
| --- | --- | --- | --- |
| `id` | `string` | Yes | Tool call ID. |
| `result` | `object` | Yes | Tool result payload. |

#### EventToolReturn

| Field | Type | Required | Description |
| --- | --- | --- | --- |
| `event` | `string` | Yes | Stream event name. |
| `toolReturn` | `ToolReturn` | Yes | Tool return payload. |

#### AgentMessage

| Field | Type | Required | Description |
| --- | --- | --- | --- |
| `sessionId` | `string` | Yes | Session ID. |
| `agentId` | `string` | No | Agent ID. |
| `parentTaskId` | `string` | No | Parent task ID. |
| `taskId` | `string` | Yes | Task ID. |
| `role` | `string` | Yes | `system`, `user`, `agent`, `llm`, `tool`. |
| `to` | `string` | Yes | `user`, `agent`, `llm`, `tool`, `client`. |
| `type` | `string` | Yes | `text`, `imageUrl`, `dispatch`, `contentList`, `functionCall`, `toolCalls`, `toolReturn`, `reflection`, `taskStatus`, `reasoning`, `reasoningContent`, `planning`. |
| `content` | `any` | Yes | Content payload, shape depends on `type`. |
| `reasoningContent` | `string` | No | Model reasoning text. |
| `completions` | `object` | No | Token usage info. |
| `createTime` | `string` | Yes | ISO timestamp. |

`completions` fields:

| Field | Type | Required | Description |
| --- | --- | --- | --- |
| `usage` | `object` | Yes | Token usage. |
| `usage.promptTokens` | `number` | Yes | Prompt tokens. |
| `usage.completionTokens` | `number` | Yes | Completion tokens. |
| `usage.totalTokens` | `number` | Yes | Total tokens. |
| `usage.contextUsageRatio` | `number` | No | Context window usage ratio (0-1). |
| `id` | `string` | Yes | Model message ID. |
| `model` | `string` | Yes | Model name. |
| `limits` | `object` | No | Model limits info. |
| `limits.maxTokens` | `number` | Yes | Max output tokens limit. |
| `limits.contextWindowSize` | `number` | No | Model context window size. |

#### AgentMessageChunk

| Field | Type | Required | Description |
| --- | --- | --- | --- |
| `sessionId` | `string` | Yes | Session ID. |
| `agentId` | `string` | No | Agent ID. |
| `parentTaskId` | `string` | No | Parent task ID. |
| `taskId` | `string` | Yes | Task ID. |
| `role` | `string` | Yes | `system`, `user`, `agent`, `llm`, `tool`. |
| `to` | `string` | Yes | `user`, `agent`, `llm`, `tool`, `client`. |
| `type` | `string` | Yes | `text`, `imageUrl`, `dispatch`, `contentList`, `functionCall`, `toolCalls`, `toolReturn`, `reflection`, `taskStatus`, `reasoning`, `reasoningContent`, `planning`. |
| `part` | `any` | Yes | Partial payload, shape depends on `type`. |
| `createTime` | `string` | Yes | ISO timestamp. |

### Endpoints

#### GET /agentkit/version

Response: `200 OK`

```
{"version":"<string>"}
```

#### GET /agentkit/agent

Query:

| Field | Type | Required |
| --- | --- | --- |
| `agentId` | `string` | Yes |

Response: `200 OK` (`Agent`)

#### POST /agentkit/agent/create

Request body: `Agent`

Response: `200 OK` (`AgentId`)

#### POST /agentkit/agent/update

Query:

| Field | Type | Required |
| --- | --- | --- |
| `agentId` | `string` | Yes |

Request body: `Agent`

Response: `200 OK` (`AgentId`)

#### GET /agentkit/agent/delete

Query:

| Field | Type | Required |
| --- | --- | --- |
| `agentId` | `string` | Yes |

Response: `200 OK` (`AgentId`)

#### POST /agentkit/initSession

Query (optional):

| Field | Type | Required |
| --- | --- | --- |
| `agentId` | `string` | No |

Request body (when `agentId` is not provided): `Capability`

Response: `200 OK` (`Session`)

#### POST /agentkit/initSimple

Request body: `SimpleCapability`

Response: `200 OK` (`Session`)

#### POST /agentkit/chat

Query:

| Field | Type | Required |
| --- | --- | --- |
| `sessionId` | `string` | Yes |

Request body: `UserTask`

Response: `200 OK`, `text/event-stream`

Events:
- `message`: `AgentMessage`
- `chunk`: `AgentMessageChunk`
- `functionCall`: `{"sessionId":"<string>","functionCall":FunctionCall}`

#### POST /agentkit/chat/simple

Query:

| Field | Type | Required |
| --- | --- | --- |
| `sessionId` | `string` | Yes |

Request body: `UserTask`

Response: `200 OK` (`AgentMessage`)

#### GET /agentkit/history

Query:

| Field | Type | Required |
| --- | --- | --- |
| `sessionId` | `string` | Yes |

Response: `200 OK` (`AgentMessage[]`)

#### GET /agentkit/stop

Query:

| Field | Type | Required |
| --- | --- | --- |
| `sessionId` | `string` | Yes |
| `taskId` | `string` | No |

Response: `200 OK`

```json
{"status":"ok"}
```

#### GET /agentkit/clear

Query:

| Field | Type | Required |
| --- | --- | --- |
| `sessionId` | `string` | Yes |

Response: `200 OK`

```json
{"status":"ok"}
```

#### POST /agentkit/callback

Query:

| Field | Type | Required |
| --- | --- | --- |
| `sessionId` | `string` | Yes |

Request body: `ToolReturn`

Response: `200 OK`

```json
{"status":"ok"}
```

Notes:
- If there is a pending external `functionCall` for the same `sessionId` + `toolReturn.id`, this endpoint completes that pending call.
- Otherwise, the request is forwarded to LiteAgent `/callback` (legacy behavior).

#### POST /agentkit/streamCallback

Query:

| Field | Type | Required |
| --- | --- | --- |
| `sessionId` | `string` | Yes |

Request body: `EventToolReturn`

Response: `200 OK`

```json
{"status":"ok"}
```

## CronKit

CronKit exposes kernel-backed cron task management and history APIs.
All routes in this section require a Bearer token from `POST /appkit/register`.

### Schemas

#### CronContent

Same shape as `Content`.

#### AgentCronSpec

| Field | Type | Required | Description |
| --- | --- | --- | --- |
| `systemPrompt` | `string` | Yes | System prompt used by the scheduled agent. |
| `content` | `CronContent[]` | Yes | Non-empty content list for the scheduled execution input. |
| `timeoutSeconds` | `number` | No | Execution timeout in seconds. Default `3600`. |

#### CronTask

| Field | Type | Required | Description |
| --- | --- | --- | --- |
| `cronId` | `string` | Yes | Cron task ID. |
| `name` | `string` | Yes | Task name. |
| `schedule` | `string` | Yes | Cron expression. |
| `source` | `string` | Yes | Internal source/ownership marker. |
| `userId` | `string` | No | Optional user ID. |
| `sessionId` | `string` | No | Optional session ID. |
| `timezone` | `string` | No | Task timezone. |
| `enabled` | `boolean` | Yes | Whether the task is enabled. |
| `status` | `string` | Yes | Current task status. |
| `concurrency` | `string` | Yes | Concurrency policy. |
| `createdAt` | `string` | Yes | ISO timestamp. |
| `updatedAt` | `string` | Yes | ISO timestamp. |
| `lastRunAt` | `string` | No | ISO timestamp of the last run. |
| `nextRunAt` | `string` | No | ISO timestamp of the next scheduled run. |
| `spec` | `AgentCronSpec` | Yes | Scheduled agent spec. |

#### CronTaskListItem

| Field | Type | Required | Description |
| --- | --- | --- | --- |
| `cronId` | `string` | Yes | Cron task ID. |
| `name` | `string` | Yes | Task name. |
| `schedule` | `string` | Yes | Cron expression. |
| `enabled` | `boolean` | Yes | Whether the task is enabled. |
| `status` | `string` | Yes | Current task status. |
| `lastRunAt` | `string` | No | ISO timestamp of the last run. |
| `nextRunAt` | `string` | No | ISO timestamp of the next scheduled run. |

#### CronRun

| Field | Type | Required | Description |
| --- | --- | --- | --- |
| `runId` | `string` | Yes | Run ID. |
| `cronId` | `string` | Yes | Cron task ID. |
| `status` | `string` | Yes | Run status. |
| `scheduledAt` | `string` | Yes | ISO timestamp of the scheduled execution time. |
| `startedAt` | `string` | Yes | ISO timestamp of the actual start time. |
| `finishedAt` | `string` | No | ISO timestamp of completion. |
| `liteAgentSessionId` | `string` | No | LiteAgent session ID, if available. |
| `error` | `string` | No | Error message if execution failed. |
| `result` | `object` | No | Final execution result payload. |

#### CronRunListItem

| Field | Type | Required | Description |
| --- | --- | --- | --- |
| `runId` | `string` | Yes | Run ID. |
| `cronId` | `string` | Yes | Cron task ID. |
| `status` | `string` | Yes | Run status. |
| `scheduledAt` | `string` | Yes | ISO timestamp of the scheduled execution time. |
| `startedAt` | `string` | Yes | ISO timestamp of the actual start time. |
| `finishedAt` | `string` | No | ISO timestamp of completion. |

#### CronRunMessage

| Field | Type | Required | Description |
| --- | --- | --- | --- |
| `messageId` | `string` | Yes | Persisted message ID. |
| `runId` | `string` | Yes | Run ID. |
| `cronId` | `string` | Yes | Cron task ID. |
| `timestamp` | `string` | Yes | ISO timestamp when the message was persisted. |
| `message` | `AgentMessage` | Yes | Persisted message payload. |

### Endpoints

#### GET /cronkit/task

Query:

| Field | Type | Required |
| --- | --- | --- |
| `cronId` | `string` | Yes |

Response: `200 OK` (`CronTask`)

#### GET /cronkit/task/list

Query:

| Field | Type | Required |
| --- | --- | --- |
| `enabled` | `boolean` | No |
| `offset` | `number` | No |
| `limit` | `number` | No |

Response: `200 OK` (`CronTaskListItem[]`)

#### POST /cronkit/task/create

Request body:

```json
{
  "name": "Daily Summary",
  "schedule": "0 9 * * *",
  "spec": {
    "systemPrompt": "You are a scheduled agent.",
    "content": [
      {"type": "text", "message": "Generate today's summary."}
    ],
    "timeoutSeconds": 3600
  },
  "timezone": "Asia/Shanghai",
  "concurrency": "skipIfRunning",
  "enabled": true
}
```

Response: `200 OK` (`CronTask`)

Notes:
- Ownership is derived from the bearer token, not from a client-supplied `source`.
- All CronKit task and run operations are shared within the same effective `appGroupId`.

#### POST /cronkit/task/update

Request body: partial `CronTask` update payload with required `cronId`.
`spec`, when provided, must use the same `AgentCronSpec` shape as creation.

Response: `200 OK` (`CronTask`)

#### POST /cronkit/task/delete

Request body:

```json
{"cronId":"<string>"}
```

Response: `200 OK`

```json
{"deleted":true,"cronId":"<string>"}
```

#### POST /cronkit/task/setEnabled

Request body:

```json
{"cronId":"<string>","enabled":true}
```

Response: `200 OK` (`CronTask`)

#### POST /cronkit/task/runNow

Request body:

```json
{"cronId":"<string>","scheduledAt":"2026-03-17T09:00:00Z"}
```

Response: `200 OK` (`CronRun`)

#### GET /cronkit/run

Query:

| Field | Type | Required |
| --- | --- | --- |
| `runId` | `string` | Yes |

Response: `200 OK` (`CronRun`)

Notes:
- `trigger` indicates how the run was started (for example, `manual` or `scheduler`).

#### GET /cronkit/run/list

Query:

| Field | Type | Required |
| --- | --- | --- |
| `cronId` | `string` | No |
| `after` | `string` | No |
| `before` | `string` | No |
| `offset` | `number` | No |
| `limit` | `number` | No |

Response: `200 OK` (`CronRunListItem[]`)

#### GET /cronkit/run/messages

Query:

| Field | Type | Required |
| --- | --- | --- |
| `runId` | `string` | Yes |
| `offset` | `number` | No |
| `limit` | `number` | No |

Response: `200 OK` (`CronRunMessage[]`)

Notes:
- This endpoint returns persisted `AgentMessage` records only.
- CronKit does not expose SSE or subscribe-based run streaming.

If kernel cron is unavailable, CronKit may return `503`.

## AppKit

### POST /appkit/register

Request body:

```
{"bundleId":"com.demo.app","appGroupId":"com.demo"}
```

Response: `200 OK`

```
{"token":"sk-...","bundleId":"com.demo.app","appGroupId":"com.demo"}
```

Notes:
- `appGroupId` is optional.
- If omitted, the server uses `bundleId` as the effective group ID.

### GET /appkit/subscribe

Requires Bearer token (token from `/appkit/register`).

Response: `200 OK`, `text/event-stream`.

Event examples:

```
event: welcome
data: {"bundleId":"com.demo.app"}

```

```
event: callApp
data: {"bundleId":"com.demo.app","contentList":[{"type":"text","message":"..."}]}

```

If the token is missing or invalid, returns `401`.

## Root

### GET /


Response: `200 OK`

```json
{
  "name": "AgentOS API Gateway",
  "version": "1.0.0",
  "description": "Unified API gateway for all local AI services",
  "baseUrl": "http://localhost:20261",
  "endpoints": {
    "/version": "Gateway version",
    "/agentkit/*": "AgentKit API (agent service, requires Token)",
    "/appkit/*": "AppKit API (app registration/subscription)",
    "/toolkit/*": "ToolKit API (OpenTool)",
    "/llmkit/text/*": "Text generation",
    "/llmkit/vision/*": "Image-text-to-text",
    "/llmkit/embedding/*": "Text embedding",
    "/llmkit/tts/*": "Text-to-speech",
    "/llmkit/asr/*": "Speech-to-text"
  }
}
```

### GET /version

Response: `200 OK`

```json
{"version":"1.0.0"}
```

## ToolKit (Proxy to OpenTool Service)

ToolKit transparently proxies all requests to the OpenTool service running on
port `19627` (configurable via ServiceLocator).

### Endpoints

#### ALL /toolkit/*

All requests to `/toolkit/*` are forwarded to the OpenTool backend service.
Request/response bodies, status codes, headers, and query parameters are
proxied as-is. If the backend is unavailable, returns `503`:

```json
{"error": "OpenTool service unavailable"}
```

## LLMKit (Proxy to LLM Services)

LLMKit proxies requests to various LLM services. Each service type has its own
endpoint prefix.

### Service Types

| Path Prefix | Service | Default Port | Description |
| --- | --- | --- | --- |
| `/llmkit/text` | llm_text | 52010 | Text generation (chat completions) |
| `/llmkit/vision` | llm_vision | 52020 | Image-text-to-text |
| `/llmkit/embedding` | llm_embedding | 52030 | Text embeddings |
| `/llmkit/tts` | llm_tts | 52040 | Text-to-speech |
| `/llmkit/asr` | llm_asr | 52050 | Speech-to-text |

### Endpoints

#### ALL /llmkit/text/*

Proxies to text generation service. Supports streaming responses when
`Accept: text/event-stream` header is present or request body contains
`"stream": true`.

#### ALL /llmkit/vision/*

Proxies to image-text-to-text service.

#### ALL /llmkit/embedding/*

Proxies to text embedding service.

#### ALL /llmkit/tts/*

Proxies to text-to-speech service.

#### ALL /llmkit/asr/*

Proxies to speech-to-text service.

### Error Responses

If a backend service is unavailable, returns `503`:

```json
{
  "error": "Text generation service unavailable",
  "service": "llm_text"
}
```

If a backend connection error occurs, returns `502`:

```json
{
  "error": "Backend service unavailable",
  "service": "llm_text",
  "message": "Connection refused"
}
```
