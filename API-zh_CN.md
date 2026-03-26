# AgentOS HTTP API

基础地址：`http://<host>:<port>`（默认端口：`20261`）。

## 鉴权

所有 `/agentkit/*`、`/cronkit/*` 路由以及 `GET /appkit/subscribe`
都需要 Bearer token。

对于 `/cronkit/*`，Bearer token 必须来自 `POST /appkit/register`。
Cron 任务权限按该 token 解析出的 app 身份控制：
同一 `appGroupId` 可共享读取，写操作仍只允许 owner `bundleId`。

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

#### POST /agentkit/chat/simple

Query:

| 字段 | 类型 | 必填 |
| --- | --- | --- |
| `sessionId` | `string` | 是 |

请求体：`UserTask`

响应：`200 OK`（`AgentMessage`）

#### GET /agentkit/history

Query:

| 字段 | 类型 | 必填 |
| --- | --- | --- |
| `sessionId` | `string` | 是 |

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
- 否则会按兼容逻辑转发到 LiteAgent 的 `/callback`。

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

#### POST /cronkit/task/update

请求体：带必填 `cronId` 的局部更新对象。
如果提供 `spec`，必须使用与创建时相同的 `AgentCronSpec` 结构。

响应：`200 OK`（`CronTask`）

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

如果 kernel 未配置 cron 模块，CronKit 可能返回 `503`。

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
  "baseUrl": "http://localhost:20261",
  "endpoints": {
    "/version": "网关版本",
    "/agentkit/*": "AgentKit API（智能体服务，需要 Token）",
    "/appkit/*": "AppKit API（应用注册/订阅）",
    "/toolkit/*": "ToolKit API（OpenTool）",
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

## ToolKit（代理 OpenTool 服务）

ToolKit 会透明代理所有请求到运行在端口 `19627` 的 OpenTool 服务
（可通过 ServiceLocator 配置）。

### 端点

#### ALL /toolkit/*

所有 `/toolkit/*` 请求会转发到 OpenTool 后端服务。
请求/响应体、状态码、请求头和查询参数会原样透传。
后端不可用时返回 `503`：

```json
{"error": "OpenTool 服务不可用"}
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

#### ALL /llmkit/vision/*

代理到图文理解服务。

#### ALL /llmkit/embedding/*

代理到文本嵌入服务。

#### ALL /llmkit/tts/*

代理到文本转语音服务。

#### ALL /llmkit/asr/*

代理到语音转文本服务。

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
