# AgentOS HTTP API

基础地址：`http://<host>:<port>`（默认端口：`8888`）。

## 鉴权

所有 `/agentkit/*`、`/cronkit/*`、`/ragkit/*`、`/harnesskit/*`、`/authkit/*`、
`/discoverykit/*`、`/transferkit/*`、`/notifykit/*` 路由以及
`GET /appkit/subscribe` 都需要 Bearer token。

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

对于 `/harnesskit/*`，Bearer token 必须来自 `POST /appkit/register`。
AgentOS 只运行一个宿主级 Harness runtime。内置 Harness 与声明 `harnessKit` 且健康检查通过的
安装型进程 App 都由 Gateway 转发到该 runtime；Gateway 会用 sidecar 专属 token 替换 AppKit
token，并将已验证的 AppKit `bundleId` 作为 actor 身份转发。App 只调用 Gateway API，不需要
提供 Harness HTTP 服务。Gateway 在共享 runtime 和数据库内按 `bundleId` 为外部 App 隔离线程、
运行记录及事件访问；内置 Harness 与侧边栏沿用默认命名空间，因此继续共享原有记录。只有内置
Harness App 能访问 runtime 控制和全局运维快照；切换引擎会影响所有接入 App 的后续请求。
停止或退出时，AppDaemon 只撤销该 App 的 HarnessKit 访问权限，不会停止共享 runtime。
升级前没有记录 App 归属的历史线程会保留在默认空间，不会自动归属到某个外部 App。

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
| `modelId` | `string` | 否 | AgentKit 专有的模型注册表 ID。`/agentkit/initSession`、`/agentkit/initSimple`、`/agentkit/chat` 和 `/agentkit/chat/simple` 均支持。传入后，AgentKit 会解析为具体的 `llmConfig`，将解析出的模型名称写入 `model`，并在可用时补齐 `baseUrl`、`apiKey`、`provider`、`adapter` 和 `contextWindowSize`；它可以替代直接传入的 `baseUrl`/`model` 字段。 |
| `provider` | `string` | 否 | LLM provider，支持 `openai` 和 `lite_oneapi`；省略时使用 LiteAgent 默认 provider。 |
| `baseUrl` | `string` | 是 | LLM 接口 base URL。 |
| `apiKey` | `string` | 是 | LLM API key。 |
| `model` | `string` | 是 | 模型名称。 |
| `adapter` | `string` | 否 | `provider=lite_oneapi` 时使用的上游协议/厂商适配器，例如 `openai`、`deepseek`、`glm`、`kimi`、`mimo`、`minimax` 或 `qwen`。 |
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

#### Capability

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `llmConfig` | `LLMConfig` | 否 | LLM 配置。缺省时网关可能从 kernel 注入可用配置。 |
| `systemPrompt` | `string` | 是 | 系统提示词。 |
| `skills` | `string[]` | 否 | 转发给 LiteAgent 的完整 Agent Skills Markdown 文档列表，每项应遵循 `SKILL.md` 格式。 |
| `openSpecList` | `OpenSpec[]` | 否 | 工具规范列表。 |
| `callbackOpenTool` | `CallbackOpenTool` | 否 | 客户端回调工具。 |
| `subAgentList` | `Agent[]` | 否 | 内联子 Agent 列表。每项可递归包含 `Capability`；运行时 session ID 由服务端生成。 |
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
| `skills` | `string[]` | 否 | 转发给 LiteAgent 的完整 Agent Skills Markdown 文档列表，每项应遵循 `SKILL.md` 格式。 |

#### Agent

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `name` | `string` | 是 | 内联 Agent 名称。 |
| `capability` | `Capability` | 是 | 内联 Agent 能力配置。 |

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
| `originalTaskId` | `string` | 是 | 根任务 ID。对于旧版 LiteAgent 响应，该字段回退为 `taskId`。 |
| `parentTaskId` | `string` | 否 | 父 task ID。 |
| `taskId` | `string` | 是 | Task ID。 |
| `role` | `string` | 是 | `system`、`user`、`agent`、`llm`、`tool`。 |
| `to` | `string` | 是 | `user`、`agent`、`llm`、`tool`、`client`。 |
| `type` | `string` | 是 | `text`、`imageUrl`、`dispatch`、`contentList`、`functionCall`、`toolCalls`、`toolReturn`、`taskStatus`、`reasoning`、`reasoningContent`、`planning`。 |
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
| `parentTaskId` | `string` | 否 | 父 task ID。 |
| `taskId` | `string` | 是 | Task ID。 |
| `role` | `string` | 是 | `system`、`user`、`agent`、`llm`、`tool`。 |
| `to` | `string` | 是 | `user`、`agent`、`llm`、`tool`、`client`。 |
| `type` | `string` | 是 | `text`、`imageUrl`、`dispatch`、`contentList`、`functionCall`、`toolCalls`、`toolReturn`、`taskStatus`、`reasoning`、`reasoningContent`、`planning`。 |
| `part` | `any` | 是 | 分片内容，随 `type` 变化。 |
| `createTime` | `string` | 是 | ISO 时间。 |

### 端点

#### GET /agentkit/version

响应：`200 OK`

```
{"version":"<string>"}
```

#### POST /agentkit/initSession

请求体：`Capability`

说明：
- 支持 `Capability.skills`，并会原样转发给 LiteAgent SDK。`skills` 的每一项都应是完整的 Agent Skills Markdown 文档。
- 每个 skill 文档的规范来源为 [agentskills.io/specification](https://agentskills.io/specification)，重点遵循其中 `SKILL.md` 的格式要求：YAML frontmatter 加 Markdown 正文。
- 也支持 `Capability.llmConfig.modelId`。AgentKit 会先用 `modelId` 在内部模型注册表中做反查（`modelId` 取 `GET /modelkit/models` 返回的 `id`），再展开成 LiteAgent 可用的具体 `llmConfig`。其中解析出的模型名会写入 `llmConfig.model`；同时网关还会在可用时补齐 `baseUrl`、`apiKey`、`provider`、`adapter`、`contextWindowSize` 等字段。
- 网关使用 `callbackOpenTool.timeout` 等待外部 function call 回调。未提供或值非法时使用兼容默认值 300 秒。

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

请求体：`UserTask`。

`llmConfig` 为可选字段。传入后只覆盖本次请求使用的 LLM 配置，不会修改
当前 session 的默认配置。直接覆盖时请传入完整的 LiteAgent 兼容配置，而不是
只传需要修改的字段。AgentKit 还支持网关扩展字段 `llmConfig.modelId`，会通过
内部模型注册表进行解析。

本次请求的 `llmConfig` 字段如下：

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `llmConfig.modelId` | `string` | 否 | AgentKit 专有的模型注册表 ID。传入后，AgentKit 会将其解析为具体模型配置，并在可用时补齐 `baseUrl`、`model`、`apiKey`、`provider`、`adapter` 和 `contextWindowSize`。它可以替代直接传入的 `baseUrl`/`model` 字段，同时仍可传入本次请求的调节字段。 |
| `llmConfig.provider` | `string` | 否 | `openai` 或 `lite_oneapi`。 |
| `llmConfig.baseUrl` | `string` | 是 | LLM 厂商 API 入口。 |
| `llmConfig.apiKey` | `string` | 是 | LLM 厂商 API Key。 |
| `llmConfig.model` | `string` | 是 | 本次请求使用的模型名称。 |
| `llmConfig.adapter` | `string` | 否 | `provider=lite_oneapi` 时使用的上游协议/厂商适配器。 |
| `llmConfig.temperature` | `number` | 否 | 温度值，LiteAgent 默认 `0`。 |
| `llmConfig.maxTokens` | `number` | 否 | 最大 token 数，LiteAgent 默认 `4096`。 |
| `llmConfig.contextWindowSize` | `number` | 否 | 上下文窗口大小。 |
| `llmConfig.topP` | `number` | 否 | 概率抽样的 p 值，LiteAgent 默认 `1`。 |
| `llmConfig.supportsToolCall` | `boolean` | 否 | 是否支持工具调用，LiteAgent 默认 `true`。 |
| `llmConfig.supportsReasoning` | `boolean` | 否 | 是否支持推理，LiteAgent 默认 `false`。 |

响应：`200 OK`，`text/event-stream`

事件类型：
- `message`：`AgentMessage`
- `chunk`：`AgentMessageChunk`
- `functionCall`：`{"sessionId":"<string>","functionCall":FunctionCall}`。对于支持流式回调的函数调用，网关还会附带 `"stream":true`。

示例请求：

```json
{
  "content": [
    {"type": "text", "message": "Summarize this repository."}
  ],
  "isChunk": true,
  "llmConfig": {
    "provider": "lite_oneapi",
    "baseUrl": "https://your-oneapi-server/v1",
    "apiKey": "sk-xxxxxxxxxx",
    "model": "qwen-plus",
    "adapter": "qwen"
  }
}
```

#### POST /agentkit/chat/simple

Query:

| 字段 | 类型 | 必填 |
| --- | --- | --- |
| `sessionId` | `string` | 是 |

请求体：`UserTask`。

`llmConfig` 与 `/agentkit/chat` 具有相同的“仅本次请求覆盖”语义：只覆盖本次
请求，不更新 session 默认配置。直接覆盖时请传入完整配置；同时支持网关扩展的
`llmConfig.modelId` 反查。

本次请求的 `llmConfig` 字段与 `/agentkit/chat` 相同：`provider`、`baseUrl`、
`modelId`、`apiKey`、`model`、`adapter`、`temperature`、`maxTokens`、
`contextWindowSize`、`topP`、`supportsToolCall` 和 `supportsReasoning`。

示例请求：

```json
{
  "content": [
    {"type": "text", "message": "Give me a random number."}
  ],
  "llmConfig": {
    "provider": "lite_oneapi",
    "baseUrl": "https://your-oneapi-server/v1",
    "apiKey": "sk-xxxxxxxxxx",
    "model": "qwen-plus",
    "adapter": "qwen"
  }
}
```

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

### LiteAgent 兼容边界

AgentKit 暴露了上面列出的 LiteAgent 兼容端点。LiteAgent 服务端独有的
`/presetOpenSpecList` 和 `/session/subscribe` 当前不会通过 `/agentkit` 代理；
需要时请直接访问 LiteAgent 服务。

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
| `sessionId` | `string` | 否 | 可选 LiteAgent session ID；定时执行时复用该 session。 |
| `timezone` | `string` | 否 | 可选 IANA 任务时区；调度按该时区计算，计划时间以 UTC 序列化。 |
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
        "repo": "local",
        "name": "opentool-server-websearch",
        "version": "1.2.0",
        "tag": "1.2.0"
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

OpenTool V2 客户端应使用 `namespace` 和 `version`。为兼容已经发布且编译了旧版
SDK 的 App，AppKit 会在注册响应和订阅事件的 `server` 对象中同时返回值相同的
弃用别名 `repo` 和 `tag`。这些别名仅属于 AppKit 响应兼容层，daemon 契约仍保持
纯 V2。

### GET /appkit/subscribe

需要 Bearer token（来自 `/appkit/register`）。

订阅时可以选择 ToolKit 生命周期通知：

```http
GET /appkit/subscribe?toolEvents=all
GET /appkit/subscribe?toolEvents=selected&toolIds=tool-a,tool-b
```

`toolEvents=all` 监听 ToolKit 当前可见的 OpenTool daemon 和 App 自有工具；
`toolEvents=selected` 只监听 `toolIds` 中逗号分隔的 ID（也可以重复传入 `toolId`）。
省略该参数时，SSE 保持原有的、发送给当前 App 的定向事件，不监听全局工具目录。订阅范围
绑定到当前 SSE 连接，断线重连后需要重新订阅。断线期间不会缓存全局可用性通知。

至少有一个带筛选条件的订阅连接时，Server 每五秒检查一次目录，并在状态变化时通过
`appEvent` 推送 `source: "toolkit"`、类型为 `toolkit.tool.available` 或
`toolkit.tool.unavailable` 的事件。`subject` 是 ToolKit ID；`data` 包含工具描述、当前
`status` 和 `registered`、`recovered`、`stopped` 或 `removed` 等 `reason`。App 可以在建立
连接后调用 `GET /toolkit/list` 初始化当前目录，再用这些事件刷新目录，避免每次事件都接收
全量工具列表。

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

## NotifyKit

NotifyKit 允许 App 将面向用户的事件提交到 AgentOS 通知中心。它只接受事件内容；
App 不能传入优先级、分组 ID、去重 key 或展示策略。

### POST /notifykit/notifications

需要 `POST /appkit/register` 返回的 Bearer token。

请求体：

```json
{
  "eventType": "task.completed",
  "subjectId": "job-123",
  "title": "任务完成",
  "message": "导出文件已准备好。"
}
```

`eventType` 必须是小写的点分名称。平台只会对平台定义的事件名称计算非中性的级别，
并统一执行 App 级别的限流、可见分类数量上限以及重复事件合并。已知分类包括 `auth`、`chat`、
`download`、`model`、`service`、`sync`、`task`、`transfer` 和 `update`；未知或
超出上限的分类会归入 `other`。

带有相同 `subjectId` 的重复事件会合并为一条。没有 subject 的事件在短去重窗口内
内容重复时也会合并。响应中的通知记录和累计次数均由平台生成；`429` 表示该 App
超过了通知速率限制。

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
    "/modelkit/models": "基于任务的模型列表",
    "/modelkit/chat/models": "OpenAI 兼容的 chat 模型列表",
    "/modelkit/chat/*": "文本/视觉生成",
    "/modelkit/embedding/*": "文本嵌入",
    "/modelkit/asr/*": "语音转文本",
    "/modelkit/tts/*": "文本转语音",
    "/modelkit/decision/*": "决策模型（类型化问题，/v1/systemone）",
    "/modelkit/app-models": "应用模型注册 API"
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
| GET | `/toolkit/list` | 列出可调用工具；`all=1` 还会包含已停止的 `opentool-server` 工具。 |
| POST | `/toolkit/{toolId}/call` | 调用工具函数。 |
| POST | `/toolkit/{toolId}/streamCall` | 调用工具函数并通过 SSE 返回结果。 |
| GET | `/toolkit/{toolId}/load` | 返回工具描述和函数 schema。 |

ToolKit 还会将声明 `rpc.discovery: "runtime"`（或使用受支持的旧版
`rpc.systemMethods` 声明）的进程 App 列为 `app:{bundleId}` 工具，但需用户至少启用一个当前 schema 中的函数。请求 `/load` 时会从 App
后端动态获取 schema；未显式 opt-in 的 App 不会为此启动。用户必须先在“设置 → 应用”中启用
单个函数，它才会出现在 `/load` 响应中并允许调用。App 自有工具由 AgentOS 代理，与 OpenTool
Daemon 管理的 `opentool-server` 工具相互独立。
已 opt-in 的 App provider 即使专用后端尚未启动也会出现在列表中；App 条目的
`status: "running"` 表示 ToolKit 路由可按需启动后端。App 条目不含 `host` 和 `port`，因为调用由
AgentOS 代理。
对于 App 工具，ToolKit 会将 `FunctionCall` 请求体（`id`、`name` 和 `arguments`）转换为 App 的
JSON-RPC 请求，并把 JSON-RPC 响应与 SSE 帧转换回 ToolKit 结果格式。App 后端无需实现 AgentOS
`FunctionCall` 请求格式。

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
| `GET /modelkit/chat/models` | 以 OpenAI 兼容格式列出 chat 模型 |
| `GET /modelkit/chat/v1/models` | `/modelkit/chat/models` 的别名 |
| `ALL /modelkit/chat` | 转发到 chat 默认端点（`/chat/completions`） |
| `ALL /modelkit/chat/*` | 转发到自定义 chat 上游路径 |
| `ALL /modelkit/embedding` | 转发到 embedding 默认端点（`/embeddings`） |
| `ALL /modelkit/embedding/*` | 转发到自定义 embedding 上游路径 |
| `ALL /modelkit/asr` | 转发到 ASR 默认端点（`/audio/transcriptions`） |
| `ALL /modelkit/asr/*` | 转发到自定义 ASR 上游路径 |
| `ALL /modelkit/tts` | 转发到 TTS 默认端点（`/audio/speech`） |
| `ALL /modelkit/tts/*` | 转发到自定义 TTS 上游路径 |
| `ALL /modelkit/decision` | 转发到决策模型默认端点（`/systemone`，即上游 `/v1/systemone`） |
| `ALL /modelkit/decision/*` | 转发到自定义决策模型上游路径 |
| `GET /modelkit/app-models` | 列出所有应用注册的模型 |
| `POST /modelkit/app-models` | 第三方应用注册模型 |
| `PUT /modelkit/app-models/<id>` | 更新应用注册的模型 |
| `DELETE /modelkit/app-models/<id>` | 注销应用注册的模型 |
| `POST /modelkit/app-models/<id>/toggle` | 切换应用注册模型的启用/禁用状态 |

### 常用 Schema

#### ModelInfo

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `id` | `string` | 是 | 网关用于路由和反查的模型 ID，在整个列表内唯一。`local` / `platform` 模型是 12 位 hash 风格 ID，`custom` 模型是创建时生成的 ID，`app` 模型是应用注册时由网关生成的 12 位 hashid（例如 `6f78dcce6717`）。详见 [模型 ID 与寻址](#模型-id-与寻址)。 |
| `name` | `string` | 是 | 上游模型名称。对于远程模型，网关可能会在转发前将请求体中的 `model` 从 `id` 改写为该值。 |
| `alias` | `string` | 是 | 便于展示的人类可读模型别名。 |
| `description` | `string` | 是 | 来自 service locator 的模型说明。 |
| `task` | `string` | 是 | `chat`、`embedding`、`asr`、`tts` 或 `decision`（决策模型，llama.cpp `/v1/systemone`）。 |
| `input` | `string[]` | 是 | 输入模态，例如 `text`、`image` 或 `audio`。多模态决策模型（如 Clef）支持 `image`。 |
| `output` | `string[]` | 是 | 输出模态，例如 `text`、`audio` 或 `decisions`（决策模型）。 |
| `capabilities` | `ModelCapabilities` | 是 | 能力标记。 |
| `contextWindowSize` | `number` | 否 | 底层模型 metadata 提供时返回上下文窗口大小。 |
| `isRemote` | `boolean` | 是 | 模型是否通过远程 provider route 提供。 |
| `isCustom` | `boolean` | 是 | 模型是否为自定义/用户定义模型。 |
| `source` | `string` | 是 | 模型来源，互斥取值：`local`、`platform`、`custom`、`app`。使用端应按该字段分组和展示，而不是用 `isRemote` / `isCustom` / `isAppModel` 自行推导分类。详见 [模型来源](#模型来源)。 |
| `isAppModel` | `boolean` | 否 | 通过应用模型注册 API 注册的模型会包含此字段且为 `true`。 |
| `appBundleId` | `string` | 否 | 注册该模型的第三方应用 bundle ID。仅应用注册模型包含此字段。 |
| `appName` | `string` | 否 | 注册该模型的应用显示名称，供模型选择器按应用分组使用。仅应用注册模型（`source` 为 `app`）包含此字段；应用未提供名称时回退为 `appBundleId`。 |

#### 模型来源

`source` 是网关推导出的单一、互斥的分类。它取代了由多个布尔字段隐式组合出的分类——
后者无法区分应用注册模型与平台模型（两者都是 `isRemote: true, isCustom: false`）。

| `source` | 含义 | 推导条件 |
| --- | --- | --- |
| `app` | 第三方应用通过 `/modelkit/app-models` 注册的模型。 | `isAppModel` 为 `true`（优先级最高） |
| `local` | 在本机运行。 | 不是应用模型，且 `isRemote` 为 `false` |
| `custom` | 用户自行配置的远端模型。 | 不是应用模型，`isRemote` 为 `true`，且 `isCustom` 为 `true` |
| `platform` | AgentOS 平台提供的远端模型。 | 其余远端模型 |

`isRemote`、`isCustom`、`isAppModel`、`appBundleId` 等布尔/标识字段保持不变，向后兼容。
运行位置（本机/云端）属于次要信息，不建议混入分组名称。

模型选择器的推荐标签（与 AgentOS 桌面端模型管理保持一致）：`local` → “本地模型”，
`platform` → “平台模型”，`custom` → “自定义模型”，`app` → “应用 · {appName}”
（每个应用一组）。

#### 模型 ID 与寻址

`GET /modelkit/models` 返回的每个 `id` 都可以原样填入请求体的 `model` 字段，网关会精确路由到
这一个模型。不同来源的 `id` 形态如下：

| `source` | `id` 形态 | 说明 |
| --- | --- | --- |
| `local` | 12 位 hex | 由本机运行实例派生。 |
| `platform` | 12 位 hex | 由平台模型的服务端 ID 派生。 |
| `custom` | 创建时生成的 ID | 创建后保持不变。管理 API 创建自定义模型时可省略 `id`，由网关生成；传入的 `id` 不能与任何已有模型冲突。 |
| `app` | 12 位 hex | 注册时由网关生成：`sha256("<bundleId>:<name>")`（`name` 去掉首尾空白）的前 12 位 hex。注册响应会返回它，应用之后用它来维护该模型。同一应用、同一 `name` 总是得到同一个 ID，不同应用即使 `name` 相同，ID 也不同；自定义模型创建时会与所有已有模型做冲突检查。 |

注册应用模型的应用，其 `bundleId` 只允许 `[A-Za-z0-9._-]`（1–128 个字符）；其他 `bundleId`
发起的注册请求返回 `400`。

**解析顺序。** 请求里的 `model` 可以是 `id`，也可以是 `alias` / `name`（用于兼容旧调用方）。
网关按以下顺序查找，命中即停止：

1. 精确匹配 `id`（所有模型，包括应用模型的 hashid）；
2. 第一方模型（`local` / `platform` / `custom`）的 `alias`，然后是 `name`；
3. 应用模型的 `alias`，然后是 `name`。

由此带来的保证：应用无法通过把自己模型的 `alias` / `name` / `id` 设成某个第一方模型的名称
来“劫持”该名称的请求——第一方模型始终优先。同一层级匹配到多个模型时取列表中的第一个，网关
日志会记录一条告警，列出所有候选 `id`。

**建议。** 调用方应使用 `GET /modelkit/models`（或应用注册响应）里的完整 `id`，不要依赖
`alias` / `name`。

**列表去重。** 网关在组装 `GET /modelkit/models` 时会对 `id` 去重：`id` 相同时第一方模型
优先于应用模型，同一层级先出现者保留，被丢弃的一项会记录告警。这是一道兜底，正常情况下
不会触发。

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
| `/modelkit/decision` | `decision` | `/systemone` | `application/json` | JSON `answers`（每题的结果、概率与置信度） |

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
（`chat` / `embedding` / `asr` / `tts` / `decision`）、`input` / `output` 模态，以及
`capabilities` 块（`vision`、`tool_call`、`stream`、`reasoning`）。
其中 `id` 是网关用于路由和反查的唯一模型标识：本地 / 平台模型是 12 位 hash 风格，应用注册模型是
注册时由网关生成的 hashid（见 [模型 ID 与寻址](#模型-id-与寻址)）。`name` 和
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
    "isCustom": false,
    "source": "local"
  },
  {
    "id": "b21d5e08a7c3",
    "name": "Julia-1",
    "alias": "julia-1",
    "description": "决策模型（llama.cpp /v1/systemone）",
    "task": "decision",
    "input": ["text"],
    "output": ["decisions"],
    "capabilities": {
      "vision": false,
      "tool_call": false,
      "stream": false,
      "reasoning": false
    },
    "contextWindowSize": 4096,
    "isRemote": false,
    "isCustom": false,
    "source": "local"
  },
  {
    "id": "c94e07b1d2f6",
    "name": "deepseek-v4-flash",
    "alias": "deepseek-v4-flash-jm",
    "description": "第三方应用注册的对话模型",
    "task": "chat",
    "input": ["text"],
    "output": ["text"],
    "capabilities": {
      "vision": false,
      "tool_call": true,
      "stream": true,
      "reasoning": true
    },
    "isRemote": true,
    "isCustom": false,
    "source": "app",
    "isAppModel": true,
    "appBundleId": "com.example.jmtest",
    "appName": "JMtest App"
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

#### ALL /modelkit/decision

将决策模型（llama.cpp `/v1/systemone`，一次前向返回类型化问题的概率）请求转发到解析出的
决策模型后端。根路径映射到上游 `/v1/systemone` 端点；决策模型不支持 chat / embeddings
端点，也不支持流式输出。

常见 JSON 请求体：

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `model` | `string` | 否 | 来自 `/modelkit/models` 的决策模型 `id` 或名称；省略时使用第一个运行中的决策模型。解析规则见 [模型 ID 与寻址](#模型-id-与寻址)。 |
| `state` | `string` / `object` / `array` | 是 | 待判断的内容；非字符串会被序列化为 JSON 文本。 |
| `questions` | `object` | 是 | `问题 id -> {type, instructions, criteria}`；`type` 为 `choice`、`score` 或 `noul`。 |
| `images` | `string[]` | 否 | 多模态决策模型（如 Clef）可传入 data URL。 |

请求示例：

```bash
curl -X POST http://localhost:8888/modelkit/decision \
  -H 'Content-Type: application/json' \
  -d '{
    "model": "Julia-1",
    "state": "客户留言：我上周的订单被重复扣款，一直没人回复。",
    "questions": {
      "route": {
        "type": "choice",
        "instructions": "这件事应该由哪个团队处理？",
        "criteria": {"billing": "付款、扣费、退款", "shipping": "配送、物流", "technical": "程序错误、登录问题"}
      },
      "angry": {"type": "noul", "instructions": "客户是否在生气？"}
    }
  }'
```

响应：上游 JSON，形如 `{"model": "...", "answers": {"route": {"type": "choice", "choice": "billing",
"probabilities": {...}, "confidence": 0.98}, "angry": {"type": "noul", "noul": 0.89}}, "usage":
{"input_tokens": 128, "output_tokens": 0}}`。

#### GET /modelkit/chat/models

以 OpenAI 兼容的 wire 格式列出可用的 chat 模型。该端点聚合所有可用的 chat
模型（远程和本地），返回 `{"object": "list", "data": [...]}` 格式，与 llama.cpp
和 OpenAI 客户端期望的格式一致。仅包含 task 为 `chat` 的模型。

`GET /modelkit/chat/v1/models` 是相同行为的别名。

响应：`200 OK`

```json
{
  "object": "list",
  "data": [
    {
      "id": "qwen3-8b (Qwen 3 8B)",
      "aliases": ["Qwen 3 8B", "qwen3-8b"],
      "tags": [],
      "object": "model",
      "created": 1727654400,
      "owned_by": "openai",
      "meta": {
        "n_ctx": 8192
      }
    }
  ]
}
```

`id` 字段是基于模型别名和名称构建的展示标签（alias 与 name 不同时格式为
`alias (name)`，否则直接使用 alias 或 name）。`aliases` 数组同时包含 `name` 和
`alias`，便于灵活反查。`meta.n_ctx` 在可用时携带上下文窗口大小。

展示标签可能重名（例如两个应用各注册了一个叫 `gpt-4o` 的模型）。为了让客户端拿到的 `id`
不会指向多个模型，只要某个标签在列表内重复出现，**所有**使用该标签的条目都会回退为模型的
真实 `id`，其余条目保持展示标签不变。需要精确寻址时，
请使用 `GET /modelkit/models` 返回的 `id`。

#### 应用模型注册 API

第三方应用可以向 ModelKit 注册自己的模型，注册后的模型将出现在统一的
`/modelkit/models` 列表中，并可通过标准 ModelKit 代理路由访问。应用注册的模型会
持久化存储，网关重启后不会丢失。

##### 认证与归属

`GET /modelkit/app-models` 无需认证。**写接口**（`POST`、`PUT`、`DELETE` 以及
`toggle`）需要携带 `POST /appkit/register` 返回的 Bearer token：

```http
Authorization: Bearer <POST /appkit/register 返回的 token>
```

每个已注册的模型都归属于 token 所对应的 `bundleId`。注册时网关会为模型分配 `id`（12 位
hashid，见 [模型 ID 与寻址](#模型-id-与寻址)）。`PUT` / `DELETE` / `toggle` 的路径参数 `<id>`
只在**调用方自己的模型**中查找，因此应用天然无法修改其他应用的模型：

| 条件 | 状态码 |
| --- | --- |
| 缺少 token，或 token 不是由 `POST /appkit/register` 签发 | `401` |
| 网关没有 app model 存储（不支持注册） | `501` |
| `POST` 缺少 `name`，或 token 所属的 `bundleId` 不符合 `bundleId` 规则 | `400` |
| 对调用方自己的模型中不存在的 `id` 执行 `PUT` / `DELETE` / `toggle`（包括该 `id` 属于其他应用的情况） | `404` |
| `POST` 请求体里的 `appBundleId` 与 token 所属 bundle 不一致 | `403` |
| `PUT` 会让模型的 `name` 与同一 bundle 下的另一个模型重名，或 `POST` 生成的 `id` 仍被一个已改名的模型占用 | `409` |

token 用于向本地网关标识应用身份；`POST /appkit/register` 本身不对调用方做身份
认证，因此该校验的作用是让应用之间互不干扰、避免误操作，与其他 Kit 采用同一信任
模型。

所有写请求的请求体必须是 UTF-8 编码的 JSON 对象。字段类型不对（例如 `name` 不是字符串、
`capabilities` 不是对象）会返回 `400`，而不是被静默忽略。

##### AppModelData Schema

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `id` | `string` | 只读 | 模型 ID：注册时网关根据 `appBundleId + name` 生成的 12 位 hashid。它出现在注册响应和 `GET /modelkit/app-models` 中，与 `GET /modelkit/models` 里该模型的 `id` 完全一致，且模型改名后保持不变。用它来维护模型（`PUT` / `DELETE` / `toggle`），调用 `/modelkit/chat` 等代理路由时也把 `"model"` 设为它。 |
| `name` | `string` | 是 | 模型显示名称。对远程模型而言它就是上游模型名；ModelKit 会把请求里的 `model` 字段从 `id` 改写为该名称。同一应用注册的模型之间必须唯一；它与 `appBundleId` 共同决定 `id`（见 [POST /modelkit/app-models](#post-modelkitapp-models)）。 |
| `alias` | `string` | 否 | 便于展示的模型别名。 |
| `description` | `string` | 否 | 模型描述。 |
| `task` | `string` | 否 | 模型任务：`chat`（默认）、`embedding`、`asr`、`tts` 或 `decision`（大小写不敏感；`systemone`、`llm_decision` 视为 `decision` 的别名）。其他取值返回 `400`。 |
| `provider` | `string` | 否 | 提供商标识（默认：`openai_compatible`）。 |
| `input` | `string[]` | 否 | 输入模态（例如 `["text"]`）。缺省值随 task 变化，见 [Decision 模型](#decision-模型)。 |
| `output` | `string[]` | 否 | 输出模态（例如 `["text"]`）。缺省值随 task 变化，见 [Decision 模型](#decision-模型)。 |
| `capabilities` | `object` | 否 | 能力标记：`stream`（bool，默认 true）、`tool_call`（bool，默认 false）、`reasoning`（bool，默认 true）。`decision` 下一律强制为 `false`。 |
| `baseUrl` | `string` | 否 | 模型端点 base URL。 |
| `apiKey` | `string` | 否 | 模型端点的 API 密钥。 |
| `contextWindowSize` | `number` | 否 | 上下文窗口大小。 |
| `appBundleId` | `string` | 否 | 注册应用的 bundle ID。写入时可省略：取自 Bearer token；若提供则必须与 token 所属 bundle 一致，且注册后不可更改。 |
| `appName` | `string` | 否 | 注册应用的显示名称，默认为 `appBundleId`。 |

列出应用模型时，响应中会用 `hasApiKey`（boolean）替代 `apiKey`，避免暴露凭证。

##### Decision 模型

Decision 模型（`"task": "decision"`，llama.cpp `/v1/systemone`）以概率回答带类型的
问题，从不生成文本。为了让注册表与 ModelKit 本地发现的模型保持一致，网关会对
decision 的注册请求做归一化，无论调用方传入什么：

| 字段 | 行为 |
| --- | --- |
| `input` | 只保留 `text`（始终包含）和 `image`（可选，用于 Clef 等多模态 decision 模型）。缺省为 `["text"]`。`decisions` 属于输出模态，会从 `input` 中剔除。 |
| `output` | 恒为 `["decisions"]`。 |
| `capabilities` | `stream`、`tool_call`、`reasoning` 恒为 `false`。 |

反过来，`decisions` 不被其他任务接受：它会从 `chat`、`embedding`、`asr`、`tts` 模型的
`input` / `output` 中剔除，剔除后为空时回退到该任务的默认值。

注册后，通过 [`/modelkit/decision`](#all-modelkitdecision) 调用，并把 `"model"` 设为
模型的 `id`。

##### GET /modelkit/app-models

列出所有第三方应用注册的模型。每一项的 `id` 是注册时返回的 hashid，与该模型在
`GET /modelkit/models` 里的 `id` 一致。

响应：`200 OK`（`AppModelData[]`）

```json
[
  {
    "id": "6f78dcce6717",
    "name": "GPT-4o",
    "alias": "gpt-4o",
    "description": "OpenAI GPT-4o model",
    "task": "chat",
    "provider": "openai_compatible",
    "input": ["text"],
    "output": ["text"],
    "capabilities": {
      "stream": true,
      "tool_call": true,
      "reasoning": false
    },
    "baseUrl": "https://api.openai.com/v1",
    "hasApiKey": true,
    "contextWindowSize": 128000,
    "isDisabled": false,
    "appBundleId": "com.example.myapp",
    "appName": "My Example App"
  }
]
```

##### POST /modelkit/app-models

第三方应用注册模型。注册后的模型会出现在 `GET /modelkit/models` 中，
并可通过标准代理路由访问。需要 Bearer token（见[认证与归属](#认证与归属)）。

请求体：参见上方 AppModelData schema。`name` 为必填；模型 `id` 由网关生成，不需要传入。

网关把 `sha256("<bundleId>:<name>")`（`name` 去掉首尾空白，区分大小写）的前 12 位 hex 作为 `id`，
并在响应中返回。调用方应保存它：既用于维护该模型（`PUT` / `DELETE` / `toggle`），也在请求里把
`"model"` 设为它，即可精确路由到这个模型。token 所属的 `bundleId` 必须是 1–128 个
`[A-Za-z0-9._-]` 字符，否则返回 `400`（这条规则只在注册模型时校验，不影响 AppKit 的其他功能）。

同一个应用注册的模型默认 `name` 互不相同，所以 `name` 就是模型在应用内的身份：同一个 bundle
重复注册已有的 `name` 时，会**整体替换**该模型（响应带 `"updated": true`），保留其 `id` 与
启用/禁用状态，因此重试注册不会产生重复条目。替换是完整的：未提供的可选字段（包括 `apiKey`）
会被重置，需要局部更新请用 `PUT`。不同应用可以注册相同的 `name`，它们得到不同的 `id`。

说明：

- 比较前会先去掉 `name` 首尾空白，比较区分大小写（`GPT-4o` 与 `gpt-4o` 视为不同模型）。
- 已禁用的模型仍然占用其名称；通过 `DELETE` 注销后该名称才会释放（再次注册会得到同一个 `id`）。
- 模型通过 `PUT` 改名后 `id` 不变。如果新注册的 `name` 生成的 `id` 仍被一个已改名的模型占用，
  请求返回 `409` 且不会写入任何数据；请先注销那个模型，或换一个 `name`。

请求示例：

```bash
TOKEN=$(curl -s http://localhost:8888/appkit/register \
  -H 'Content-Type: application/json' \
  -d '{"bundleId":"com.example.myapp"}' | jq -r .token)

curl -X POST http://localhost:8888/modelkit/app-models \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer $TOKEN" \
  -d '{
    "name": "GPT-4o",
    "alias": "gpt-4o",
    "description": "OpenAI GPT-4o model",
    "appName": "My Example App",
    "task": "chat",
    "provider": "openai_compatible",
    "input": ["text"],
    "output": ["text"],
    "capabilities": {
      "stream": true,
      "tool_call": true,
      "reasoning": false
    },
    "baseUrl": "https://api.openai.com/v1",
    "apiKey": "sk-...",
    "contextWindowSize": 128000
  }'
```

响应：`200 OK`

```json
{
  "success": true,
  "id": "6f78dcce6717"
}
```

随后即可用返回的 `id` 调用该模型：

```bash
curl -X POST http://localhost:8888/modelkit/chat \
  -H 'Content-Type: application/json' \
  -d '{"model": "6f78dcce6717", "messages": [{"role": "user", "content": "你好"}]}'
```

示例：注册 decision 模型。只需提供身份与端点，`input`、`output`、`capabilities`
会按 [Decision 模型](#decision-模型) 一节自动补全：

```bash
curl -X POST http://localhost:8888/modelkit/app-models \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer $TOKEN" \
  -d '{
    "name": "Julia-1",
    "task": "decision",
    "baseUrl": "http://127.0.0.1:8080",
    "apiKey": "sk-..."
  }'
```

`GET /modelkit/app-models` 会把它报告为 `"task": "decision"`、
`"input": ["text"]`、`"output": ["decisions"]`，且所有能力位均为 `false`。它会出现在
`GET /modelkit/models` 中（但不会出现在 `GET /modelkit/chat/models`）；以
`"model": "b35bf2726675"`（即为 `Julia-1` 返回的 `id`）调用 `POST /modelkit/decision` 时，请求会被转发到
`http://127.0.0.1:8080/v1/systemone`，并以注册的 `apiKey` 作为上游 Bearer token，
同时把 `model` 改写为 `Julia-1`。

##### PUT /modelkit/app-models/\<id\>

更新已注册的应用模型，需要携带该模型所属 bundle 的 Bearer token。路径参数 `<id>` 是
注册时返回的 `id`，只会在调用方自己的模型中查找。仅更新请求体中提供的
字段；未提供的字段保留当前值。`apiKey` 只在传入非空值时才会覆盖。`appBundleId` 不可更改
（传入不同的值返回 `400`）。

重命名（修改 `name`）要求新的 `name` 没有被该应用的其他模型使用，否则请求返回 `409` 且模型
保持不变；模型改名后 `id` 不变。未修改名称的请求不会被该规则拦截。

修改 `task` 时，请求中未提供的 `input`、`output`、`capabilities` 会重置为新 task 的默认值，
而不是沿用旧 task 的值，同时套用新 task 的约束（例如 [decision](#decision-模型) 的约束）。
未知的 `task` 返回 `400`。

请求示例：

```bash
curl -X PUT http://localhost:8888/modelkit/app-models/6f78dcce6717 \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer $TOKEN" \
  -d '{
    "name": "GPT-4o Updated",
    "description": "Updated description",
    "contextWindowSize": 256000
  }'
```

响应：`200 OK`

```json
{
  "success": true
}
```

没有有效 token 时返回 `401`；在调用方自己的模型中找不到该 `id`（包括它属于其他应用的情况）时返回 `404`。

##### DELETE /modelkit/app-models/\<id\>

注销应用注册的模型，需要携带该模型所属 bundle 的 Bearer token。

请求示例：

```bash
curl -X DELETE http://localhost:8888/modelkit/app-models/6f78dcce6717 \
  -H "Authorization: Bearer $TOKEN"
```

响应：`200 OK`

```json
{
  "success": true
}
```

没有有效 token 时返回 `401`；在调用方自己的模型中找不到该 `id`（包括它属于其他应用的情况）时返回 `404`。

##### POST /modelkit/app-models/\<id\>/toggle

切换应用注册模型的禁用状态。被禁用的模型仍保持注册，但不参与活跃模型列表和代理
路由。需要携带该模型所属 bundle 的 Bearer token。

请求示例：

```bash
curl -X POST http://localhost:8888/modelkit/app-models/6f78dcce6717/toggle \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer $TOKEN" \
  -d '{}'
```

响应：`200 OK`

```json
{
  "success": true
}
```

没有有效 token 时返回 `401`；在调用方自己的模型中找不到该 `id`（包括它属于其他应用的情况）时返回 `404`。

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
