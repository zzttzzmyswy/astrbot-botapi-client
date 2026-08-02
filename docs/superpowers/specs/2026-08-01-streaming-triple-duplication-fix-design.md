# 流式消息「三分重复 + 旧坏消息残留」修复设计

- 日期：2026-08-01
- 影响范围：`astrbot-app`（Flutter 客户端），不涉及服务端插件
- 状态：待评审

## 1. 问题

手机 App 端收到 bot 流式回复时，气泡里出现**成组的 3 倍重复**（如
`收到收到收到，我将为我将为我将为您完成您完成您完成`）。每个短语**整组**重复
3 次（d1×3 → d2×3），而非交错（`收我将到收…`）。当整轮回复完成（`final`）后，
才会新增一条干净、无重复的消息；但此时**旧的、重复过的那条坏消息仍留在列表里**。

## 2. 根因（已证）

### 2.1 服务端是无辜的（已用真实 token 实测证伪）

- 单连接抓 `/stream`：N 个 `streaming:true` 增量片段拼接后与 `final` 全文**逐字符相等**；
  `segment_end` 事件 0 个。
- 同 token 并开 3 条 `/stream`：每条各自收到一份完整且正确的流，互不干扰。

→ 服务端每个事件只发一次、delta 是真增量、final 是真全文。问题 100% 在 App 端。

### 2.2 重复是「成组」的 ⇒ N 个订阅共享一个累加器

- N 个独立 HTTP 连接受网络抖动影响，重复必然**交错**。
- 1 个 `state.streamingText` 累加器 + N 个 `_handleEvent` 订阅同步各追加一次，
  才会**整组**重复 N 倍。

→ 即：存在 N 个激活的 `_handleEvent` 订阅，都在往同一个 `state.streamingText` 追加 delta。

### 2.3 `ChatNotifier.connect()` 非重入 ⇒ 订阅泄漏 + 孤儿客户端

`lib/providers/chat_provider.dart` 的 `connect()`（约 252–342 行）：

```
_eventSub?.cancel(); _eventSub = null;   // 顶部清理
…
await _http!.auth();            // 网络 await（可达 ~12s+重试）
await _http!.fetchHistory(…);   // 网络 await
… 多个 await cache …
_client = BotApiClient(…);              // 这里才赋新 client
_eventSub = _client!.events.listen(_handleEvent);  // 这里才赋新 sub
```

顶部清理与「赋新 client/新 sub」之间隔着一长串 `await`（可达十几秒）。这段窗口里
`_eventSub`/`_client` 都是 `null`。`connect()` **没有重入护栏**，而 App 回前台 /
网络变化 / 切账户都会调它：

| 时刻 | 事件 |
|---|---|
| T0 | `connect#1` 启动：顶部清理（subs 为 null）→ 进入 `await auth()` |
| T1 | `connect#2` 启动（如 connectivity 触发）：顶部清理发现 `_eventSub` 仍为 null → **跳过清理** → 也进入 await |
| T2 | `connect#1` await 结束：赋 `_client=A`、`_eventSub=subA`（监听 A 的流）。A 开始收 SSE |
| T3 | `connect#2` await 结束：赋 `_client=B`（**覆盖引用，A 成孤儿但从未 dispose**）、`_eventSub=subB`（**覆盖引用，subA 从未 cancel，仍活着**） |

后果：

- **孤儿客户端 A 永不释放**，自带重连循环，长期挂着 SSE。
- **subA 一直激活**：A 每收到一个事件就调一次 `_handleEvent`；subB 同理。
- A、B 是同 token 的两条独立连接，服务端**每条都投递一份完整回复**。于是每个 delta
  经 A→subA 追加一次、经 B→subB 再追加一次 → **成组 2 倍**；再来一次重叠 `connect()`
  → **3 倍**。泄漏**永久累积**，解释「会反复出现 3 分重复」。

### 2.4 「完成后才出干净消息、旧坏消息残留」的成因

1. 流式过程中某次重连（`state`→reconnecting/disconnected）触发
   `_flushInterruptedStream`，把**当前已被 N 倍化的 `state.streamingText`** 当作
   「中断占位行」落库（带 `_(回复中断,请重试)_` 后缀）。
2. 真正 `final` 到达，`_commitBotText` → `upsertBotText` 按「内容+5min」去重，
   **只插入 1 条干净消息**。
3. `reconcileInterruptedPlaceholders` 的清理逻辑是「占位行去掉后缀的半截若是完整
   回复的**前缀**则删除」。但 N 倍化文本**不是**干净回复的前缀 → **识别失败，坏消息残留**。

→ 流式时 N 倍 → 完成后多一条干净的 → 旧 N 倍坏消息仍在。与用户观测完全吻合。

## 3. 修复目标

- 流式气泡只追加一次 delta（无 N 倍重复）。
- 同一时刻至多一个激活的 `BotApiClient` 与一对 (`_eventSub`/`_stateSub`)。
- 接管新连接时，旧 client 必被 `dispose()`、旧 sub 必被 `cancel()`，无论时序。
- 中断占位行不再因孤儿客户端抖动被误 flush；保留既有「真断连」时的中断提示语义。

非目标（不做）：
- 不改服务端协议（不加 seq、不改 delta/cumulative 语义）。
- 不引入客户端内容级去重（非根因，属补丁）。

## 4. 设计

### 4.1 `ChatNotifier.connect()` 重入安全 + 接管前强制清理

`lib/providers/chat_provider.dart`：

1. 新增 `int _connectGen = 0;` 世代号。
2. `connect()` 入口：`final gen = ++_connectGen;`
3. 每个 `await`（auth、fetchHistory、各 cache 调用、`_client.connect`）之后插入：
   ```
   if (gen != _connectGen) return;   // 已被更新的轮接管，本轮作废
   ```
4. 在「赋新 client」之前（约 314 行 `_client = BotApiClient(...)` 之前）加**接管前强制
   清理**：再次 `cancel()` 当时存在的 `_eventSub`/`_stateSub`、`dispose()` 当时存在的
   `_client`，再置 null。这保证：任何并发兄弟轮在赋值瞬间都会先回收上一轮，杜绝覆盖
   引用造成的泄漏。
5. 顶部清理保留（仍正确处理「串行」调用的常规情况）。

要点：世代号让**旧 await 苏醒后自废**，强制清理让**赋值瞬间回收上一轮**——两者配合，
无论并发时序如何，至多一个 client/一对 sub 存活。

### 4.2 `BotApiClient.connect()` 重入护栏（防重叠 `_parseStream`）

`lib/services/botapi_client.dart`：内部重连路径（`_scheduleReconnect`→`connect`、
`_forceReconnect`）也可能与外部 `connect()` 并发，导致同一 `_eventController` 被两个
`_parseStream` 循环喂数据。加护栏：

1. 新增 `int _connectGen = 0;`（`BotApiClient` 自有的、与 `ChatNotifier` 的世代号相互独立——各自只管自己类内的重入）。
2. `connect()` 入口 `final gen = ++_connectGen;`；在 `_parseStream` 启动前 `if (gen != _connectGen) return;`（被更新的内部重连超越，本轮不启动 parse）。
3. `_parseStream` 循环内每次取行后校验 `if (gen != _connectGen) break;`，令被超越的旧 parse 退出。
4. `connect()` 顶部 `_httpClient?.close()` 已有，保留；新轮开始即令旧 parse 失效。

这样同一 client 上至多一个激活 `_parseStream`。

### 4.3 不动 `reconcileInterruptedPlaceholders` / `_flushInterruptedStream`

4.1 + 4.2 落地后，孤儿客户端不再产生、状态抖动消失，`_flushInterruptedStream` 不会再在
「连接其实活着」时误触。既有的真断连→中断占位→重连拿完整 final→reconciler 清理的链路
保持原样（干净文本是 final 前缀，能被正确清理）。无需改 reconciler，也不引入内容去重。

## 5. 验证

### 5.1 单元测试（`astrbot-app/test/`）

- `chat_provider` 重入：模拟「connect#1 在 await auth 期间，connect#2 接管」，断言全程
  至多一个激活 `BotApiClient`（用假 client 计数 new/dispose），至多一对 sub（计数
  listen/cancel），`_handleEvent` 订阅数恒为 ≤1。
- `BotApiClient` 重入：模拟「connect() 在 await send 期间再次 connect」，断言只有一次
  `_parseStream` 处于激活（用假 streamedResponse 计数消费行数），事件不被重复 `add`。

### 5.2 端到端手测（真机）

用给定测试 token 对 `https://astrbot.zztweb.top`：

- 发一条会流式回复的消息（如「用一句话介绍你自己，然后数 1 到 5」）。预期：气泡逐字
  增长，**无成组重复**；完成后仅 1 条干净消息，无残留坏消息。
- 制造重连（切后台 ≥90s 触发空闲看门狗、或飞行模式开关）后再发，仍无重复、无残留。
- 快速来回切账户 3 次后发消息，确认无累积重复（即无遗留孤儿客户端）。

### 5.3 一次性诊断日志（验收用，验后移除）

- 在 `BotApiClient` 构造与 dispose 打 `debugPrint` 实例 id；在 `connect()` listen 时打印
  订阅计数。复现一次确认「泄漏」消失。验后删除。

## 6. 风险与回滚

- 世代号 abort 可能让某次「正当的」重连（如切账户）被更晚的调用抢先——但切账户本身
  就是最新意图，被最新轮接管是正确行为，无功能损失。
- 强制清理 `dispose` 旧 client 是幂等的，已在 `dispose()` 内 `if (_disposed) return`。
- 回滚：还原 `chat_provider.dart` 与 `botapi_client.dart` 两个文件的世代号与强制清理
  片段即可，无数据迁移、无协议变更。

## 7. 变更清单

- `astrbot-app/lib/providers/chat_provider.dart`：`connect()` 加世代号 + 接管前强制清理。
- `astrbot-app/lib/services/botapi_client.dart`：`connect()` 加世代号 + `_parseStream` 退出校验。
- `astrbot-app/test/`：新增重入与订阅泄漏单测。
- `astrbot-app/CHANGELOG`（若有）：记一条 Fixed。
