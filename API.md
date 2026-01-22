# AgentOS HTTP API

Base URL: `http://<host>:<port>` (default port: `20261`).

## Authentication

Bearer token is required for all `/agentkit/*` routes and for
`GET /appkit/subscribe`.

```
Authorization: Bearer <token>
```

## AgentKit (Proxy to LiteAgent Server)

AgentKit forwards requests to the LiteAgent Server configured by
`LITEAGENT_BASEURL` (default: `http://127.0.0.1:9527/api/v1`).
All routes below require a Bearer token. Request/response bodies, status
codes, and query parameters are proxied as-is to/from LiteAgent Server.
If the upstream is unavailable, the proxy may return `502`.

### Schemas

#### LLMConfig

| Field | Type | Required | Description |
| --- | --- | --- | --- |
| `baseUrl` | `string` | Yes | LLM endpoint base URL. |
| `apiKey` | `string` | Yes | LLM API key. |
| `model` | `string` | Yes | Model name. |
| `temperature` | `number` | No | Sampling temperature. |
| `maxTokens` | `number` | No | Max tokens. |
| `topP` | `number` | No | Top-p. |
| `supportsToolCalling` | `boolean` | No | Whether tool calling is supported. |
| `supportsDeepThinking` | `boolean` | No | Whether deep thinking is supported. |

#### ApiKey

| Field | Type | Required | Description |
| --- | --- | --- | --- |
| `type` | `string` | Yes | `basic` or `bearer`. |
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
| `llmConfig` | `LLMConfig` | Yes | LLM config. |
| `systemPrompt` | `string` | Yes | System prompt. |
| `openSpecList` | `OpenSpec[]` | No | Tool specs. |
| `callbackOpenTool` | `CallbackOpenTool` | No | Client callback tool. |
| `sessionList` | `SessionName[]` | No | Sub-sessions. |
| `reflectPromptList` | `ReflectPrompt[]` | No | Reflection prompts. |
| `timeoutSeconds` | `number` | No | Default `3600`. |
| `taskPipelineStrategy` | `string` | No | `parallel`, `serial`, `reject`. |
| `toolPipelineStrategy` | `string` | No | `parallel`, `serial`, `reject`. |
| `auto` | `boolean` | No | Auto-run tasks. |
| `llmConfigList` | `LLMConfig[]` | No | Alternative LLM configs. |
| `enableThinking` | `boolean` | No | Enable reasoning output. |

#### SimpleCapability

| Field | Type | Required | Description |
| --- | --- | --- | --- |
| `llmConfig` | `LLMConfig` | Yes | LLM config. |
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

#### ToolReturn

| Field | Type | Required | Description |
| --- | --- | --- | --- |
| `id` | `string` | Yes | Tool call ID. |
| `result` | `object` | Yes | Tool result payload. |

#### StreamCallback

| Field | Type | Required | Description |
| --- | --- | --- | --- |
| `event` | `string` | Yes | Stream event name. |
| `toolReturn` | `ToolReturn` | Yes | Tool return payload. |

#### OpenTool

| Field | Type | Required | Description |
| --- | --- | --- | --- |
| `openToolId` | `string` | Yes | OpenTool ID. |
| `description` | `string` | Yes | OpenTool description. |

#### AgentMessage

| Field | Type | Required | Description |
| --- | --- | --- | --- |
| `sessionId` | `string` | Yes | Session ID. |
| `agentId` | `string` | No | Agent ID. |
| `parentTaskId` | `string` | No | Parent task ID. |
| `taskId` | `string` | Yes | Task ID. |
| `role` | `string` | Yes | `system`, `user`, `agent`, `llm`, `tool`. |
| `to` | `string` | Yes | `user`, `agent`, `llm`, `tool`, `client`. |
| `type` | `string` | Yes | `text`, `imageUrl`, `contentList`, `functionCall`, `toolCalls`, `toolReturn`, `reflection`, `taskStatus`. |
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
| `id` | `string` | Yes | Model message ID. |
| `model` | `string` | Yes | Model name. |

#### AgentMessageChunk

| Field | Type | Required | Description |
| --- | --- | --- | --- |
| `sessionId` | `string` | Yes | Session ID. |
| `agentId` | `string` | No | Agent ID. |
| `parentTaskId` | `string` | No | Parent task ID. |
| `taskId` | `string` | Yes | Task ID. |
| `role` | `string` | Yes | `system`, `user`, `agent`, `llm`, `tool`. |
| `to` | `string` | Yes | `user`, `agent`, `llm`, `tool`, `client`. |
| `type` | `string` | Yes | `text`, `imageUrl`, `contentList`, `functionCall`, `toolCalls`, `toolReturn`, `reflection`, `taskStatus`. |
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
- `functionCall`: `AgentMessage`

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

Response: `200 OK` (`SessionTask`)

#### GET /agentkit/clear

Query:

| Field | Type | Required |
| --- | --- | --- |
| `sessionId` | `string` | Yes |

Response: `200 OK` (`Session`)

#### GET /agentkit/opentool-list

Response: `200 OK` (`OpenTool[]`)

#### POST /agentkit/callback

Query:

| Field | Type | Required |
| --- | --- | --- |
| `sessionId` | `string` | Yes |

Request body: `ToolReturn`

Response: `200 OK` (`Session`)

#### POST /agentkit/streamCallback

Query:

| Field | Type | Required |
| --- | --- | --- |
| `sessionId` | `string` | Yes |

Request body: `StreamCallback`

Response: `200 OK` (`Session`)

## AppKit

### POST /appkit/register

Request body:

```
{"bundleId":"com.demo.app"}
```

Response: `200 OK`

```
{"token":"sk-..."}
```

### GET /appkit/subscribe

Requires Bearer token (token from `/appkit/register`).

Response: `200 OK`, `text/event-stream`.

Event examples:

```
event: welcome
data: {"bundleId":"com.demo.app","token":"sk-..."}

```

```
event: agents
data: {"bundleId":"com.demo.app","agents":[]}

```

If the token is missing, returns `401`. If the token is invalid, the stream
emits:

```
event: error
data: {"error":"invalid_token"}

```

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

## Disabled Modules

Intent module is currently disabled and not exposed.
