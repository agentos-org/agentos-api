这是一个基于 [Shelf](https://pub.dev/packages/shelf) 的服务端应用，
支持通过 [Docker](https://www.docker.com/) 运行。

该服务提供 `/version` 端点用于健康检查与版本查询。

# 运行示例

## 配置

- `PORT`: 绑定端口；默认 `20261`。
- `AGENTOS_BASEURL`: 服务对外宣告的 base URL；默认
  `http://127.0.0.1:20261`。辅助脚本会自动设置。
- `LITEAGENT_BASEURL`: AgentKit 代理的 LiteAgent Server base URL；默认
  `http://127.0.0.1:9527/api/v1`。

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

- `/version` 返回 `pubspec.yaml` 中的版本号：
  `{"version": "1.0.0"}`。

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
- `GET /agentkit/opentool-list`
- `POST /agentkit/callback`
- `POST /agentkit/streamCallback`

## Toolkit API

Toolkit 当前已停用。

## AppKit API

- `POST /appkit/register` 注册 app bundle：`{"bundleId": "com.demo"}` -> `{"token": "sk-..."}`。
- `GET /appkit/subscribe`（Bearer required）以 SSE 形式输出事件：
  `event: welcome\ndata: {"bundleId": "..."}\n\n`。

## Intent API

Intent 当前已停用。
