这是一个基于 [Shelf](https://pub.dev/packages/shelf) 的服务端应用，
支持通过 [Docker](https://www.docker.com/) 运行。

该网关为所有本地 AI 服务提供统一入口：
- **AgentKit**：Session 初始化与对话（基于 LiteAgent SDK）
- **CronKit**：定时任务管理（基于 agentos_kernel）
- **RagKit**：RAG 知识库管理与检索（基于 agentos_kernel）
- **AppKit**：应用注册与订阅
- **ToolKit**：通过网关访问工具执行能力
- **ModelKit**：基于任务的模型服务（chat、embedding、ASR、TTS、decision）
- **HarnessKit**：将 AppKit 鉴权后的请求路由到 AgentOS 唯一的 Harness runtime
- **AuthKit**：第三方应用 OAuth 认证
- **DiscoveryKit**：附近 AgentOS 设备发现
- **TransferKit**：跨设备文件传输

详细 HTTP API 文档：
- [API.md](API.md)
- [API-zh_CN.md](API-zh_CN.md)

## HarnessKit runtime 路由

AgentOS Runtime 托管唯一的 HarnessKit sidecar 和 runtime。任何完成 AppKit 注册的 App 都可
使用同一进程和数据库，无需声明 `harnessKit` 或额外登记。Gateway 依据 AppKit token 对应的
`bundleId` 隔离外部 App 的线程、运行结果和事件访问；内置 Harness 与侧边栏继续使用默认空间，
共享现有记录。App 使用 AppKit token 调用 Gateway 的 `/harnesskit/*`，不需要实现 Harness HTTP
API。所有 App 可读取当前引擎状态；切换共享引擎和读取全局运维快照仍属于宿主管理操作。
调用方可通过每次请求中的 `toolPolicy.allowedToolIds` 限制本次运行可用的工具。自定义宿主仍可
通过 `HarnessKitClientRegistry` 注入 client。
升级前没有记录 App 归属的历史线程会留在默认空间，不会自动迁移到外部 App。

# 运行示例

## 配置

- `PORT`: 绑定端口；默认 `8888`。
- `AGENTOS_BASEURL`: 服务对外宣告的 base URL；默认
  `http://127.0.0.1:8888`。辅助脚本会自动设置。

## 使用 Dart SDK 运行

```
$ ./tool/run_server.sh
Server listening on port 8888
AGENTOS_BASEURL=http://127.0.0.1:8888
```

另开一个终端：
```
$ curl http://127.0.0.1:8888/version
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
$ docker run -it -p 8888:8888 myserver
Server listening on port 8888
AGENTOS_BASEURL=http://127.0.0.1:8888
```

另开一个终端：
```
$ curl http://0.0.0.0:8888/version
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
- `POST /agentkit/initSession`
- `POST /agentkit/initSimple`
- `POST /agentkit/chat`（SSE 流式）
- `POST /agentkit/chat/simple`
- `GET /agentkit/history`（可选成对传入 `page` 和 `pageSize` 查询参数）
- `GET /agentkit/history/summary`（按任务摘要优先加载历史）
- `GET /agentkit/history/process`（按 `originalTaskId` 懒加载过程消息）
- `GET /agentkit/stop`
- `GET /agentkit/clear`
- `POST /agentkit/callback`
- `POST /agentkit/streamCallback`

`POST /agentkit/chat` 的 SSE 会输出 `message`、`chunk`、`functionCall`。
外部收到 `functionCall` 后，可调用
`POST /agentkit/callback?sessionId=...` 并提交 `ToolReturn` 完成该回调。
如需验证 `streamCallback` 是否会从 AgentKit 正确转发到 LiteAgent SDK，可运行：

```
$ dart run example/agentkit_stream_callback_example.dart
streamCallback forwarded successfully.
```

如需参照 `liteagent_server_dart` 的 `stream_call_example.dart` 运行一次真实 LLM
触发的完整 `streamCallback` 流程：

```
$ cd ../liteagent_server_dart
$ dart run bin/server.dart
```

然后回到本仓库，配置模型并运行：

```
$ cp example/.env.example example/.env
$ # 编辑 example/.env，填入 baseUrl / apiKey / model
$ dart run example/agentkit_stream_callback_llm_example.dart
```

`example/.env.example` 是隐藏 dotfile。如果你在 Finder 或普通文件列表里看不到，
可以运行 `ls -la example`。

这个示例会启动一个临时 AgentKit 网关，连接 `.env` 中的
`liteAgentBaseUrl`，通过 `initSession` 注册 `callbackOpenTool`，再调用
`/agentkit/chat`。当 LiteAgent 的 SSE 返回 stream functionCall 时，示例会
执行本地 `sequentiallyRead` mock 工具，并通过
`/agentkit/streamCallback` 依次回传 `data`、`done`。

大模型配置由 AgentKit 请求体中的 `llmConfig` 传给 LiteAgent：

```json
{
  "llmConfig": {
    "baseUrl": "https://api.openai.com/v1",
    "apiKey": "sk-...",
    "model": "gpt-4o-mini"
  }
}
```

本仓库也提供了示例环境变量模板：

```
$ cp example/.env.example example/.env
```

其中 `baseUrl`、`apiKey`、`model` 的命名与 `liteagent_server_dart` 的 example
保持一致。注意：单独调用 `streamCallback` 本身只是工具流式回调转发，不会调用
大模型；完整示例中的大模型调用发生在 `chat` 阶段，`streamCallback` 负责把工具
流式结果送回 LiteAgent。

`/agentkit/chat` 与 `/agentkit/chat/simple` 也支持在 `UserTask` 请求体中传入
`llmConfig`。它只覆盖本次请求使用的配置，不会修改 session 默认配置。直接覆盖
时应传入完整的 LiteAgent 兼容配置；同时支持 AgentKit 扩展的 `modelId` 反查。

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

`Capability` 的执行限制字段（`maxLlmRequests`、`maxToolRounds`、
`maxToolCalls`、`maxConsecutiveIdenticalToolRounds` 和
`maxTaskDurationSeconds`）也会通过 `/agentkit/initSession` 原样转发。

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

`sessionId` 是可选字段。创建任务时传入后，定时执行会复用该 LiteAgent
session；未传入时，kernel 会在任务执行时初始化 session。`timezone` 接受
IANA 时区名称，例如 `Asia/Shanghai`；Cron 会按该时区计算，计划时间以 UTC
返回。

`GET /cronkit/run` 用于读取单条 run 详情，响应里包含 `trigger` 字段，
用于标识该次 run 的触发方式（如 `manual` 或 `scheduler`）。
`GET /cronkit/run/messages` 用于读取该 run 持久化下来的 `AgentMessage[]`。
当前 CronKit 不提供 cron 执行过程的 SSE 或订阅式流输出。

如果 kernel 没有配置 cron 模块，CronKit 会返回 `503`。

## RagKit API

RagKit 暴露基于 kernel 的 RAG base、文档、同步与检索接口。
所有 RagKit 路由都需要通过 `POST /appkit/register` 获取的 Bearer token。

RagKit 的权限边界分成两层：

- 写操作只允许 owner `bundleId`
- 读和检索操作按 `appGroupId` 共享

也就是说，创建某个 RAG base 的 app 可以更新、删除、同步它；同一个
`appGroupId` 下的其他 app 则可以读取并检索这个 base。

支持的路由：

- `GET /ragkit/base?baseId=<id>`
- `GET /ragkit/base/list?offset=<n>&limit=<n>`
- `POST /ragkit/base/create`
- `POST /ragkit/base/update`
- `POST /ragkit/base/delete`
- `GET /ragkit/document?baseId=<id>&documentId=<id>`
- `GET /ragkit/document/list?baseId=<id>&offset=<n>&limit=<n>`
- `POST /ragkit/document/upsert`
- `POST /ragkit/document/upsertBatch`
- `POST /ragkit/document/delete`
- `POST /ragkit/sync/document`
- `POST /ragkit/sync/base`
- `POST /ragkit/sync/retryFailed`
- `POST /ragkit/query`

## ToolKit API

ToolKit 通过 AgentOS API Gateway 对外提供统一工具入口。外部客户端只需要访问
网关的 `/toolkit/*` 路由，不需要连接、配置或理解内部工具运行时。ToolKit
请求需要携带 `POST /appkit/register` 返回的 Bearer token。

示例：

```
$ TOKEN=$(curl -s http://127.0.0.1:8888/appkit/register \
    -H 'content-type: application/json' \
    -d '{"bundleId":"com.demo.app"}' | jq -r .token)
$ curl http://127.0.0.1:8888/toolkit/list \
    -H "authorization: Bearer $TOKEN"
```

常用端点：

- `GET /toolkit/list?all=0` - 列出可调用工具；`all=1` 还会包含已停止的
  `opentool-server` 工具。`opentool-server` 条目包含 `host`、`port`、`status` 和可选的来源信息；App
  条目使用相同的 `id`、`alias`、`status` 字段，但不含 `host` 和 `port`，因为调用由 AgentOS 代理。
- `GET /toolkit/{toolId}/load` - 返回工具的 OpenTool JSON 描述，包含可用函数
  和参数 schema。
- `POST /toolkit/{toolId}/call` - 调用一个函数：
  `{"id":"call-001","name":"status","arguments":{"depth":1}}` ->
  `{"id":"call-001","result":{...}}`。
- `POST /toolkit/{toolId}/streamCall` - 调用一个函数，并通过 SSE 接收长耗时或
  增量结果。

ToolKit 还会将显式 opt-in 的进程 App 列为 `app:{bundleId}` 工具，但需用户至少启用一个当前 schema 中的函数。通过 `/load`
获取 App 当前 schema；只有请求 schema 或函数时才会启动 App 后端。每个函数都必须由用户在
“设置 → 应用”中启用，才会出现在 `/load` 响应中并允许 `/call` 调用。没有声明
`rpc.discovery: "runtime"`（或旧版 `rpc.systemMethods` opt-in）的 App 不会列出。
App 工具由 AgentOS 代理，与 OpenTool Daemon 管理的 `opentool-server` 工具相互独立。
App 条目的 `status: "running"` 表示 ToolKit provider 可用；App 专用后端在首次 `/load` 或函数调用前仍可处于停止状态。
对于 App 工具，Gateway 会将 ToolKit `FunctionCall` 请求转换为 App 的 JSON-RPC wire format，并将调用响应和 SSE 帧转换回 ToolKit 结果格式。

## ModelKit API

基于任务的模型代理。视觉模型归于 `/modelkit/chat`，通过模型的
`capabilities.vision` 标识。

- `GET /modelkit/models` - 基于任务的模型列表
- `GET /modelkit/chat/models` - OpenAI 兼容的 chat 模型列表
- `ALL /modelkit/chat/*` - 文本/视觉生成（chat completions）
- `ALL /modelkit/embedding/*` - 文本嵌入
- `ALL /modelkit/asr/*` - 语音转文本
- `ALL /modelkit/tts/*` - 文本转语音
- `ALL /modelkit/decision/*` - 决策模型（通过 llama.cpp `/v1/systemone` 回答类型化问题）
- `GET /modelkit/app-models` - 列出应用注册的模型
- `POST /modelkit/app-models` - 第三方应用注册模型
- `PUT /modelkit/app-models/<id>` - 更新应用注册的模型
- `DELETE /modelkit/app-models/<id>` - 注销应用注册的模型
- `POST /modelkit/app-models/<id>/toggle` - 切换应用注册模型的启用/禁用状态

`app-models` 的写接口（`POST` / `PUT` / `DELETE` / `toggle`）需要携带
`POST /appkit/register` 返回的 AppKit Bearer token，并且模型只能由注册它的 bundle
修改。注册时不需要传模型 id：网关会根据 `bundleId + name` 生成 12 位 hashid，并在响应的
`id` 中返回；后续 `PUT` / `DELETE` / `toggle` 以及代理请求的 `model` 都使用它（它也是
`GET /modelkit/models` 里该模型的 `id`）。`task` 可取 `chat`、`embedding`、`asr`、`tts` 或
`decision`。

## AppKit API

- `POST /appkit/register` 注册 app bundle：
  `{"bundleId": "com.demo.desktop", "appGroupId": "com.demo"}` ->
  `{"token": "sk-...", "bundleId": "com.demo.desktop", "appGroupId": "com.demo"}`。
- 请求可包含
  `"opentoolServers":[{"ref":"websearch","name":"opentool-server-websearch"}]`。
  注册始终选择已安装的最高语义版本。
  该能力要求 OpenTool daemon 0.5.0+ 且具备 `artifactRegistryV2` 与
  `startToolTerminalV1` capability。
  每个声明会返回：带 `id` 的 `running`、不带 `id` 的 `starting`，或者不带
  `id` 的 `notFound`。
- 如果不传 `appGroupId`，服务端会默认以 `bundleId` 作为有效 group。
- `GET /appkit/subscribe`（需 Bearer token）以 SSE 形式输出事件：
  `event: welcome\ndata: {"bundleId": "..."}\n\n`。
- 异步拉起结果统一使用 `event: appEvent`；ToolKit 成功时发送带可调用 tool `id`
  的 `toolkit.provision.succeeded`，失败时发送带错误详情的
  `toolkit.provision.failed`。
- 拉起成功后，AgentOS 会持续监控每个已声明 tool。daemon 或 tool 进程不可用时
  推送 `toolkit.tool.unavailable`，恢复健康后推送 `toolkit.tool.available`；
  相同状态的重复检查不会重复推送。

## AuthKit API

AuthKit 为第三方应用提供类 OAuth 的认证能力，用于访问 AgentOS 用户数据。
所有 AuthKit 路由都需要通过 `POST /appkit/register` 获取的 Bearer token。

支持的路由：

- `POST /authkit/authorize` - 发起授权请求（返回 `requestId` 和授权 URL 供用户
  同意）
- `GET /authkit/authorize/<requestId>/status` - 轮询授权状态
- `POST /authkit/token` - 用授权码换取访问令牌
- `GET /authkit/userinfo` - 获取用户资料（需使用令牌交换返回的 access token）
- `POST /authkit/revoke` - 撤销访问令牌
流程：应用调用 `/authorize` 传入所需 `scopes` 和可选 `appName`，将授权 URL
展示给用户，轮询 `/status` 直到用户同意/拒绝，然后通过 `/token` 换取令牌。
获取的 access token 可用于请求 `/userinfo`。用户信息发生变更时会自动刷新。

## DiscoveryKit API

DiscoveryKit 通过 mDNS/TLS 实现附近 AgentOS 设备发现。
所有 DiscoveryKit 路由都需要通过 `POST /appkit/register` 获取的 Bearer token。

支持的路由：

- `GET /discoverykit/peers` - 列出当前已发现的附近设备
- `GET /discoverykit/peers/stream` - 实时设备发现/离开事件的 SSE 流
- `GET /discoverykit/self` - 获取本设备的发现身份
- `POST /discoverykit/register` - 注册本设备加入发现（可选传入
  `receivePolicy`：`auto` | `confirmation`）
- `POST /discoverykit/unregister` - 注销本设备退出发现

设备流会在附近设备出现或消失时实时推送事件。发现状态变更会即时传播。

## TransferKit API

TransferKit 提供 AgentOS 设备间的安全文件传输能力。
所有 TransferKit 路由都需要通过 `POST /appkit/register` 获取的 Bearer token。

支持的路由：

- `POST /transferkit/send` - 向已发现的设备发起文件传输
- `GET /transferkit/transfers` - 列出活跃/最近的传输
- `GET /transferkit/transfers/<transferId>/status` - 获取传输状态
- `GET /transferkit/transfers/<transferId>/stream` - 传输进度事件的 SSE 流
- `POST /transferkit/transfers/<transferId>/cancel` - 取消进行中的传输
- `POST /transferkit/transfers/<transferId>/respond` - 接受或拒绝传入的传输请求
  （用于 `confirmation` 接收策略）
- `GET /transferkit/receive/stream` - 传入传输请求的 SSE 流
- `PUT /transferkit/receive/policy` - 设置文件接收策略
- `GET /transferkit/receive/policy` - 获取当前接收策略
- `GET /transferkit/history` - 列出传输历史记录
- `DELETE /transferkit/history/<recordId>` - 删除指定历史记录
- `DELETE /transferkit/history` - 清空全部传输历史

接收策略：
- `autoAccept`：自动接受传入的文件
- `requireConfirm`：每次传输需要用户/应用明确确认
