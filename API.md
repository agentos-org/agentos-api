# AgentOS HTTP API

Base URL: `http://<host>:<port>` (default port: `8888`).

## Authentication

Bearer token is required for all `/agentkit/*`, `/cronkit/*`, and `/ragkit/*`
routes, and for `GET /appkit/subscribe`.

For `/cronkit/*`, the bearer token must be an AppKit-issued token from
`POST /appkit/register`. Cron task ownership is isolated by the token's
resolved app identity. Reads are shared within the same effective
`appGroupId`, while writes stay restricted to the owner `bundleId`.

For `/ragkit/*`, the bearer token must also be an AppKit-issued token from
`POST /appkit/register`. Rag base ownership is stored on the base metadata:
write operations are restricted to the owner `bundleId`, while reads and query
are shared within the same effective `appGroupId`.

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

Example request:

```json
{
  "name": "planner",
  "capability": {
    "systemPrompt": "You are a helpful planner.",
    "timeoutSeconds": 3600
  }
}
```

Example response:

```json
{"agentId":"agent-1"}
```

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

Notes:
- `Capability.skills` is supported and forwarded as-is to LiteAgent SDK. Each item should be a complete Agent Skills markdown document.
- The source spec for each skill document is [agentskills.io/specification](https://agentskills.io/specification), especially the `SKILL.md` format with YAML frontmatter followed by Markdown content.

Response: `200 OK` (`Session`)

Example request:

```json
{
  "systemPrompt": "You are a helpful planner.",
  "llmConfig": {
    "baseUrl": "http://127.0.0.1:52010",
    "apiKey": "",
    "model": "qwen3-8b"
  }
}
```

Example response:

```json
{"sessionId":"session-1"}
```

#### POST /agentkit/initSimple

Request body: `SimpleCapability`

Notes:
- `SimpleCapability.skills` is supported and forwarded as-is to LiteAgent SDK. Each item should be a complete Agent Skills markdown document.
- The source spec for each skill document is [agentskills.io/specification](https://agentskills.io/specification), especially the `SKILL.md` format with YAML frontmatter followed by Markdown content.

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

Example request:

```json
{
  "content": [
    {"type": "text", "message": "Summarize this repository."}
  ],
  "isChunk": true
}
```

#### POST /agentkit/chat/simple

Query:

| Field | Type | Required |
| --- | --- | --- |
| `sessionId` | `string` | Yes |

Request body: `UserTask`

Response: `200 OK` (`AgentMessage`)

Example response:

```json
{
  "sessionId": "session-1",
  "taskId": "task-1",
  "role": "llm",
  "to": "user",
  "type": "text",
  "content": "This repository provides a unified API gateway for local AI services.",
  "createTime": "2026-04-08T10:00:02.000Z"
}
```

#### GET /agentkit/history

Query:

| Field | Type | Required |
| --- | --- | --- |
| `sessionId` | `string` | Yes |

Response: `200 OK` (`AgentMessage[]`)

Example response:

```json
[
  {
    "sessionId": "session-1",
    "taskId": "task-1",
    "role": "user",
    "to": "agent",
    "type": "contentList",
    "content": [
      {"type": "text", "message": "Summarize this repository."}
    ],
    "createTime": "2026-04-08T10:00:00.000Z"
  }
]
```

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

Example request:

```json
{
  "id": "call-1",
  "result": {
    "ok": true,
    "content": "Tool execution finished."
  }
}
```

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

Example request:

```json
{
  "event": "functionCall",
  "toolReturn": {
    "id": "call-1",
    "result": {
      "ok": true,
      "content": "Tool execution finished."
    }
  }
}
```

Notes:
- This endpoint is the stream-oriented callback companion to `/agentkit/callback`.
- It is typically used when the client keeps event context and wants to return a tool result tagged with the original stream event type.

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

Example response:

```json
{
  "cronId": "cron-1",
  "name": "Daily Summary",
  "schedule": "0 9 * * *",
  "source": "appkit|owner=com.demo.app|group=com.demo",
  "timezone": "Asia/Shanghai",
  "enabled": true,
  "status": "active",
  "concurrency": "skipIfRunning",
  "createdAt": "2026-04-08T09:00:00.000Z",
  "updatedAt": "2026-04-08T09:00:00.000Z",
  "nextRunAt": "2026-04-09T09:00:00.000Z",
  "spec": {
    "systemPrompt": "You are a scheduled agent.",
    "content": [
      {"type": "text", "message": "Generate today's summary."}
    ],
    "timeoutSeconds": 3600
  }
}
```

#### POST /cronkit/task/update

Request body: partial `CronTask` update payload with required `cronId`.
`spec`, when provided, must use the same `AgentCronSpec` shape as creation.

Response: `200 OK` (`CronTask`)

Example request:

```json
{
  "cronId": "cron-1",
  "enabled": false
}
```

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

Example response:

```json
{
  "runId": "run-1",
  "cronId": "cron-1",
  "trigger": "manual",
  "status": "succeeded",
  "scheduledAt": "2026-03-17T09:00:00.000Z",
  "startedAt": "2026-03-17T09:00:01.000Z",
  "finishedAt": "2026-03-17T09:00:30.000Z",
  "hasDisplayableResult": false,
  "result": {
    "message": "ok"
  }
}
```

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

Example response:

```json
[
  {
    "runId": "run-1",
    "cronId": "cron-1",
    "trigger": "manual",
    "status": "succeeded",
    "scheduledAt": "2026-03-17T09:00:00.000Z",
    "startedAt": "2026-03-17T09:00:01.000Z",
    "finishedAt": "2026-03-17T09:00:30.000Z",
    "hasDisplayableResult": false
  }
]
```

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

Example response:

```json
[
  {
    "messageId": "msg-1",
    "runId": "run-1",
    "cronId": "cron-1",
    "timestamp": "2026-03-17T09:00:02.000Z",
    "message": {
      "sessionId": "session-1",
      "taskId": "task-1",
      "role": "llm",
      "to": "user",
      "type": "text",
      "content": "Today's summary is ready.",
      "createTime": "2026-03-17T09:00:02.000Z"
    }
  }
]
```

If kernel cron is unavailable, CronKit may return `503`.

## RagKit

RagKit exposes kernel-backed RAG base, document, sync, and query APIs.
All routes in this section require a Bearer token from `POST /appkit/register`.

Authorization model:
- Base/document write operations require the owner `bundleId`
- Base/document reads and query are shared within the same `appGroupId`

### Schemas

#### RagBase

| Field | Type | Required | Description |
| --- | --- | --- | --- |
| `id` | `string` | Yes | RAG base ID. |
| `name` | `string` | Yes | Base name. |
| `docsName` | `string` | Yes | Embeddings docs collection name. |
| `docsId` | `string` | Yes | Embeddings docs collection ID. May be empty before embeddings are ready. |
| `metadata` | `object` | No | User metadata plus system ownership metadata. |
| `createdAt` | `string` | Yes | ISO timestamp. |
| `updatedAt` | `string` | Yes | ISO timestamp. |

Ownership fields stored in `metadata`:

| Field | Type | Required | Description |
| --- | --- | --- | --- |
| `ownerBundleId` | `string` | Yes | Bundle allowed to modify this base. |
| `ownerAppGroupId` | `string` | Yes | App group allowed to read/query this base. |

#### RagBaseListItem

| Field | Type | Required | Description |
| --- | --- | --- | --- |
| `id` | `string` | Yes | RAG base ID. |
| `name` | `string` | Yes | Base name. |
| `createdAt` | `string` | Yes | ISO timestamp. |
| `updatedAt` | `string` | Yes | ISO timestamp. |

#### RagDocument

| Field | Type | Required | Description |
| --- | --- | --- | --- |
| `id` | `string` | Yes | Base-scoped document ID. |
| `baseId` | `string` | Yes | Parent base ID. |
| `title` | `string` | Yes | Document title. |
| `markdown` | `string` | Yes | Full markdown body. |
| `contentHash` | `string` | Yes | Stable normalized content hash. |
| `metadata` | `object` | No | User metadata. |
| `createdAt` | `string` | Yes | ISO timestamp. |
| `updatedAt` | `string` | Yes | ISO timestamp. |
| `indexedAt` | `string` | No | ISO timestamp of last successful sync. |
| `syncStatus` | `string` | Yes | `pending`, `synced`, or `failed`. |

#### RagDocumentListItem

| Field | Type | Required | Description |
| --- | --- | --- | --- |
| `id` | `string` | Yes | Base-scoped document ID. |
| `baseId` | `string` | Yes | Parent base ID. |
| `title` | `string` | Yes | Document title. |
| `updatedAt` | `string` | Yes | ISO timestamp. |
| `indexedAt` | `string` | No | ISO timestamp of last successful sync. |
| `syncStatus` | `string` | Yes | `pending`, `synced`, or `failed`. |

#### RagMarkdownDocumentInput

| Field | Type | Required | Description |
| --- | --- | --- | --- |
| `documentId` | `string` | Yes | Base-scoped document ID. |
| `title` | `string` | Yes | Document title. |
| `markdown` | `string` | Yes | Full markdown body. |
| `metadata` | `object` | No | User metadata. |

#### RagDocumentSyncResult

| Field | Type | Required | Description |
| --- | --- | --- | --- |
| `baseId` | `string` | Yes | Base ID. |
| `documentId` | `string` | Yes | Document ID. |
| `syncStatus` | `string` | Yes | `pending`, `synced`, or `failed`. |
| `keptCount` | `number` | Yes | Unchanged segment count. |
| `updatedCount` | `number` | Yes | Updated segment count. |
| `insertedCount` | `number` | Yes | Inserted segment count. |
| `deletedCount` | `number` | Yes | Deleted segment count. |
| `syncedAt` | `string` | Yes | ISO timestamp for this sync attempt. |

#### RagBatchItemResult

| Field | Type | Required | Description |
| --- | --- | --- | --- |
| `baseId` | `string` | Yes | Base ID. |
| `documentId` | `string` | Yes | Document ID. |
| `status` | `string` | Yes | `success`, `failed`, or `skipped`. |
| `syncStatus` | `string` | Yes | `pending`, `synced`, or `failed`. |
| `message` | `string` | No | Optional failure or skip message. |

#### RagBatchResult

| Field | Type | Required | Description |
| --- | --- | --- | --- |
| `totalCount` | `number` | Yes | Total processed item count. |
| `successCount` | `number` | Yes | Success item count. |
| `failedCount` | `number` | Yes | Failed item count. |
| `skippedCount` | `number` | Yes | Skipped item count. |
| `processedAt` | `string` | Yes | ISO timestamp. |
| `items` | `RagBatchItemResult[]` | Yes | Per-document results. |

#### RagQueryResult

| Field | Type | Required | Description |
| --- | --- | --- | --- |
| `baseId` | `string` | Yes | Base ID. |
| `query` | `string` | Yes | Original query text. |
| `hits` | `RagDocumentHit[]` | Yes | Aggregated document hits. |

#### RagDocumentHit

| Field | Type | Required | Description |
| --- | --- | --- | --- |
| `documentId` | `string` | Yes | Document ID. |
| `title` | `string` | Yes | Document title. |
| `score` | `number` | Yes | Aggregated score. |
| `snippet` | `string` | Yes | Top matching snippet. |
| `segments` | `RagSegmentHit[]` | Yes | Matching segments. |

#### RagSegmentHit

| Field | Type | Required | Description |
| --- | --- | --- | --- |
| `segmentId` | `string` | Yes | Segment ID. |
| `score` | `number` | Yes | Segment score. |
| `text` | `string` | Yes | Segment text. |
| `headingPath` | `string` | Yes | Markdown heading path. |

### Endpoints

#### GET /ragkit/base

Query:

| Field | Type | Required |
| --- | --- | --- |
| `baseId` | `string` | Yes |

Response: `200 OK` (`RagBase`)

#### GET /ragkit/base/list

Query:

| Field | Type | Required |
| --- | --- | --- |
| `offset` | `number` | No |
| `limit` | `number` | No |

Response: `200 OK` (`RagBaseListItem[]`)

Notes:
- Returns only bases visible to the current token's effective `appGroupId`.

#### POST /ragkit/base/create

Request body:

```json
{
  "baseId": "product-docs",
  "name": "Product Docs",
  "metadata": {
    "domain": "docs",
    "language": "en"
  }
}
```

Response: `200 OK` (`RagBase`)

Notes:
- Ownership metadata is injected by the gateway. Client-supplied
  `ownerBundleId` / `ownerAppGroupId` values are overwritten.

#### POST /ragkit/base/update

Request body:

```json
{
  "baseId": "product-docs",
  "name": "Product Docs v2",
  "metadata": {
    "language": "en"
  }
}
```

Response: `200 OK` (`RagBase`)

#### POST /ragkit/base/delete

Request body:

```json
{"baseId":"product-docs"}
```

Response: `200 OK`

```json
{"deleted":true,"baseId":"product-docs"}
```

#### GET /ragkit/document

Query:

| Field | Type | Required |
| --- | --- | --- |
| `baseId` | `string` | Yes |
| `documentId` | `string` | Yes |

Response: `200 OK` (`RagDocument`)

#### GET /ragkit/document/list

Query:

| Field | Type | Required |
| --- | --- | --- |
| `baseId` | `string` | Yes |
| `offset` | `number` | No |
| `limit` | `number` | No |

Response: `200 OK` (`RagDocumentListItem[]`)

#### POST /ragkit/document/upsert

Request body:

```json
{
  "baseId": "product-docs",
  "documentId": "intro",
  "title": "Introduction",
  "markdown": "# Intro\n\nHello world",
  "metadata": {
    "source": "manual"
  },
  "sync": true
}
```

Response: `200 OK` (`RagDocument`)

Notes:
- `sync=false` stores the document locally without forcing immediate embeddings sync.

#### POST /ragkit/document/upsertBatch

Request body:

```json
{
  "baseId": "product-docs",
  "sync": false,
  "documents": [
    {
      "documentId": "intro",
      "title": "Introduction",
      "markdown": "# Intro\n\nHello world"
    },
    {
      "documentId": "faq",
      "title": "FAQ",
      "markdown": "# FAQ\n\nCommon questions"
    }
  ]
}
```

Response: `200 OK` (`RagBatchResult`)

#### POST /ragkit/document/delete

Request body:

```json
{"baseId":"product-docs","documentId":"intro"}
```

Response: `200 OK`

```json
{"deleted":true,"baseId":"product-docs","documentId":"intro"}
```

#### POST /ragkit/sync/document

Request body:

```json
{"baseId":"product-docs","documentId":"intro"}
```

Response: `200 OK` (`RagDocumentSyncResult`)

#### POST /ragkit/sync/base

Request body:

```json
{"baseId":"product-docs"}
```

Response: `200 OK` (`RagBatchResult`)

#### POST /ragkit/sync/retryFailed

Request body:

```json
{"baseId":"product-docs"}
```

Response: `200 OK` (`RagBatchResult`)

Notes:
- If `baseId` is omitted or empty, the gateway retries failed documents across
  all bases visible to the current token's `appGroupId`.
- Writes are still restricted to owner `bundleId` on a per-base basis.

#### POST /ragkit/query

Request body:

```json
{
  "baseId": "product-docs",
  "query": "How do I ingest markdown?",
  "limit": 5,
  "candidateLimit": 20
}
```

Response: `200 OK` (`RagQueryResult`)

Example:

```json
{
  "baseId": "product-docs",
  "query": "How do I ingest markdown?",
  "hits": [
    {
      "documentId": "intro",
      "title": "Introduction",
      "score": 0.91,
      "snippet": "RAG documents are ingested from markdown text.",
      "segments": [
        {
          "segmentId": "seg-1",
          "score": 0.91,
          "text": "RAG documents are ingested from markdown text.",
          "headingPath": "Intro"
        }
      ]
    }
  ]
}
```

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

Example request without explicit `appGroupId`:

```json
{"bundleId":"com.demo.app"}
```

Example response:

```json
{"token":"sk-...","bundleId":"com.demo.app","appGroupId":"com.demo.app"}
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
  "baseUrl": "http://localhost:8888",
  "endpoints": {
    "/version": "Gateway version",
    "/ready": "Gateway readiness",
    "/agentkit/*": "AgentKit API (agent service, requires Token)",
    "/cronkit/*": "CronKit API (cron task management, requires Token)",
    "/ragkit/*": "RagKit API (RAG knowledge/query, requires Token)",
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

### GET /ready

Response: `200 OK` or `503 Service Unavailable`

```json
{
  "ready": true,
  "llmConfigured": true,
  "llmServicesReady": true,
  "liteAgentReady": true,
  "openToolDaemonReady": true,
  "embeddingsReady": true,
  "reasons": []
}
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

Example request:

```json
{
  "model": "qwen3-8b",
  "messages": [
    {"role": "user", "content": "Hello"}
  ]
}
```

Example response:

```json
{
  "id": "chatcmpl-1",
  "object": "chat.completion",
  "model": "qwen3-8b",
  "choices": [
    {
      "index": 0,
      "message": {"role": "assistant", "content": "Hello!"},
      "finish_reason": "stop"
    }
  ]
}
```

#### ALL /llmkit/vision/*

Proxies to image-text-to-text service.

#### ALL /llmkit/embedding/*

Proxies to text embedding service.

Example request:

```json
{
  "model": "bge-large-zh-v1.5-q8_0",
  "input": ["hello world"]
}
```

Example response:

```json
{
  "object": "list",
  "data": [
    {
      "object": "embedding",
      "index": 0,
      "embedding": [0.1, 0.2, 0.3]
    }
  ],
  "model": "bge-large-zh-v1.5-q8_0"
}
```

#### ALL /llmkit/tts/*

Proxies to text-to-speech service.

#### ALL /llmkit/asr/*

Proxies to speech-to-text service.

#### GET /llmkit/models

Lists currently available text-capable models visible through the service
locator. Returns local running models plus remote models.

Response: `200 OK`

```json
[
  {
    "id": "qwen3-8b",
    "name": "qwen3-8b",
    "alias": "qwen3-8b",
    "description": "text model",
    "type": "textGeneration",
    "contextWindowSize": 8192,
    "isRemote": false,
    "isCustom": false
  }
]
```

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
