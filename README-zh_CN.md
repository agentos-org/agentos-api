这是一个基于 [Shelf](https://pub.dev/packages/shelf) 的服务端应用，
支持通过 [Docker](https://www.docker.com/) 运行。

该网关为所有本地 AI 服务提供统一入口：
- **AgentKit**：智能体管理与对话（代理 LiteAgent）
- **IntentKit**：意图识别（基于 agentos_kernel）
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

AgentKit 在 `/agentkit/` 下代理 LiteAgent Server 的接口。请设置
`LITEAGENT_BASEURL` 为 LiteAgent Server 的 base URL（例如
`http://127.0.0.1:9527/api/v1`）。所有 AgentKit 路由都需要 Bearer token。

支持的代理路由：

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

## IntentKit API

IntentKit 提供内核驱动的意图识别接口，供意图检测类 App 使用。
所有 IntentKit 路由均需要 Bearer Token。

- `POST /intentkit/submitRaw`
- `POST /intentkit/submitIntent`
- `POST /intentkit/confirmJob`
- `POST /intentkit/suggestNextAction`

## ToolKit API


- `ALL /toolkit/*` - 透明代理所有请求到 OpenTool 后端。

## LLMKit API


- `ALL /llmkit/text/*` - 文本生成（chat completions）
- `ALL /llmkit/vision/*` - 图文理解
- `ALL /llmkit/embedding/*` - 文本嵌入
- `ALL /llmkit/tts/*` - 文本转语音
- `ALL /llmkit/asr/*` - 语音转文本

## AppKit API

- `POST /appkit/register` 注册 app bundle：`{"bundleId": "com.demo"}` -> `{"token": "sk-..."}`。
- `GET /appkit/subscribe`（需 Bearer token）以 SSE 形式输出事件：
  `event: welcome\ndata: {"bundleId": "..."}\n\n`。
