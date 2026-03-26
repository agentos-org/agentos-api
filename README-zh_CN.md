这是一个基于 [Shelf](https://pub.dev/packages/shelf) 的服务端应用，
支持通过 [Docker](https://www.docker.com/) 运行。

该网关为所有本地 AI 服务提供统一入口：
- **AgentKit**：智能体管理与对话（基于 LiteAgent SDK）
- **CronKit**：定时任务管理（基于 agentos_kernel）
- **AppKit**：应用注册与订阅
- **ToolKit**：工具执行（代理 OpenTool）
- **LLMKit**：LLM 服务（文本生成、图文理解、文本嵌入、TTS、ASR）

# 运行示例

## 配置

- `PORT`: 绑定端口；默认 `20261`。
- `AGENTOS_BASEURL`: 服务对外宣告的 base URL；默认
  `http://127.0.0.1:20261`。辅助脚本会自动设置。

## 使用 Dart SDK 运行

```
$ ./tool/run_server.sh
Server listening on port 20261
AGENTOS_BASEURL=http://127.0.0.1:20261
```

另开一个终端：
```
$ curl http://127.0.0.1:20261/version
{"version":"1.0.0"}
```

显式覆盖默认值：
```
$ PORT=8080 AGENTOS_BASEURL=http://127.0.0.1:8080 dart run bin/server.dart
Server listening on port 8080
AGENTOS_BASEURL=http://127.0.0.1:8080
```

## 使用 Docker 运行

```
$ docker build . -t myserver
$ docker run -it -p 20261:20261 myserver
Server listening on port 20261
AGENTOS_BASEURL=http://127.0.0.1:20261
```

另开一个终端：
```
$ curl http://0.0.0.0:20261/version
{"version":"1.0.0"}
```

你会在第一个终端看到日志：
```
2021-05-06T15:47:04.620417  0:00:00.000158 GET     [200] /
2021-05-06T15:47:08.392928  0:00:00.001216 GET     [200] /echo/I_love_Dart
```

## Root API

系统端点提供网关信息。

- `GET /` 返回网关信息，包含所有可用端点。
- `GET /version` 返回版本号：`{"version": "1.0.0"}`。

## AgentKit API

AgentKit 在 `/agentkit/` 下提供 LiteAgent 兼容接口，并通过 LiteAgent SDK
执行。默认 LiteAgent 地址来自 `DefaultServiceLocator`：
`http://127.0.0.1:9527/api/v1`。所有 AgentKit 路由都需要 Bearer token。

支持的路由：

- `GET /agentkit/version`
- `GET /agentkit/agent`
- `POST /agentkit/agent/create`
- `POST /agentkit/agent/update`
- `GET /agentkit/agent/delete`
- `POST /agentkit/initSession`
- `POST /agentkit/initSimple`
- `POST /agentkit/chat`（SSE 流式）
- `POST /agentkit/chat/simple`
- `GET /agentkit/history`
- `GET /agentkit/stop`
- `GET /agentkit/clear`
- `POST /agentkit/callback`
- `POST /agentkit/streamCallback`

`POST /agentkit/chat` 的 SSE 会输出 `message`、`chunk`、`functionCall`。
外部收到 `functionCall` 后，可调用
`POST /agentkit/callback?sessionId=...` 并提交 `ToolReturn` 完成该回调。

`POST /agentkit/initSession` 与 `POST /agentkit/initSimple` 也支持在
`Capability` / `SimpleCapability` 中传入 `skills`。AgentKit 会原样转发给
LiteAgent SDK。`skills` 的每一项都应是完整的 Agent Skills Markdown
文档，而不是仅传技能名。规范来源是官方 Agent Skills 规范：
[agentskills.io/specification](https://agentskills.io/specification)。
具体应遵循其中的 `SKILL.md` 格式：先写 YAML frontmatter，再写 Markdown
说明正文。示例：

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

CronKit 暴露基于 kernel 的定时任务管理接口。所有 CronKit 路由都需要
通过 `POST /appkit/register` 获取的 Bearer token。
`POST /appkit/register` 接收 `bundleId`，也可以附带可选的 `appGroupId`。
如果未传 `appGroupId`，服务端会默认使用 `bundleId`。
Cron 任务归属由 bearer token 推导：
同一个 `appGroupId` 下，CronKit 的任务和运行记录接口都按 group 共享访问。

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

CronKit 的任务 `spec` 请求体已对齐 kernel 新 schema：

```json
{
  "systemPrompt": "You are a scheduled agent.",
  "content": [
    {"type": "text", "message": "Generate the daily summary."}
  ],
  "timeoutSeconds": 3600
}
```

`GET /cronkit/run` 用于读取单条 run 详情，响应里包含 `trigger` 字段，
用于标识该次 run 的触发方式（如 `manual` 或 `scheduler`）。
`GET /cronkit/run/messages` 用于读取该 run 持久化下来的 `AgentMessage[]`。
当前 CronKit 不提供 cron 执行过程的 SSE 或订阅式流输出。

如果 kernel 没有配置 cron 模块，CronKit 会返回 `503`。

## ToolKit API


- `ALL /toolkit/*` - 透明代理所有请求到 OpenTool 后端。

## LLMKit API


- `ALL /llmkit/text/*` - 文本生成（chat completions）
- `ALL /llmkit/vision/*` - 图文理解
- `ALL /llmkit/embedding/*` - 文本嵌入
- `ALL /llmkit/tts/*` - 文本转语音
- `ALL /llmkit/asr/*` - 语音转文本

## AppKit API

- `POST /appkit/register` 注册 app bundle：
  `{"bundleId": "com.demo.desktop", "appGroupId": "com.demo"}` ->
  `{"token": "sk-...", "bundleId": "com.demo.desktop", "appGroupId": "com.demo"}`。
- 如果不传 `appGroupId`，服务端会默认以 `bundleId` 作为有效 group。
- `GET /appkit/subscribe`（需 Bearer token）以 SSE 形式输出事件：
  `event: welcome\ndata: {"bundleId": "..."}\n\n`。
- 当内核触发 App 调用时，已订阅 App 可能收到：
  `event: callApp\ndata: {"bundleId":"...","contentList":[...]}\n\n`。
