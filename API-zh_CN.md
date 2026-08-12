# AgentOS HTTP API

基础地址：`http://<host>:<port>`（默认端口：`8888`）。

## 鉴权

所有 `/agentkit/*`、`/cronkit/*`、`/ragkit/*`、`/authkit/*`、
`/discoverykit/*`、`/transferkit/*` 路由以及 `GET /appkit/subscribe`
都需要 Bearer token。

对于 `/cronkit/*`，Bearer token 必须来自 `POST /appkit/register`。
Cron 任务权限按该 token 解析出的 app 身份控制：
同一 `appGroupId` 可共享读取，写操作仍只允许 owner `bundleId`。

对于 `/ragkit/*`，Bearer token 也必须来自 `POST /appkit/register`。
Rag base 的归属信息会写入 base metadata：
写操作只允许 owner `bundleId`，读取与检索则按有效 `appGroupId` 共享。

对于 `/authkit/*`，大多数端点需要 AppKit 签发的 Bearer token。例外是
`GET /authkit/userinfo`，该端点需要通过授权流程获取的 AuthKit access token。

对于 `/discoverykit/*` 和 `/transferkit/*`，Bearer token 必须来自
`POST /appkit/register`。

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
| `modelId` | `string` | 否 | AgentKit 网关扩展字段。`/agentkit/initSession`、`/agentkit/initSimple` 以及 `/agentkit/chat` 这类按任务覆盖 `llmConfig` 的接口均支持。传入后，网关会在内部模型注册表中查找并展开成一份具体的 `llmConfig`。 |
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
| `timeout` | 正整数 | 否 | 外部回调超时秒数。AgentKit 按 session 保存；未提供或值非法时使用网关兼容默认值 300 秒。 |

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
| `maxLlmRequests` | `number` | 否 | 单个工具型任务允许的大模型请求次数上限，默认 `64`；非正数使用服务端默认值。 |
| `maxToolRounds` | `number` | 否 | 单个任务允许的工具调用轮数上限，默认 `16`；非正数使用服务端默认值。 |
| `maxToolCalls` | `number` | 否 | 单个任务允许的工具调用总数上限，默认 `64`；非正数使用服务端默认值。 |
| `maxConsecutiveIdenticalToolRounds` | `number` | 否 | 工具名称及规范化参数完全相同的连续调用轮数上限，默认 `3`；非正数使用服务端默认值。 |
| `maxTaskDurationSeconds` | `number` | 否 | 单个工具型任务的最长执行时间，单位为秒，默认 `300`；非正数使用服务端默认值。 |

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
| `originalTaskId` | `string` | 是 | 根任务 ID。对于旧版 LiteAgent 响应，该字段回退为 `taskId`。 |
| `parentTaskId` | `string` | 否 | 父 task ID。 |
| `taskId` | `string` | 是 | Task ID。 |
| `role` | `string` | 是 | `system`、`user`、`agent`、`llm`、`tool`。 |
| `to` | `string` | 是 | `user`、`agent`、`llm`、`tool`、`client`。 |
| `type` | `string` | 是 | `text`、`imageUrl`、`dispatch`、`contentList`、`functionCall`、`toolCalls`、`toolReturn`、`reflection`、`taskStatus`、`reasoning`、`reasoningContent`、`planning`。 |
| `content` | `any` | 是 | 内容，随 `type` 变化。 |
| `reasoningContent` | `string` | 否 | 推理文本。 |
| `completions` | `object` | 否 | Token 使用情况。 |
| `createTime` | `string` | 是 | ISO 时间。 |

当 `type` 为 `taskStatus` 时，`content` 包含：

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `status` | `string` | 是 | 当前任务状态。 |
| `taskId` | `string` | 否 | 与该状态更新关联的任务 ID。 |
| `description` | `object` | 否 | 额外的状态详情。 |

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
- 也支持 `Capability.llmConfig.modelId`。AgentKit 会先用 `modelId` 在内部模型注册表中做反查，再展开成 LiteAgent 可用的具体 `llmConfig`。其中解析出的模型名会写入 `llmConfig.model`；同时网关还会在可用时补齐 `baseUrl`、`apiKey`、`provider`、`adapter`、`contextWindowSize` 等字段。
- 网关使用 `callbackOpenTool.timeout` 等待外部 function call 回调。通过 `agentId` 初始化时，会在可获取的情况下读取已保存的 Agent capability；无法获取时使用兼容默认值 300 秒。

响应：`200 OK`（`Session`）

示例请求：

直接传 LiteAgent 兼容字段：

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

使用 `modelId` 反查：

```json
{
  "systemPrompt": "You are a helpful planner.",
  "llmConfig": {
    "modelId": "qwen3-8b"
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
- `SimpleCapability.llmConfig.modelId` 也受支持，解析行为与 `/agentkit/initSession` 相同。

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
| `page` | `integer` | 否 |
| `pageSize` | `integer` | 否 |

`page` 和 `pageSize` 必须成对提供，且均为正整数。页码从 1 开始；两者均省略时，返回完整的持久化历史记录。

响应：`200 OK`（`AgentMessage[]`）

示例响应：

```json
[
  {
    "sessionId": "session-1",
    "originalTaskId": "task-1",
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

#### GET /agentkit/history/summary

按任务轮次返回轻量摘要，用于摘要优先的历史加载。`page` 默认为 `1`，
`pageSize` 默认为 `30`，且不能超过 `200`。

Query：

| 字段 | 类型 | 必填 |
| --- | --- | --- |
| `sessionId` | `string` | 是 |
| `page` | `integer` | 否 |
| `pageSize` | `integer` | 否 |

响应：`200 OK`（`HistoryTurnSummaryDto[]`）

#### GET /agentkit/history/process

按任务轮次懒加载过程消息。`page` 默认为 `1`，`pageSize` 默认为 `50`，
且不能超过 `200`。

Query：

| 字段 | 类型 | 必填 |
| --- | --- | --- |
| `sessionId` | `string` | 是 |
| `originalTaskId` | `string` | 是 |
| `page` | `integer` | 否 |
| `pageSize` | `integer` | 否 |

响应：`200 OK`（`AgentMessage[]`）

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
- 对于已经超时或完成的网关代理调用，迟到 callback 返回 `200 OK`，响应为 `{"status":"ignored","reason":"callback_expired"}` 或 `callback_completed`，且不会再次转发到下游。
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
- 已超时或完成的网关代理调用，其迟到流事件同样返回 `200 OK` 的 ignored 响应，并且不会再次转发到下游。

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

App 也可以通过稳定的 `ref` 和 server `name` 声明本地 OpenTool Server 依赖：

```json
{
  "bundleId": "com.demo.app",
  "opentoolServers": [
    {"ref": "websearch", "name": "opentool-server-websearch"}
  ]
}
```

注册始终选择同名 server 中已安装的最高语义版本，App 不能固定具体版本。如果同名
server 的 version 都不是语义版本，则继续采用 daemon 返回的顺序。

该集成要求 OpenTool daemon API v2 且具备 `artifactRegistryV2` 与
`startToolTerminalV1` capability（daemon 0.5.0 或更高版本）。读取 Server 或
Tool 数据前会拒绝旧版 daemon 契约。

网关会在返回前快速检查本地 OpenTool daemon。已经可用的工具返回可调用的
`id`；正在拉起或本地没有找到的工具不返回 `id`：

```json
{
  "token": "sk-...",
  "bundleId": "com.demo.app",
  "appGroupId": "com.demo.app",
  "opentoolServers": [
    {
      "ref": "websearch",
      "server": {
        "namespace": "local",
        "name": "opentool-server-websearch",
        "version": "1.2.0"
      },
      "status": "running",
      "id": "tool-..."
    }
  ]
}
```

注册状态包括 `running`、`starting`、`notFound`。只有 `running` 返回 `id`。
`starting` 会在后台继续执行；最终成功或失败都会通过 `GET /appkit/subscribe`
通知 App。

### GET /appkit/subscribe

需要 Bearer token（来自 `/appkit/register`）。

响应：`200 OK`，`text/event-stream`。

事件示例：

```
event: welcome
data: {"bundleId":"com.demo.app"}

```

新的业务通知统一使用 `appEvent` envelope。register 返回 `starting` 后，ToolKit
成功拉起本地 OpenTool Server 时会推送最终可调用的 tool ID：

```text
id: evt-...
event: appEvent
data: {"version":1,"id":"evt-...","type":"toolkit.provision.succeeded","source":"toolkit","time":"2026-07-15T10:30:00.000Z","subject":"websearch","data":{"ref":"websearch","name":"opentool-server-websearch","status":"running","server":{"namespace":"local","name":"opentool-server-websearch","version":"1.2.0"},"id":"tool-..."}}

```

如果拉起失败，则推送：

```text
id: evt-...
event: appEvent
data: {"version":1,"id":"evt-...","type":"toolkit.provision.failed","source":"toolkit","time":"2026-07-15T10:30:00.000Z","subject":"websearch","data":{"ref":"websearch","name":"opentool-server-websearch","status":"failed","server":{"namespace":"local","name":"opentool-server-websearch","version":"1.2.0"},"error":{"code":"startFailed","message":"..."}}}

```

声明的 tool 就绪后，AgentOS 会持续监控 OpenTool daemon 和具体 tool 进程。
任意一层不可用时推送：

```text
id: evt-...
event: appEvent
data: {"version":1,"id":"evt-...","type":"toolkit.tool.unavailable","source":"toolkit","time":"2026-07-15T10:35:00.000Z","subject":"websearch","data":{"ref":"websearch","name":"opentool-server-websearch","id":"tool-...","status":"unavailable","scope":"tool","reason":"healthcheckFailed","server":{"namespace":"local","name":"opentool-server-websearch","version":"1.2.0"}}}

```

daemon 停止、报错或无法连接时，`scope` 为 `daemon`；否则为 `tool`。tool 层的
`reason` 包括 `removed`、`stopped`、`healthcheckFailed`；daemon 层包括
`daemonStarting`、`daemonStopped`、`daemonError`、`daemonUnavailable`。

同一个 tool 恢复健康后，AgentOS 会推送对应的恢复事件：

```text
id: evt-...
event: appEvent
data: {"version":1,"id":"evt-...","type":"toolkit.tool.available","source":"toolkit","time":"2026-07-15T10:35:05.000Z","subject":"websearch","data":{"ref":"websearch","name":"opentool-server-websearch","id":"tool-...","status":"running","scope":"tool","reason":"recovered","server":{"namespace":"local","name":"opentool-server-websearch","version":"1.2.0"}}}

```

可用性事件只在状态发生变化时推送，相同状态的重复检查不会产生重复事件。事件中的
`id` 是 register 或 `toolkit.provision.succeeded` 返回的具体 OpenTool 实例 ID。

如果 App 尚未建立订阅，AppKit 事件会先暂存，并在 `welcome` 后立即补发。对于
register 返回 `starting` 的声明，App 应以 `toolkit.provision.succeeded` 作为工具
正式可调用的时点；收到 `toolkit.tool.unavailable` 后停止使用该 tool，直到收到
`toolkit.tool.available`。`app.command.requested` 类型预留给未来发送到 App 的指令。

如果 token 缺失或无效，直接返回 `401`。

## AuthKit

AuthKit 为第三方应用提供 OAuth 风格的授权服务。它允许外部 App 发起用户授权请求、
通过授权码交换 access token，以及获取 AgentOS 用户信息。

除 `GET /authkit/userinfo` 外，所有端点都需要 AppKit 签发的 Bearer token
（`POST /appkit/register`）。`GET /authkit/userinfo` 需要通过授权流程获取的
AuthKit access token。

### 授权流程

1. App 调用 `POST /authkit/authorize` 创建授权请求。
2. 如果 App 此前已被授权，响应为 `200`，并包含 `authCode`。
   否则响应为 `202`，`status` 为 `"pending"`。
3. 对于待处理请求，轮询 `GET /authkit/authorize/<requestId>/status`，
   直到 `status` 变为 `granted`（包含 `authCode`）、`denied` 或 `timeout`。
4. 通过 `POST /authkit/token` 将 `authCode` 交换为 access token。
5. 使用 access token 调用 `GET /authkit/userinfo` 获取用户信息。
6. 通过 `POST /authkit/revoke` 吊销授权。

待处理请求 3 分钟后过期。

### Schema（数据结构）

#### AuthRequestResponse

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `requestId` | `string` | 是 | 授权请求 ID。 |
| `status` | `string` | 是 | `pending`、`granted`、`denied` 或 `timeout`。 |
| `authCode` | `string` | 否 | 当 `status` 为 `granted` 时返回。 |

#### TokenResponse

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `accessToken` | `string` | 是 | AuthKit access token（前缀 `akt-`）。 |
| `userId` | `string` | 否 | 稳定的按 App 隔离的用户 ID（SHA-256 派生）。 |
| `userInfo` | `object` | 是 | 用户信息对象。 |
| `userInfo.name` | `string` | 是 | 用户显示名称。 |
| `userInfo.avatarUrl` | `string` | 是 | 用户头像 URL（可能为空）。 |

#### UserInfo

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `userId` | `string` | 否 | 稳定的按 App 隔离的用户 ID。 |
| `name` | `string` | 是 | 用户显示名称。 |
| `avatarUrl` | `string` | 是 | 用户头像 URL。 |

### 端点

#### POST /authkit/authorize

发起授权请求。

请求体：

```json
{
  "scopes": ["profile"],
  "appName": "My App"
}
```

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `scopes` | `string[]` | 否 | 请求的权限范围，默认 `["profile"]`。 |
| `appName` | `string` | 否 | 请求方 App 的显示名称。 |

响应：`200 OK`（此前已授权）或 `202 Accepted`（待处理）

```json
{"requestId":"req-1","status":"granted","authCode":"ac-..."}
```

#### GET /authkit/authorize/\<requestId\>/status

轮询待处理授权请求的状态。

响应：`200 OK`（`AuthRequestResponse`）

```json
{"requestId":"req-1","status":"pending"}
```

请求 ID 不存在时返回 `404`。

#### POST /authkit/token

用授权码交换 access token。

请求体：

```json
{"authCode":"ac-..."}
```

响应：`200 OK`（`TokenResponse`）

```json
{
  "accessToken": "akt-...",
  "userId": "a1b2c3...",
  "userInfo": {
    "name": "AgentOS User",
    "avatarUrl": ""
  }
}
```

`authCode` 缺失、无效或过期时返回 `400`。

#### GET /authkit/userinfo

使用 AuthKit access token 获取用户信息。

```http
Authorization: Bearer <akt-...>
```

响应：`200 OK`（`UserInfo`）

```json
{
  "userId": "a1b2c3...",
  "name": "AgentOS User",
  "avatarUrl": ""
}
```

错误响应：

| 状态码 | 错误码 | 说明 |
| --- | --- | --- |
| `401` | `invalid_token` | token 不被识别。 |
| `401` | `auth_expired` | AgentOS 用户未登录。 |
| `401` | `token_revoked` | 授权已被吊销。 |
| `404` | `not_found` | 用户未找到。 |

#### POST /authkit/revoke

吊销此前已授予的授权。

请求体：

```json
{"bundleId":"com.demo.app"}
```

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `bundleId` | `string` | 否 | 默认使用 token 自身的 `bundleId`。 |

响应：`200 OK`

```json
{"status":"revoked"}
```

## DiscoveryKit

DiscoveryKit 提供附近 AgentOS 设备发现功能。App 可将自身注册为可被发现的节点、
查询附近设备列表，以及通过 SSE 订阅实时的设备变化事件。

所有端点都需要 AppKit 签发的 Bearer token。

### Schema（数据结构）

#### PeerApp

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `bundleId` | `string` | 否 | App bundle ID。 |
| `userId` | `string` | 否 | 来自 AuthKit 的稳定按 App 隔离的用户 ID。 |
| `username` | `string` | 否 | 用户显示名称。 |
| `appName` | `string` | 否 | App 显示名称。 |
| `avatarUrl` | `string` | 否 | 用户头像 URL。 |

#### PeerDevice

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `deviceId` | `string` | 是 | 设备指纹。 |
| `name` | `string` | 是 | 设备上的用户显示名称。 |
| `avatarUrl` | `string` | 否 | 用户头像 URL。 |
| `deviceName` | `string` | 是 | 设备名称（如主机名）。 |
| `deviceType` | `string` | 是 | 设备类型标识。 |
| `host` | `string` | 是 | 设备 IP 地址。 |
| `port` | `integer` | 是 | 设备服务端口。 |
| `online` | `boolean` | 是 | 设备是否当前可达。 |
| `apps` | `PeerApp[]` | 是 | 设备上已注册的 App 列表。 |

### 端点

#### POST /discoverykit/register

将当前 App 注册为可发现节点。网关会根据 token 的 `bundleId` 从 AuthKit grant
中解析用户身份和 App 名称。

请求体：

```json
{"receivePolicy":"autoAccept"}
```

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `receivePolicy` | `string` | 否 | `autoAccept` 或 `requireConfirm`，默认 `autoAccept`。 |

响应：`200 OK`

```json
{"status":"registered","bundleId":"com.demo.app"}
```

发现服务不可用时返回 `503`。

#### POST /discoverykit/unregister

将当前 App 从发现广播中注销。

响应：`200 OK`

```json
{"status":"unregistered","bundleId":"com.demo.app"}
```

#### GET /discoverykit/peers

列出已发现的附近设备。使用 AppKit token 时，只返回运行相同 `bundleId` 的设备
（App 级扫描）。

响应：`200 OK`（`PeerDevice[]`）

```json
[
  {
    "deviceId": "abc123",
    "name": "AgentOS User",
    "deviceName": "MacBook Pro",
    "deviceType": "desktop",
    "host": "192.168.1.100",
    "port": 8888,
    "online": true,
    "apps": [
      {
        "bundleId": "com.demo.app",
        "userId": "a1b2c3...",
        "username": "AgentOS User"
      }
    ]
  }
]
```

#### GET /discoverykit/peers/stream

通过 SSE 订阅实时的设备变化事件。

响应：`200 OK`，`text/event-stream`

事件类型：

```text
event: peer.joined
data: {"type":"joined","device":{...}}

event: peer.left
data: {"type":"left","device":{...}}

event: peer.updated
data: {"type":"updated","device":{...}}
```

事件类型包括：`joined`、`left`、`updated`。

#### GET /discoverykit/self

获取当前设备自身的信息，结构与 `PeerDevice` 相同，额外包含状态字段。

响应：`200 OK`

```json
{
  "deviceId": "self-device-id",
  "name": "AgentOS User",
  "deviceName": "MacBook Pro",
  "deviceType": "desktop",
  "host": "192.168.1.50",
  "port": 8888,
  "online": true,
  "apps": [],
  "nearbyTransferEnabled": true,
  "registered": true
}
```

## TransferKit

TransferKit 提供 AgentOS 设备之间的跨设备文件传输功能。它负责发送文件、跟踪传输
进度、管理接收策略以及持久化传输历史记录。

所有端点都需要 AppKit 签发的 Bearer token。

### Schema（数据结构）

#### TransferFileInfo

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `fileName` | `string` | 是 | 文件名。 |
| `size` | `integer` | 是 | 文件大小（字节）。 |
| `filePath` | `string` | 是 | 发送设备上的绝对路径。 |
| `mimeType` | `string` | 否 | MIME 类型。 |

#### TransferSession

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `transferId` | `string` | 是 | 传输会话 ID。 |
| `state` | `string` | 是 | `pending`、`preparing`、`transferring`、`completed`、`failed` 或 `cancelled`。 |
| `progress` | `number` | 是 | 总体进度 0.0–1.0。 |
| `targetDeviceId` | `string` | 是 | 目标设备指纹。 |
| `bundleId` | `string` | 是 | 发送方 App bundle ID。 |
| `userId` | `string` | 否 | 发送方用户 ID。 |
| `targetBundleId` | `string` | 否 | 目标 App bundle ID。 |
| `files` | `TransferFileInfo[]` | 是 | 正在传输的文件列表。 |
| `errorMessage` | `string` | 否 | `state` 为 `failed` 时的错误详情。 |

#### IncomingTransferEvent

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `transferId` | `string` | 是 | 传输会话 ID。 |
| `fromDeviceId` | `string` | 是 | 发送方设备指纹。 |
| `fromName` | `string` | 是 | 发送方显示名称。 |
| `sourceBundleId` | `string` | 是 | 发送方 App bundle ID。 |
| `targetBundleId` | `string` | 否 | 目标 App bundle ID。 |
| `autoAccepted` | `boolean` | 是 | 是否被自动接受。 |
| `files` | `ReceivedFileInfo[]` | 是 | 接收到的文件详情。 |

#### ReceivedFileInfo

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `fileName` | `string` | 是 | 文件名。 |
| `size` | `integer` | 是 | 文件大小（字节）。 |
| `savedPath` | `string` | 是 | 文件保存的绝对路径。 |
| `mimeType` | `string` | 否 | MIME 类型。 |

#### TransferHistoryRecord

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `id` | `string` | 是 | 记录 ID。 |
| `direction` | `string` | 是 | `send` 或 `receive`。 |
| `peerDeviceId` | `string` | 是 | 对方设备指纹。 |
| `peerName` | `string` | 是 | 对方显示名称。 |
| `peerAvatarUrl` | `string` | 否 | 对方头像 URL。 |
| `files` | `TransferHistoryFile[]` | 是 | 传输的文件列表。 |
| `totalSize` | `integer` | 是 | 总大小（字节）。 |
| `state` | `string` | 是 | 最终传输状态。 |
| `timestamp` | `string` | 是 | ISO 时间。 |
| `savedDir` | `string` | 否 | 接收文件保存的目录。 |

#### TransferHistoryFile

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `fileName` | `string` | 是 | 文件名。 |
| `size` | `integer` | 是 | 文件大小（字节）。 |
| `filePath` | `string` | 否 | 文件路径。 |

### 端点

#### POST /transferkit/send

向目标设备发送文件。文件路径会按 App 的沙箱数据目录进行校验。

请求体：

```json
{
  "targetDeviceId": "abc123",
  "targetBundleId": "com.demo.app",
  "files": [
    {
      "fileName": "report.pdf",
      "size": 1048576,
      "filePath": "/data/com.demo.app/files/report.pdf",
      "mimeType": "application/pdf"
    }
  ]
}
```

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `targetDeviceId` | `string` | 是 | 目标设备指纹。 |
| `targetBundleId` | `string` | 否 | 目标 App bundle ID，用于 App 级传输。 |
| `files` | `TransferFileInfo[]` | 是 | 要发送的文件列表（非空）。 |

响应：`200 OK`（`TransferSession`）

```json
{
  "transferId": "tf-1",
  "state": "preparing",
  "progress": 0.0,
  "targetDeviceId": "abc123",
  "bundleId": "com.demo.app",
  "files": [
    {"fileName": "report.pdf", "size": 1048576, "filePath": "/data/com.demo.app/files/report.pdf", "mimeType": "application/pdf"}
  ]
}
```

附近传输不可用时返回 `503`。目标设备不可达时返回 `502`。

#### GET /transferkit/transfers

列出当前 App 的活跃传输。

响应：`200 OK`（`TransferSession[]`）

#### GET /transferkit/transfers/\<transferId\>/status

获取指定传输的状态。

响应：`200 OK`（`TransferSession`）

传输未找到时返回 `404`。

#### GET /transferkit/transfers/\<transferId\>/stream

通过 SSE 订阅传输的实时进度更新。

响应：`200 OK`，`text/event-stream`

```text
data: {"transferId":"tf-1","state":"transferring","progress":0.5,...}

data: {"transferId":"tf-1","state":"completed","progress":1.0,...}
```

传输达到 `completed` 或 `failed` 状态时流自动关闭。每 15 秒发送一条
keep-alive 注释。

#### POST /transferkit/transfers/\<transferId\>/cancel

取消进行中的传输。

响应：`200 OK`

```json
{"status":"cancelled"}
```

传输已完成或已取消时返回 `400`。

#### POST /transferkit/transfers/\<transferId\>/respond

接受或拒绝收到的传输请求（配合 `requireConfirm` 策略使用）。

请求体：

```json
{"accept": true}
```

响应：`200 OK`

```json
{"status":"accepted"}
```

传输未找到或已响应时返回 `404`。

#### GET /transferkit/receive/stream

通过 SSE 订阅文件接收事件。事件按当前 App 的 `bundleId` 过滤。

响应：`200 OK`，`text/event-stream`

```text
event: file.received
data: {"transferId":"tf-2","fromDeviceId":"def456","fromName":"Other Device","sourceBundleId":"com.demo.app","autoAccepted":true,"files":[{"fileName":"photo.jpg","size":2097152,"savedPath":"/received/photo.jpg"}]}
```

每 15 秒发送一条 keep-alive 注释。

#### PUT /transferkit/receive/policy

设置当前 App 的文件接收策略。

请求体：

```json
{"policy":"requireConfirm"}
```

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `policy` | `string` | 是 | `autoAccept` 或 `requireConfirm`。 |

响应：`200 OK`

```json
{"policy":"requireConfirm","bundleId":"com.demo.app"}
```

#### GET /transferkit/receive/policy

获取当前文件接收策略。

响应：`200 OK`

```json
{"policy":"autoAccept","bundleId":"com.demo.app"}
```

#### GET /transferkit/history

获取传输历史记录。

Query：

| 字段 | 类型 | 必填 |
| --- | --- | --- |
| `deviceId` | `string` | 否 |
| `userId` | `string` | 否 |

响应：`200 OK`（`TransferHistoryRecord[]`）

#### DELETE /transferkit/history/\<recordId\>

删除单条历史记录。

Query：

| 字段 | 类型 | 必填 |
| --- | --- | --- |
| `deviceId` | `string` | 否 |
| `userId` | `string` | 否 |

响应：`200 OK`

```json
{"status":"deleted"}
```

记录未找到时返回 `404`。

#### DELETE /transferkit/history

清空指定范围的所有历史记录。

Query：

| 字段 | 类型 | 必填 |
| --- | --- | --- |
| `deviceId` | `string` | 否 |
| `userId` | `string` | 否 |

响应：`200 OK`

```json
{"status":"cleared"}
```

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
    "/authkit/*": "AuthKit API（OAuth 风格授权，需要 Token）",
    "/discoverykit/*": "DiscoveryKit API（附近设备发现，需要 Token）",
    "/transferkit/*": "TransferKit API（跨设备文件传输，需要 Token）",
    "/toolkit/*": "ToolKit API（需要 Token）",
    "/modelkit/chat/*": "文本/视觉生成",
    "/modelkit/embedding/*": "文本嵌入",
    "/modelkit/asr/*": "语音转文本",
    "/modelkit/tts/*": "文本转语音"
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
  "serverId": "srv-1",
  "server": {
    "namespace": "demo",
    "name": "demo",
    "version": "1.0.0"
  }
}
```

`status` 通常为 `running` 或 `notRunning`。`serverId` 和 `server` 均可能不
存在；存在时用于标识创建该工具所使用的来源 Server。

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
    "serverId": "srv-1",
    "server": {
      "namespace": "demo",
      "name": "demo",
      "version": "1.0.0"
    }
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

## ModelKit（代理模型服务）

ModelKit 是面向任务的模型能力网关，用于直接访问模型能力。需要 agent、
session、工具调用或多步骤编排时使用 AgentKit；只需要直接调用某类模型能力时使用
ModelKit。

ModelKit 暴露稳定的任务路由，并将请求转发到对应的本地或远程模型后端。请求体、
query 参数和大多数 headers 会透传给上游服务。网关只负责路由、模型解析、指标记录
和兼容性处理。

ModelKit 路由当前不要求 AgentOS Bearer token。对于远程模型，网关会从注册的模型
metadata 或 kernel 默认 LLM 配置中解析 provider 凭证。

### 端点总览

| 端点 | 说明 |
| --- | --- |
| `GET /modelkit/models` | 以 ModelKit 面向任务的 schema 列出可用模型 |
| `ALL /modelkit/chat` | 转发到 chat 默认端点（`/chat/completions`） |
| `ALL /modelkit/chat/*` | 转发到自定义 chat 上游路径 |
| `ALL /modelkit/embedding` | 转发到 embedding 默认端点（`/embeddings`） |
| `ALL /modelkit/embedding/*` | 转发到自定义 embedding 上游路径 |
| `ALL /modelkit/asr` | 转发到 ASR 默认端点（`/audio/transcriptions`） |
| `ALL /modelkit/asr/*` | 转发到自定义 ASR 上游路径 |
| `ALL /modelkit/tts` | 转发到 TTS 默认端点（`/audio/speech`） |
| `ALL /modelkit/tts/*` | 转发到自定义 TTS 上游路径 |

### 常用 Schema

#### ModelInfo

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `id` | `string` | 是 | 网关用于路由和反查的唯一 12 位 hash 风格模型 ID。 |
| `name` | `string` | 是 | 上游模型名称。对于远程模型，网关可能会在转发前将请求体中的 `model` 从 `id` 改写为该值。 |
| `alias` | `string` | 是 | 便于展示的人类可读模型别名。 |
| `description` | `string` | 是 | 来自 service locator 的模型说明。 |
| `task` | `string` | 是 | `chat`、`embedding`、`asr` 或 `tts`。 |
| `input` | `string[]` | 是 | 输入模态，例如 `text`、`image` 或 `audio`。 |
| `output` | `string[]` | 是 | 输出模态，例如 `text` 或 `audio`。 |
| `capabilities` | `ModelCapabilities` | 是 | 能力标记。 |
| `contextWindowSize` | `number` | 否 | 底层模型 metadata 提供时返回上下文窗口大小。 |
| `isRemote` | `boolean` | 是 | 模型是否通过远程 provider route 提供。 |
| `isCustom` | `boolean` | 是 | 模型是否为自定义/用户定义模型。 |

#### ModelCapabilities

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `vision` | `boolean` | 是 | chat 模型是否接受图像输入。视觉语言模型使用 `/modelkit/chat`，没有单独的 vision task route。 |
| `tool_call` | `boolean` | 是 | 是否支持工具/函数调用。 |
| `stream` | `boolean` | 是 | 是否支持流式响应。 |
| `reasoning` | `boolean` | 是 | 模型 metadata 是否声明支持 reasoning 输出。 |

#### 通用请求字段

ModelKit 转发上游模型服务协议。对于 OpenAI-compatible 后端，常用字段如下：

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `model` | `string` | 通常必填 | 模型标识。建议优先使用 `GET /modelkit/models` 返回的唯一 `id`；为兼容旧调用，网关也接受可解析的模型 `name`。对于 `/modelkit/chat`，如果省略，网关可能使用 kernel 默认 LLM 配置。 |
| `stream` | `boolean` | 否 | 为 true 时，chat 响应以 `text/event-stream` 流式返回。带有 `Accept: text/event-stream` 的请求也会被视为流式请求。 |
| `base_url` | `string` | 否 | 可选的 base URL 提示，用于指标记录。实际路由仍通过模型注册表和 service locator 解析。 |

### 路由契约

ModelKit 的路径前缀用于选择任务。任务根路径会映射到默认上游端点；子路径会作为显式
上游路径转发。

| 对外路径 | 任务 | 默认上游路径 | 典型 Content Type | 典型响应 |
| --- | --- | --- | --- | --- |
| `/modelkit/chat` | `chat` | `/chat/completions` | `application/json` | JSON chat completion 或 SSE stream |
| `/modelkit/embedding` | `embedding` | `/embeddings` | `application/json` | JSON embedding response |
| `/modelkit/asr` | `asr` | `/audio/transcriptions` | `multipart/form-data` | JSON 或 text transcription |
| `/modelkit/tts` | `tts` | `/audio/speech` | `application/json` | 音频 bytes 或 provider 响应 |

示例：

| 请求路径 | 转发行为 |
| --- | --- |
| `POST /modelkit/chat` | 使用 chat 任务默认端点 |
| `POST /modelkit/chat/v1/chat/completions` | 使用该显式路径转发到 chat 后端 |
| `GET /modelkit/tts/audio/voices` | 转发到 TTS 后端的声音列表端点 |

对于 chat 响应，ModelKit 会在需要时规范化 OpenAI-compatible JSON 和 SSE 细节，包括
`data: ` SSE framing、`reasoning_content` 和 tool-call delta 兼容性。对于 TTS
声音列表响应，voice key 中的文件系统路径可能会被简化为 basename。

### 端点

#### GET /modelkit/models

以基于任务的 wire schema 列出可用模型。每个条目包含 `task`
（`chat` / `embedding` / `asr` / `tts`）、`input` / `output` 模态，以及
`capabilities` 块（`vision`、`tool_call`、`stream`、`reasoning`）。
其中 `id` 是网关用于路由和反查的唯一 12 位 hash 风格模型标识。`name` 和
`alias` 应视为展示或 provider metadata，而不是规范 ID。

响应：`200 OK`（`ModelInfo[]`）

```json
[
  {
    "id": "7f3a91c2de4b",
    "name": "Qwen 3 8B",
    "alias": "qwen3-8b",
    "description": "文本生成模型",
    "task": "chat",
    "input": ["text"],
    "output": ["text"],
    "capabilities": {
      "vision": false,
      "tool_call": true,
      "stream": true,
      "reasoning": true
    },
    "contextWindowSize": 8192,
    "isRemote": false,
    "isCustom": false
  }
]
```

#### ALL /modelkit/chat

将 chat/text-generation 或视觉语言请求转发到解析出的 chat 后端。根路径映射到上游
`/chat/completions` 端点。视觉语言模型通过选择 `capabilities.vision` 为 `true`
的 chat 模型来使用。

常见 JSON 请求体：

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `model` | `string` | 否 | 来自 `/modelkit/models` 的稳定模型 `id`。如果省略，网关可能使用 kernel 默认 LLM 配置。 |
| `messages` | `object[]` | 是 | OpenAI-compatible chat messages。对于视觉模型，message content 可包含上游后端支持的文本和图像 part。 |
| `stream` | `boolean` | 否 | 在模型支持时以 SSE 流式返回。 |
| `tools` | `object[]` | 否 | 模型支持 tool calling 时使用的 OpenAI-compatible tool definitions。 |

请求示例：

```bash
curl -X POST http://localhost:8888/modelkit/chat \
  -H 'Content-Type: application/json' \
  -d '{
    "model": "7f3a91c2de4b",
    "messages": [
      {"role": "user", "content": "写一句产品标语。"}
    ]
  }'
```

响应示例：

```json
{
  "id": "chatcmpl-001",
  "object": "chat.completion",
  "model": "Qwen 3 8B",
  "choices": [
    {
      "index": 0,
      "message": {
        "role": "assistant",
        "content": "AgentOS 将本地与远程 AI 能力整合为一个可编程工作空间。"
      },
      "finish_reason": "stop"
    }
  ],
  "usage": {
    "prompt_tokens": 18,
    "completion_tokens": 14,
    "total_tokens": 32
  }
}
```

流式请求示例：

```bash
curl -N -X POST http://localhost:8888/modelkit/chat \
  -H 'Content-Type: application/json' \
  -H 'Accept: text/event-stream' \
  -d '{
    "model": "7f3a91c2de4b",
    "stream": true,
    "messages": [
      {"role": "user", "content": "列出两个上线风险。"}
    ]
  }'
```

流式响应：`text/event-stream`

```text
data: {"choices":[{"index":0,"delta":{"role":"assistant","content":""}}]}

data: {"choices":[{"index":0,"delta":{"content":"依赖服务就绪情况"}}]}

data: [DONE]
```

#### ALL /modelkit/embedding

将 embedding 请求转发到解析出的 embedding 后端。根路径映射到上游 `/embeddings`
端点。

常见 JSON 请求体：

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `model` | `string` | 是 | 来自 `/modelkit/models` 的稳定 embedding 模型 `id`。 |
| `input` | `string` 或 `string[]` | 是 | 需要向量化的文本。 |

请求示例：

```bash
curl -X POST http://localhost:8888/modelkit/embedding \
  -H 'Content-Type: application/json' \
  -d '{
    "model": "bge-large-zh-v1.5-q8_0",
    "input": "AgentOS model gateway"
  }'
```

响应示例：

```json
{
  "object": "list",
  "data": [
    {
      "object": "embedding",
      "index": 0,
      "embedding": [0.0123, -0.0456, 0.0789]
    }
  ],
  "model": "bge-large-zh-v1.5-q8_0"
}
```

#### ALL /modelkit/asr

将 speech-to-text 请求转发到解析出的 ASR 后端。根路径映射到上游
`/audio/transcriptions` 端点。

常见 multipart 请求字段：

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `model` | `string` | 是 | 来自 `/modelkit/models` 的稳定 ASR 模型 `id`。 |
| `file` | `file` | 是 | 需要转写的音频文件。 |
| `language` | `string` | 否 | 上游后端支持时使用的语言提示。 |
| `response_format` | `string` | 否 | provider-specific 响应格式，例如 `json` 或 `text`。 |

请求示例：

```bash
curl -X POST http://localhost:8888/modelkit/asr \
  -F model=whisper-local \
  -F file=@sample.wav \
  -F response_format=json
```

响应示例：

```json
{
  "text": "欢迎使用 AgentOS。"
}
```

#### ALL /modelkit/tts

将 text-to-speech 请求转发到解析出的 TTS 后端。根路径映射到上游
`/audio/speech` 端点。

常见 JSON 请求体：

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `model` | `string` | 是 | 来自 `/modelkit/models` 的稳定 TTS 模型 `id`。 |
| `input` | `string` | 是 | 需要合成的文本。 |
| `voice` | `string` | 否 | 上游后端支持的声音名称。 |
| `response_format` | `string` | 否 | 上游后端支持时指定音频格式。 |

请求示例：

```bash
curl -X POST http://localhost:8888/modelkit/tts \
  -H 'Content-Type: application/json' \
  -o speech.wav \
  -d '{
    "model": "qwen-tts",
    "input": "欢迎使用 AgentOS。",
    "voice": "default",
    "response_format": "wav"
  }'
```

响应：使用上游 content type 的音频 bytes，或 provider-specific JSON 响应。

声音列表示例：

```bash
curl http://localhost:8888/modelkit/tts/audio/voices
```

### 错误响应

所选 task/model 没有可用本地服务或远程 route 时返回 `503`：

```json
{
  "error": "Model \"qwen3-8b\" unavailable",
  "service": "llm_chat"
}
```

后端连接错误时返回 `502`：

```json
{
  "error": "Backend service unavailable",
  "service": "llm_chat",
  "message": "Connection refused"
}
```

如果上游返回上下文窗口超限错误，ModelKit 会将常见 provider-specific 错误规范化为
`400`：

```json
{
  "error": {
    "message": "This model's maximum context length is 8192 tokens. However, your messages resulted in 12000 tokens. Please reduce the length of the messages.",
    "type": "context_length_exceeded",
    "code": "context_length_exceeded",
    "n_prompt_tokens": 12000,
    "n_ctx": 8192
  }
}
```
