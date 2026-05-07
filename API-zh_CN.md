# AgentOS HTTP API

基础地址：`http://<host>:<port>`（默认端口：`8888`）。

## 鉴权

所有 `/agentkit/*`、`/cronkit/*`、`/ragkit/*` 路由以及 `GET /appkit/subscribe`
都需要 Bearer token。

对于 `/cronkit/*`，Bearer token 必须来自 `POST /appkit/register`。
Cron 任务权限按该 token 解析出的 app 身份控制：
同一 `appGroupId` 可共享读取，写操作仍只允许 owner `bundleId`。

对于 `/ragkit/*`，Bearer token 也必须来自 `POST /appkit/register`。
Rag base 的归属信息会写入 base metadata：
写操作只允许 owner `bundleId`，读取与检索则按有效 `appGroupId` 共享。

```
Authorization: Bearer <token>
```

## AgentKit（LiteAgent 兼容网关）

AgentKit 提供 LiteAgent 兼容路由，并通过 LiteAgent SDK 执行。
默认 LiteAgent 地址来自 `DefaultServiceLocator`：
`http://127.0.0.1:9527/api/v1`。以下路由均需要 Bearer token。
若后端/SDK 调用失败，网关可能返回 `502`。

### Schema（数据结构）

#### LLMConfig

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `baseUrl` | `string` | 是 | LLM 接口 base URL。 |
| `apiKey` | `string` | 是 | LLM API key。 |
| `model` | `string` | 是 | 模型名称。 |
| `temperature` | `number` | 否 | 采样温度。 |
| `maxTokens` | `number` | 否 | 最大 token 数。 |
| `contextWindowSize` | `number` | 否 | 上下文窗口大小。 |
| `topP` | `number` | 否 | Top-p。 |
| `supportsToolCall` | `boolean` | 否 | 是否支持工具调用。 |
| `supportsReasoning` | `boolean` | 否 | 是否支持推理模式。 |

#### ApiKey

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `type` | `string` | 是 | `basic`、`bearer` 或 `original`。 |
| `apiKey` | `string` | 是 | API key 字符串。 |

#### OpenSpec

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `openSpec` | `string` | 是 | JSON 规范字符串。 |
| `protocol` | `string` | 是 | `openapi`、`jsonrpcHttp`、`opentool`、`mcpStdio`、`mcpHttp`。 |
| `serverUrl` | `string` | 否 | 覆盖 server URL。 |
| `apiKey` | `ApiKey` | 否 | API key 配置。 |

#### CallbackOpenTool

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `opentool` | `string` | 是 | OpenTool JSON。 |
| `timeout` | `number` | 否 | 超时秒数。 |

#### SessionName

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `sessionId` | `string` | 是 | Session ID。 |
| `name` | `string` | 否 | 子 Agent 名称（`[a-zA-Z0-9_-]{1,64}`）。 |
| `description` | `string` | 否 | 子 Agent 描述。 |

#### ReflectPrompt

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `llmConfig` | `LLMConfig` | 是 | 反思用 LLM 配置。 |
| `prompt` | `string` | 是 | 反思提示词。 |

#### Capability

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `llmConfig` | `LLMConfig` | 否 | LLM 配置。缺省时网关可能从 kernel 注入可用配置。 |
| `systemPrompt` | `string` | 是 | 系统提示词。 |
| `openSpecList` | `OpenSpec[]` | 否 | 工具规范列表。 |
| `callbackOpenTool` | `CallbackOpenTool` | 否 | 客户端回调工具。 |
| `sessionList` | `SessionName[]` | 否 | 子 session 列表。 |
| `reflectPromptList` | `ReflectPrompt[]` | 否 | 反思提示列表。 |
| `timeoutSeconds` | `number` | 否 | 默认 `3600`。 |
| `taskPipelineStrategy` | `string` | 否 | `parallel`、`serial`、`reject`。 |
| `toolPipelineStrategy` | `string` | 否 | `parallel`、`serial`、`reject`。 |
| `auto` | `boolean` | 否 | 是否自动执行。 |
| `llmConfigList` | `LLMConfig[]` | 否 | 候选 LLM 配置列表（模型选择/回退）。 |
| `enableThinking` | `boolean` | 否 | 是否输出推理文本。 |
| `toolReturnPackMinLength` | `number` | 否 | 工具结果打包返回的最小长度阈值。 |

#### SimpleCapability

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `llmConfig` | `LLMConfig` | 否 | LLM 配置。缺省时网关可能从 kernel 注入可用配置。 |
| `systemPrompt` | `string` | 是 | 系统提示词。 |

#### Agent

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `name` | `string` | 是 | Agent 名称。 |
| `capability` | `Capability` | 是 | Agent 能力配置。 |

#### AgentId

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `agentId` | `string` | 是 | Agent ID。 |

#### Session

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `sessionId` | `string` | 是 | Session ID。 |

#### SessionTask

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `sessionId` | `string` | 是 | Session ID。 |
| `taskId` | `string` | 否 | Task ID。 |

#### Content

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `type` | `string` | 是 | `text` 或 `imageUrl`。 |
| `message` | `string` | 是 | 文本或图片 URL/base64。 |

#### UserTask

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `content` | `Content[]` | 是 | 消息内容数组。 |
| `isChunk` | `boolean` | 否 | 是否输出 chunk 事件。 |
| `extraSystemPrompt` | `string` | 否 | 仅本次任务追加的系统提示词。 |
| `llmConfig` | `LLMConfig` | 否 | 本次任务覆盖的 LLM 配置。 |

#### ToolReturn

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `id` | `string` | 是 | 工具调用 ID。 |
| `result` | `object` | 是 | 工具返回结果。 |

#### EventToolReturn

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `event` | `string` | 是 | 流事件名。 |
| `toolReturn` | `ToolReturn` | 是 | 工具返回结果。 |

#### AgentMessage

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `sessionId` | `string` | 是 | Session ID。 |
| `agentId` | `string` | 否 | Agent ID。 |
| `parentTaskId` | `string` | 否 | 父 task ID。 |
| `taskId` | `string` | 是 | Task ID。 |
| `role` | `string` | 是 | `system`、`user`、`agent`、`llm`、`tool`。 |
| `to` | `string` | 是 | `user`、`agent`、`llm`、`tool`、`client`。 |
| `type` | `string` | 是 | `text`、`imageUrl`、`dispatch`、`contentList`、`functionCall`、`toolCalls`、`toolReturn`、`reflection`、`taskStatus`、`reasoning`、`reasoningContent`、`planning`。 |
| `content` | `any` | 是 | 内容，随 `type` 变化。 |
| `reasoningContent` | `string` | 否 | 推理文本。 |
| `completions` | `object` | 否 | Token 使用情况。 |
| `createTime` | `string` | 是 | ISO 时间。 |

`completions` 字段：

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `usage` | `object` | 是 | Token 使用量。 |
| `usage.promptTokens` | `number` | 是 | Prompt tokens。 |
| `usage.completionTokens` | `number` | 是 | Completion tokens。 |
| `usage.totalTokens` | `number` | 是 | Total tokens。 |
| `usage.contextUsageRatio` | `number` | 否 | 上下文窗口使用率（0-1）。 |
| `id` | `string` | 是 | 模型消息 ID。 |
| `model` | `string` | 是 | 模型名称。 |
| `limits` | `object` | 否 | 模型限制信息。 |
| `limits.maxTokens` | `number` | 是 | 最大输出 token 限制。 |
| `limits.contextWindowSize` | `number` | 否 | 模型上下文窗口大小。 |

#### AgentMessageChunk

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `sessionId` | `string` | 是 | Session ID。 |
| `agentId` | `string` | 否 | Agent ID。 |
| `parentTaskId` | `string` | 否 | 父 task ID。 |
| `taskId` | `string` | 是 | Task ID。 |
| `role` | `string` | 是 | `system`、`user`、`agent`、`llm`、`tool`。 |
| `to` | `string` | 是 | `user`、`agent`、`llm`、`tool`、`client`。 |
| `type` | `string` | 是 | `text`、`imageUrl`、`dispatch`、`contentList`、`functionCall`、`toolCalls`、`toolReturn`、`reflection`、`taskStatus`、`reasoning`、`reasoningContent`、`planning`。 |
| `part` | `any` | 是 | 分片内容，随 `type` 变化。 |
| `createTime` | `string` | 是 | ISO 时间。 |

### 端点

#### GET /agentkit/version

响应：`200 OK`

```
{"version":"<string>"}
```

#### GET /agentkit/agent

Query:

| 字段 | 类型 | 必填 |
| --- | --- | --- |
| `agentId` | `string` | 是 |

响应：`200 OK`（`Agent`）

#### POST /agentkit/agent/create

请求体：`Agent`

响应：`200 OK`（`AgentId`）

示例请求：

```json
{
  "name": "planner",
  "capability": {
    "systemPrompt": "You are a helpful planner.",
    "timeoutSeconds": 3600
  }
}
```

示例响应：

```json
{"agentId":"agent-1"}
```

#### POST /agentkit/agent/update

Query:

| 字段 | 类型 | 必填 |
| --- | --- | --- |
| `agentId` | `string` | 是 |

请求体：`Agent`

响应：`200 OK`（`AgentId`）

#### GET /agentkit/agent/delete

Query:

| 字段 | 类型 | 必填 |
| --- | --- | --- |
| `agentId` | `string` | 是 |

响应：`200 OK`（`AgentId`）

#### POST /agentkit/initSession

Query（可选）：

| 字段 | 类型 | 必填 |
| --- | --- | --- |
| `agentId` | `string` | 否 |

请求体（未传 `agentId` 时）：`Capability`

说明：
- 支持 `Capability.skills`，并会原样转发给 LiteAgent SDK。`skills` 的每一项都应是完整的 Agent Skills Markdown 文档。
- 每个 skill 文档的规范来源为 [agentskills.io/specification](https://agentskills.io/specification)，重点遵循其中 `SKILL.md` 的格式要求：YAML frontmatter 加 Markdown 正文。

响应：`200 OK`（`Session`）

示例请求：

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

示例响应：

```json
{"sessionId":"session-1"}
```

#### POST /agentkit/initSimple

请求体：`SimpleCapability`

说明：
- 支持 `SimpleCapability.skills`，并会原样转发给 LiteAgent SDK。`skills` 的每一项都应是完整的 Agent Skills Markdown 文档。
- 每个 skill 文档的规范来源为 [agentskills.io/specification](https://agentskills.io/specification)，重点遵循其中 `SKILL.md` 的格式要求：YAML frontmatter 加 Markdown 正文。

响应：`200 OK`（`Session`）

#### POST /agentkit/chat

Query:

| 字段 | 类型 | 必填 |
| --- | --- | --- |
| `sessionId` | `string` | 是 |

请求体：`UserTask`

响应：`200 OK`，`text/event-stream`

事件类型：
- `message`：`AgentMessage`
- `chunk`：`AgentMessageChunk`
- `functionCall`：`{"sessionId":"<string>","functionCall":FunctionCall}`

示例请求：

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

| 字段 | 类型 | 必填 |
| --- | --- | --- |
| `sessionId` | `string` | 是 |

请求体：`UserTask`

响应：`200 OK`（`AgentMessage`）

示例响应：

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

| 字段 | 类型 | 必填 |
| --- | --- | --- |
| `sessionId` | `string` | 是 |

响应：`200 OK`（`AgentMessage[]`）

示例响应：

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

| 字段 | 类型 | 必填 |
| --- | --- | --- |
| `sessionId` | `string` | 是 |
| `taskId` | `string` | 否 |

响应：`200 OK`

```json
{"status":"ok"}
```

#### GET /agentkit/clear

Query:

| 字段 | 类型 | 必填 |
| --- | --- | --- |
| `sessionId` | `string` | 是 |

响应：`200 OK`

```json
{"status":"ok"}
```

#### POST /agentkit/callback

Query:

| 字段 | 类型 | 必填 |
| --- | --- | --- |
| `sessionId` | `string` | 是 |

请求体：`ToolReturn`

响应：`200 OK`

```json
{"status":"ok"}
```

说明：
- 如果存在相同 `sessionId` + `toolReturn.id` 的待完成外部 `functionCall`，该接口会优先完成该调用。
- 否则会按兼容逻辑转发到 LiteAgent 的 `/callback`。

示例请求：

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

| 字段 | 类型 | 必填 |
| --- | --- | --- |
| `sessionId` | `string` | 是 |

请求体：`EventToolReturn`

响应：`200 OK`

```json
{"status":"ok"}
```

示例请求：

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

说明：
- 该接口是 `/agentkit/callback` 的流式配套版本。
- 适用于客户端保留了原始流事件上下文，并希望带着事件类型回传工具结果的场景。

## CronKit

CronKit 提供基于 kernel 的定时任务管理与历史读取接口。
本节所有路由都需要使用 `POST /appkit/register` 获取的 Bearer token。

### Schema（数据结构）

#### CronContent

结构与 `Content` 相同。

#### AgentCronSpec

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `systemPrompt` | `string` | 是 | 定时任务执行时使用的系统提示词。 |
| `content` | `CronContent[]` | 是 | 非空输入内容数组。 |
| `timeoutSeconds` | `number` | 否 | 执行超时时间，单位秒，默认 `3600`。 |

#### CronTask

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `cronId` | `string` | 是 | 定时任务 ID。 |
| `name` | `string` | 是 | 任务名称。 |
| `schedule` | `string` | 是 | Cron 表达式。 |
| `source` | `string` | 是 | 内部来源/归属标记。 |
| `userId` | `string` | 否 | 可选用户 ID。 |
| `sessionId` | `string` | 否 | 可选 session ID。 |
| `timezone` | `string` | 否 | 任务时区。 |
| `enabled` | `boolean` | 是 | 是否启用。 |
| `status` | `string` | 是 | 当前任务状态。 |
| `concurrency` | `string` | 是 | 并发策略。 |
| `createdAt` | `string` | 是 | ISO 时间。 |
| `updatedAt` | `string` | 是 | ISO 时间。 |
| `lastRunAt` | `string` | 否 | 最近一次执行时间。 |
| `nextRunAt` | `string` | 否 | 下一次计划执行时间。 |
| `spec` | `AgentCronSpec` | 是 | 定时任务执行 spec。 |

#### CronTaskListItem

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `cronId` | `string` | 是 | 定时任务 ID。 |
| `name` | `string` | 是 | 任务名称。 |
| `schedule` | `string` | 是 | Cron 表达式。 |
| `enabled` | `boolean` | 是 | 是否启用。 |
| `status` | `string` | 是 | 当前任务状态。 |
| `lastRunAt` | `string` | 否 | 最近一次执行时间。 |
| `nextRunAt` | `string` | 否 | 下一次计划执行时间。 |

#### CronRun

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `runId` | `string` | 是 | 执行记录 ID。 |
| `cronId` | `string` | 是 | 定时任务 ID。 |
| `status` | `string` | 是 | 执行状态。 |
| `scheduledAt` | `string` | 是 | 计划执行时间。 |
| `startedAt` | `string` | 是 | 实际开始时间。 |
| `finishedAt` | `string` | 否 | 完成时间。 |
| `liteAgentSessionId` | `string` | 否 | LiteAgent session ID。 |
| `error` | `string` | 否 | 执行失败时的错误信息。 |
| `result` | `object` | 否 | 最终执行结果。 |

#### CronRunListItem

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `runId` | `string` | 是 | 执行记录 ID。 |
| `cronId` | `string` | 是 | 定时任务 ID。 |
| `status` | `string` | 是 | 执行状态。 |
| `scheduledAt` | `string` | 是 | 计划执行时间。 |
| `startedAt` | `string` | 是 | 实际开始时间。 |
| `finishedAt` | `string` | 否 | 完成时间。 |

#### CronRunMessage

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `messageId` | `string` | 是 | 持久化消息 ID。 |
| `runId` | `string` | 是 | 执行记录 ID。 |
| `cronId` | `string` | 是 | 定时任务 ID。 |
| `timestamp` | `string` | 是 | 消息持久化时间。 |
| `message` | `AgentMessage` | 是 | 持久化消息内容。 |

### 端点

#### GET /cronkit/task

Query:

| 字段 | 类型 | 必填 |
| --- | --- | --- |
| `cronId` | `string` | 是 |

响应：`200 OK`（`CronTask`）

#### GET /cronkit/task/list

Query:

| 字段 | 类型 | 必填 |
| --- | --- | --- |
| `enabled` | `boolean` | 否 |
| `offset` | `number` | 否 |
| `limit` | `number` | 否 |

响应：`200 OK`（`CronTaskListItem[]`）

#### POST /cronkit/task/create

请求体：

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

响应：`200 OK`（`CronTask`）

说明：
- 任务归属由 Bearer token 推导，不接受客户端自行决定 `source`。
- CronKit 的任务和运行记录接口都按有效 `appGroupId` 共享访问。

示例响应：

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

请求体：带必填 `cronId` 的局部更新对象。
如果提供 `spec`，必须使用与创建时相同的 `AgentCronSpec` 结构。

响应：`200 OK`（`CronTask`）

示例请求：

```json
{
  "cronId": "cron-1",
  "enabled": false
}
```

#### POST /cronkit/task/delete

请求体：

```json
{"cronId":"<string>"}
```

响应：`200 OK`

```json
{"deleted":true,"cronId":"<string>"}
```

#### POST /cronkit/task/setEnabled

请求体：

```json
{"cronId":"<string>","enabled":true}
```

响应：`200 OK`（`CronTask`）

#### POST /cronkit/task/runNow

请求体：

```json
{"cronId":"<string>","scheduledAt":"2026-03-17T09:00:00Z"}
```

响应：`200 OK`（`CronRun`）

示例响应：

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

| 字段 | 类型 | 必填 |
| --- | --- | --- |
| `runId` | `string` | 是 |

响应：`200 OK`（`CronRun`）

说明：
- `trigger` 表示该次 run 的触发方式（如 `manual` 或 `scheduler`）。

#### GET /cronkit/run/list

Query:

| 字段 | 类型 | 必填 |
| --- | --- | --- |
| `cronId` | `string` | 否 |
| `after` | `string` | 否 |
| `before` | `string` | 否 |
| `offset` | `number` | 否 |
| `limit` | `number` | 否 |

响应：`200 OK`（`CronRunListItem[]`）

示例响应：

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

| 字段 | 类型 | 必填 |
| --- | --- | --- |
| `runId` | `string` | 是 |
| `offset` | `number` | 否 |
| `limit` | `number` | 否 |

响应：`200 OK`（`CronRunMessage[]`）

说明：
- 该接口只返回已持久化的 `AgentMessage` 记录。
- 当前 CronKit 不提供 cron 执行过程的 SSE 或订阅流接口。

示例响应：

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

如果 kernel 未配置 cron 模块，CronKit 可能返回 `503`。

## RagKit

RagKit 提供基于 kernel 的 RAG base、文档、同步与检索接口。
本节所有路由都需要使用 `POST /appkit/register` 获取的 Bearer token。

权限模型：
- Base/文档写操作要求 owner `bundleId`
- Base/文档读取与 query 按 `appGroupId` 共享

### Schema（数据结构）

#### RagBase

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `id` | `string` | 是 | RAG base ID。 |
| `name` | `string` | 是 | Base 名称。 |
| `docsName` | `string` | 是 | embeddings docs collection 名称。 |
| `docsId` | `string` | 是 | embeddings docs collection ID；embeddings 未就绪时可能为空。 |
| `metadata` | `object` | 否 | 用户 metadata，加上系统写入的归属 metadata。 |
| `createdAt` | `string` | 是 | ISO 时间。 |
| `updatedAt` | `string` | 是 | ISO 时间。 |

`metadata` 中的归属字段：

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `ownerBundleId` | `string` | 是 | 允许修改该 base 的 bundleId。 |
| `ownerAppGroupId` | `string` | 是 | 允许读取/检索该 base 的 appGroupId。 |

#### RagBaseListItem

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `id` | `string` | 是 | RAG base ID。 |
| `name` | `string` | 是 | Base 名称。 |
| `createdAt` | `string` | 是 | ISO 时间。 |
| `updatedAt` | `string` | 是 | ISO 时间。 |

#### RagDocument

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `id` | `string` | 是 | base 内唯一 document ID。 |
| `baseId` | `string` | 是 | 所属 base ID。 |
| `title` | `string` | 是 | 文档标题。 |
| `markdown` | `string` | 是 | 完整 markdown 内容。 |
| `contentHash` | `string` | 是 | 归一化内容 hash。 |
| `metadata` | `object` | 否 | 用户 metadata。 |
| `createdAt` | `string` | 是 | ISO 时间。 |
| `updatedAt` | `string` | 是 | ISO 时间。 |
| `indexedAt` | `string` | 否 | 最近一次成功同步时间。 |
| `syncStatus` | `string` | 是 | `pending`、`synced`、`failed`。 |

#### RagDocumentListItem

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `id` | `string` | 是 | base 内唯一 document ID。 |
| `baseId` | `string` | 是 | 所属 base ID。 |
| `title` | `string` | 是 | 文档标题。 |
| `updatedAt` | `string` | 是 | ISO 时间。 |
| `indexedAt` | `string` | 否 | 最近一次成功同步时间。 |
| `syncStatus` | `string` | 是 | `pending`、`synced`、`failed`。 |

#### RagMarkdownDocumentInput

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `documentId` | `string` | 是 | base 内唯一 document ID。 |
| `title` | `string` | 是 | 文档标题。 |
| `markdown` | `string` | 是 | 完整 markdown 内容。 |
| `metadata` | `object` | 否 | 用户 metadata。 |

#### RagDocumentSyncResult

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `baseId` | `string` | 是 | Base ID。 |
| `documentId` | `string` | 是 | Document ID。 |
| `syncStatus` | `string` | 是 | `pending`、`synced`、`failed`。 |
| `keptCount` | `number` | 是 | 未变更 segment 数。 |
| `updatedCount` | `number` | 是 | 更新 segment 数。 |
| `insertedCount` | `number` | 是 | 新增 segment 数。 |
| `deletedCount` | `number` | 是 | 删除 segment 数。 |
| `syncedAt` | `string` | 是 | 本次同步尝试时间。 |

#### RagBatchItemResult

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `baseId` | `string` | 是 | Base ID。 |
| `documentId` | `string` | 是 | Document ID。 |
| `status` | `string` | 是 | `success`、`failed`、`skipped`。 |
| `syncStatus` | `string` | 是 | `pending`、`synced`、`failed`。 |
| `message` | `string` | 否 | 可选失败/跳过说明。 |

#### RagBatchResult

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `totalCount` | `number` | 是 | 处理总数。 |
| `successCount` | `number` | 是 | 成功数。 |
| `failedCount` | `number` | 是 | 失败数。 |
| `skippedCount` | `number` | 是 | 跳过数。 |
| `processedAt` | `string` | 是 | ISO 时间。 |
| `items` | `RagBatchItemResult[]` | 是 | 每个文档的处理结果。 |

#### RagQueryResult

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `baseId` | `string` | 是 | Base ID。 |
| `query` | `string` | 是 | 原始 query 文本。 |
| `hits` | `RagDocumentHit[]` | 是 | 聚合后的文档命中结果。 |

#### RagDocumentHit

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `documentId` | `string` | 是 | Document ID。 |
| `title` | `string` | 是 | 文档标题。 |
| `score` | `number` | 是 | 聚合分数。 |
| `snippet` | `string` | 是 | 顶部命中片段。 |
| `segments` | `RagSegmentHit[]` | 是 | 命中的 segment。 |

#### RagSegmentHit

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `segmentId` | `string` | 是 | Segment ID。 |
| `score` | `number` | 是 | Segment 分数。 |
| `text` | `string` | 是 | Segment 文本。 |
| `headingPath` | `string` | 是 | Markdown 标题路径。 |

### 端点

#### GET /ragkit/base

Query:

| 字段 | 类型 | 必填 |
| --- | --- | --- |
| `baseId` | `string` | 是 |

响应：`200 OK`（`RagBase`）

#### GET /ragkit/base/list

Query:

| 字段 | 类型 | 必填 |
| --- | --- | --- |
| `offset` | `number` | 否 |
| `limit` | `number` | 否 |

响应：`200 OK`（`RagBaseListItem[]`）

说明：
- 只返回当前 token 所属有效 `appGroupId` 可见的 base。

#### POST /ragkit/base/create

请求体：

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

响应：`200 OK`（`RagBase`）

说明：
- 归属字段由网关注入，客户端传入的 `ownerBundleId` / `ownerAppGroupId`
  会被覆盖。

#### POST /ragkit/base/update

请求体：

```json
{
  "baseId": "product-docs",
  "name": "Product Docs v2",
  "metadata": {
    "language": "en"
  }
}
```

响应：`200 OK`（`RagBase`）

#### POST /ragkit/base/delete

请求体：

```json
{"baseId":"product-docs"}
```

响应：`200 OK`

```json
{"deleted":true,"baseId":"product-docs"}
```

#### GET /ragkit/document

Query:

| 字段 | 类型 | 必填 |
| --- | --- | --- |
| `baseId` | `string` | 是 |
| `documentId` | `string` | 是 |

响应：`200 OK`（`RagDocument`）

#### GET /ragkit/document/list

Query:

| 字段 | 类型 | 必填 |
| --- | --- | --- |
| `baseId` | `string` | 是 |
| `offset` | `number` | 否 |
| `limit` | `number` | 否 |

响应：`200 OK`（`RagDocumentListItem[]`）

#### POST /ragkit/document/upsert

请求体：

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

响应：`200 OK`（`RagDocument`）

说明：
- `sync=false` 时仅写入本地存储，不强制立即做 embeddings 同步。

#### POST /ragkit/document/upsertBatch

请求体：

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

响应：`200 OK`（`RagBatchResult`）

#### POST /ragkit/document/delete

请求体：

```json
{"baseId":"product-docs","documentId":"intro"}
```

响应：`200 OK`

```json
{"deleted":true,"baseId":"product-docs","documentId":"intro"}
```

#### POST /ragkit/sync/document

请求体：

```json
{"baseId":"product-docs","documentId":"intro"}
```

响应：`200 OK`（`RagDocumentSyncResult`）

#### POST /ragkit/sync/base

请求体：

```json
{"baseId":"product-docs"}
```

响应：`200 OK`（`RagBatchResult`）

#### POST /ragkit/sync/retryFailed

请求体：

```json
{"baseId":"product-docs"}
```

响应：`200 OK`（`RagBatchResult`）

说明：
- 如果省略 `baseId` 或传空，网关会在当前 token 可见的所有 base 范围内重试失败文档。
- 具体写权限仍按每个 base 的 owner `bundleId` 校验。

#### POST /ragkit/query

请求体：

```json
{
  "baseId": "product-docs",
  "query": "How do I ingest markdown?",
  "limit": 5,
  "candidateLimit": 20
}
```

响应：`200 OK`（`RagQueryResult`）

示例：

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

请求体：

```
{"bundleId":"com.demo.app","appGroupId":"com.demo"}
```

响应：`200 OK`

```
{"token":"sk-...","bundleId":"com.demo.app","appGroupId":"com.demo"}
```

未显式传 `appGroupId` 的示例请求：

```json
{"bundleId":"com.demo.app"}
```

示例响应：

```json
{"token":"sk-...","bundleId":"com.demo.app","appGroupId":"com.demo.app"}
```

说明：
- `appGroupId` 是可选的。
- 如果不传，服务端会默认使用 `bundleId` 作为有效 group ID。

### GET /appkit/subscribe

需要 Bearer token（来自 `/appkit/register`）。

响应：`200 OK`，`text/event-stream`。

事件示例：

```
event: welcome
data: {"bundleId":"com.demo.app"}

```

```
event: callApp
data: {"bundleId":"com.demo.app","contentList":[{"type":"text","message":"..."}]}

```

如果 token 缺失或无效，直接返回 `401`。

## Root

### GET /


响应：`200 OK`

```json
{
  "name": "AgentOS API Gateway",
  "version": "1.0.0",
  "description": "统一 API 网关，提供所有本地 AI 服务的统一访问入口",
  "baseUrl": "http://localhost:8888",
  "endpoints": {
    "/version": "网关版本",
    "/ready": "网关就绪状态",
    "/agentkit/*": "AgentKit API（智能体服务，需要 Token）",
    "/cronkit/*": "CronKit API（定时任务管理，需要 Token）",
    "/ragkit/*": "RagKit API（RAG 知识库/检索，需要 Token）",
    "/appkit/*": "AppKit API（应用注册/订阅）",
    "/toolkit/*": "ToolKit API",
    "/llmkit/text/*": "文本生成",
    "/llmkit/vision/*": "图文理解",
    "/llmkit/embedding/*": "文本嵌入",
    "/llmkit/tts/*": "文本转语音",
    "/llmkit/asr/*": "语音转文本"
  }
}
```

### GET /version

响应：`200 OK`

```json
{"version":"1.0.0"}
```

### GET /ready

响应：`200 OK` 或 `503 Service Unavailable`

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

## ToolKit API

ToolKit 是工具运行时 API 的网关入口。外部客户端访问 AgentOS API Gateway 的
`/toolkit/*` 路由即可，不需要连接、配置或理解内部工具运行时路径。Server
构建/导入、进程生命周期等管理接口由平台侧处理，不作为公开 ToolKit API 暴露。

ToolKit 请求需要携带 `POST /appkit/register` 返回的 Bearer token。

网关使用默认端口运行时，可这样调用：

```bash
TOKEN=$(curl -s http://127.0.0.1:8888/appkit/register \
  -H 'content-type: application/json' \
  -d '{"bundleId":"com.demo.app"}' | jq -r .token)
curl http://127.0.0.1:8888/toolkit/list \
  -H "authorization: Bearer $TOKEN"
```

### 鉴权

所有 ToolKit 端点都需要：

```http
Authorization: Bearer <POST /appkit/register 返回的 token>
```

缺少 token 或 token 无效时返回 `401`。

### 端点总览

| 方法 | 路径 | 说明 |
| --- | --- | --- |
| GET | `/toolkit/list` | 列出运行中的工具，`all=1` 时列出全部工具。 |
| POST | `/toolkit/{toolId}/call` | 调用工具函数。 |
| POST | `/toolkit/{toolId}/streamCall` | 调用工具函数并通过 SSE 返回结果。 |
| GET | `/toolkit/{toolId}/load` | 返回工具描述和函数 schema。 |

### 常用 Schema

#### Tool

```json
{
  "id": "tool-1",
  "alias": "alpha",
  "host": "127.0.0.1",
  "port": 9001,
  "status": "running",
  "serverId": "srv-1"
}
```

`status` 通常为 `running` 或 `notRunning`。`serverId` 可能不存在，也可能指向
平台侧预置的 server。

#### FunctionCall

```json
{
  "id": "call-001",
  "name": "status",
  "arguments": {
    "depth": 1
  }
}
```

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `id` | `string` | 是 | 客户端生成的调用 id；`ToolReturn` 会返回同一个 id。 |
| `name` | `string` | 是 | 函数名，来自 `GET /toolkit/{toolId}/load`。 |
| `arguments` | `object` | 是 | 函数参数，需要匹配函数参数 schema。 |

#### ToolReturn

```json
{
  "id": "call-001",
  "result": {
    "ok": true
  }
}
```

#### SSE 结果

`POST /toolkit/{toolId}/streamCall` 返回 `text/event-stream`：

```text
event:DATA
data:{"json":"payload"}
```

通用事件名包括 `START`、`DATA`、`DONE`、`ERROR`。

### 端点

#### GET /toolkit/list

查询参数：

| 名称 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `all` | `0` 或 `1` | 否 | 省略或 `0` 只返回运行中的工具；`1` 返回包含已停止工具在内的全部工具。 |

响应：

```json
[
  {
    "id": "tool-1",
    "alias": "alpha",
    "host": "127.0.0.1",
    "port": 9001,
    "status": "running",
    "serverId": "srv-1"
  }
]
```

#### GET /toolkit/{toolId}/load

返回工具的 OpenTool JSON 描述。调用函数前可用该端点发现函数、参数和返回 schema。

响应形状：

```json
{
  "info": {
    "title": "Demo Tool",
    "version": "1.0.0"
  },
  "functions": [
    {
      "name": "status",
      "description": "Return current status.",
      "parameters": [
        {
          "name": "depth",
          "description": "Detail depth.",
          "schema": {"type": "integer"}
        }
      ],
      "return": {
        "name": "result",
        "schema": {"type": "object"}
      }
    }
  ]
}
```

#### POST /toolkit/{toolId}/call

请求体：

```json
{
  "id": "call-001",
  "name": "status",
  "arguments": {
    "depth": 1
  }
}
```

响应：

```json
{
  "id": "call-001",
  "result": {
    "ok": true
  }
}
```

#### POST /toolkit/{toolId}/streamCall

请求体：同 `/toolkit/{toolId}/call`。

响应：`text/event-stream`，适合长耗时函数或增量结果。

### 错误

工具服务不可用时返回 `503`：

```json
{"error": "OpenTool service unavailable"}
```

## LLMKit（代理 LLM 服务）

LLMKit 代理请求到各种 LLM 服务。每种服务类型有独立的端点前缀。

### 服务类型

| 路径前缀 | 服务标识 | 默认端口 | 说明 |
| --- | --- | --- | --- |
| `/llmkit/text` | llm_text | 52010 | 文本生成（chat completions） |
| `/llmkit/vision` | llm_vision | 52020 | 图文理解 |
| `/llmkit/embedding` | llm_embedding | 52030 | 文本嵌入 |
| `/llmkit/tts` | llm_tts | 52040 | 文本转语音 |
| `/llmkit/asr` | llm_asr | 52050 | 语音转文本 |

### 端点

#### ALL /llmkit/text/*

代理到文本生成服务。当请求头包含 `Accept: text/event-stream` 或
请求体包含 `"stream": true` 时支持流式响应。

示例请求：

```json
{
  "model": "qwen3-8b",
  "messages": [
    {"role": "user", "content": "Hello"}
  ]
}
```

示例响应：

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

代理到图文理解服务。

#### ALL /llmkit/embedding/*

代理到文本嵌入服务。

示例请求：

```json
{
  "model": "bge-large-zh-v1.5-q8_0",
  "input": ["hello world"]
}
```

示例响应：

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

代理到文本转语音服务。

#### ALL /llmkit/asr/*

代理到语音转文本服务。

#### GET /llmkit/models

列出当前通过 service locator 可见的文本能力模型。返回运行中的本地模型，
以及远程模型。

响应：`200 OK`

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

### 错误响应

后端服务不可用时返回 `503`：

```json
{
  "error": "文本生成 服务不可用",
  "service": "llm_text"
}
```

后端连接错误时返回 `502`：

```json
{
  "error": "后端服务不可用",
  "service": "llm_text",
  "message": "Connection refused"
}
```
