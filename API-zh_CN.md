# AgentOS HTTP API

基础地址：`http://<host>:<port>`（默认端口：`20261`）。

## 鉴权

所有 `/agentkit/*` 路由以及 `GET /appkit/subscribe` 都需要 Bearer token。

```
Authorization: Bearer <token>
```

## AgentKit（代理 LiteAgent Server）

AgentKit 会把请求转发到 `LITEAGENT_BASEURL` 指定的 LiteAgent Server
（默认：`http://127.0.0.1:9527/api/v1`）。以下路由均需要 Bearer token。
请求/响应体、状态码和查询参数会原样透传到 LiteAgent Server。
上游不可用时可能返回 `502`。

### Schema（数据结构）

#### LLMConfig

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `baseUrl` | `string` | 是 | LLM 接口 base URL。 |
| `apiKey` | `string` | 是 | LLM API key。 |
| `model` | `string` | 是 | 模型名称。 |
| `temperature` | `number` | 否 | 采样温度。 |
| `maxTokens` | `number` | 否 | 最大 token 数。 |
| `topP` | `number` | 否 | Top-p。 |
| `supportsToolCalling` | `boolean` | 否 | 是否支持工具调用。 |
| `supportsDeepThinking` | `boolean` | 否 | 是否支持深度思考。 |

#### ApiKey

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `type` | `string` | 是 | `basic` 或 `bearer`。 |
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
| `llmConfig` | `LLMConfig` | 是 | LLM 配置。 |
| `systemPrompt` | `string` | 是 | 系统提示词。 |
| `openSpecList` | `OpenSpec[]` | 否 | 工具规范列表。 |
| `callbackOpenTool` | `CallbackOpenTool` | 否 | 客户端回调工具。 |
| `sessionList` | `SessionName[]` | 否 | 子 session 列表。 |
| `reflectPromptList` | `ReflectPrompt[]` | 否 | 反思提示列表。 |
| `timeoutSeconds` | `number` | 否 | 默认 `3600`。 |
| `taskPipelineStrategy` | `string` | 否 | `parallel`、`serial`、`reject`。 |
| `toolPipelineStrategy` | `string` | 否 | `parallel`、`serial`、`reject`。 |
| `auto` | `boolean` | 否 | 是否自动执行。 |
| `llmConfigList` | `LLMConfig[]` | 否 | 备用 LLM 配置。 |
| `enableThinking` | `boolean` | 否 | 是否输出推理文本。 |

#### SimpleCapability

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `llmConfig` | `LLMConfig` | 是 | LLM 配置。 |
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

#### ToolReturn

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `id` | `string` | 是 | 工具调用 ID。 |
| `result` | `object` | 是 | 工具返回结果。 |

#### StreamCallback

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `event` | `string` | 是 | 流事件名。 |
| `toolReturn` | `ToolReturn` | 是 | 工具返回结果。 |

#### OpenTool

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `openToolId` | `string` | 是 | OpenTool ID。 |
| `description` | `string` | 是 | OpenTool 描述。 |

#### AgentMessage

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `sessionId` | `string` | 是 | Session ID。 |
| `agentId` | `string` | 否 | Agent ID。 |
| `parentTaskId` | `string` | 否 | 父 task ID。 |
| `taskId` | `string` | 是 | Task ID。 |
| `role` | `string` | 是 | `system`、`user`、`agent`、`llm`、`tool`。 |
| `to` | `string` | 是 | `user`、`agent`、`llm`、`tool`、`client`。 |
| `type` | `string` | 是 | `text`、`imageUrl`、`contentList`、`functionCall`、`toolCalls`、`toolReturn`、`reflection`、`taskStatus`。 |
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
| `id` | `string` | 是 | 模型消息 ID。 |
| `model` | `string` | 是 | 模型名称。 |

#### AgentMessageChunk

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `sessionId` | `string` | 是 | Session ID。 |
| `agentId` | `string` | 否 | Agent ID。 |
| `parentTaskId` | `string` | 否 | 父 task ID。 |
| `taskId` | `string` | 是 | Task ID。 |
| `role` | `string` | 是 | `system`、`user`、`agent`、`llm`、`tool`。 |
| `to` | `string` | 是 | `user`、`agent`、`llm`、`tool`、`client`。 |
| `type` | `string` | 是 | `text`、`imageUrl`、`contentList`、`functionCall`、`toolCalls`、`toolReturn`、`reflection`、`taskStatus`。 |
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

响应：`200 OK`（`Session`）

#### POST /agentkit/initSimple

请求体：`SimpleCapability`

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
- `functionCall`：`AgentMessage`

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

响应：`200 OK`（`SessionTask`）

#### GET /agentkit/clear

Query:

| 字段 | 类型 | 必填 |
| --- | --- | --- |
| `sessionId` | `string` | 是 |

响应：`200 OK`（`Session`）

#### POST /agentkit/callback

Query:

| 字段 | 类型 | 必填 |
| --- | --- | --- |
| `sessionId` | `string` | 是 |

请求体：`ToolReturn`

响应：`200 OK`（`Session`）

#### POST /agentkit/streamCallback

Query:

| 字段 | 类型 | 必填 |
| --- | --- | --- |
| `sessionId` | `string` | 是 |

请求体：`StreamCallback`

响应：`200 OK`（`Session`）

## AppKit

### POST /appkit/register

请求体：

```
{"bundleId":"com.demo.app"}
```

响应：`200 OK`

```
{"token":"sk-..."}
```

### GET /appkit/subscribe

需要 Bearer token（来自 `/appkit/register`）。

响应：`200 OK`，`text/event-stream`。

事件示例：

```
event: welcome
data: {"bundleId":"com.demo.app","token":"sk-..."}

```

```
event: agents
data: {"bundleId":"com.demo.app","agents":[]}

```

如果 token 缺失，返回 `401`。如果 token 无效，流内会返回：

```
event: error
data: {"error":"invalid_token"}

```

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

## 已停用模块

Intent 模块当前已停用且不对外提供接口。
