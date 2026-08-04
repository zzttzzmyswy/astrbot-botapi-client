# 单账户多会话（Multi-Session）设计

> 日期：2026-08-04
> 范围：`astrbot-app`（Flutter 客户端）+ `astrbot_plugin_botapi`（AstrBot 服务端插件）

## 目标

为单个账户（token）支持**多个命名会话（会话）**：可新增、删除、修改、重命名；会话与消息**跨 app 设备同步**；**服务端 Web 管理平台**也能管理会话。当前模型为「1 token = 1 账户 = 1 会话」。

## 设计决策（已与用户确认）

1. **会话按账户隔离**：每个账户（token）下有 N 个命名会话；会话共享同一 token/bot persona，仅上下文与历史相互独立。
2. **UI 位置**：账户抽屉 → 选择账户 → 展开该账户的会话面板（两级抽屉，支持返回）。
3. **Web 管理**：账户表 → 点「对话」下钻到该账户的会话列表（新建/改名/删除/直接对话）。
4. **同步模型 = 服务端权威**：服务端持有每账户唯一权威的会话列表；app 与 Web 都通过 API 读写它；离线时 app 用本地镜像，重连后拉取。**不在本设计内**：双向合并冲突解决。

## 已验证的技术事实（决定设计）

来源：`https://github.com/AstrBotDevs/AstrBot`（原 `Soulter/AstrBot`），master (v4.27.1) 与 v4.10.0 一致。AstrBot 核心**未安装**在本机，以下经源码核对。

- `ConversationManager`（`astrbot/core/conversation_mgr.py`，版本下限 **v4.10.0**）提供：
  - `new_conversation(umo, platform_id=None, content=None, title=None, persona_id=None) -> str`（返回新 cid）
  - `switch_conversation(umo, cid) -> None`（切换当前会话）
  - `get_conversations(umo=None, platform_id=None) -> list[Conversation]`（枚举/计数）
  - `delete_conversation(umo, cid=None)`（删当前若省略）
  - `get_curr_conversation_id(umo)` / `get_conversation(umo, cid, create_if_not_exists=False)`
  - 无 `set_curr_conversation_id` —— `switch_conversation` 即该能力
- **umo 加后缀安全**：`MessageSession.from_str` 用 `split(":", 2)`（只按前两个冒号切分），第三段（session_id）可含冒号；DB 将 umo 当不透明串精确匹配。`session_id = f"{token}:{sid}"` 完全安全；首段必须仍是合法 `platform_id`，第二段仍须为 `FriendMessage`。
- **路由机制**：LLM pipeline 在处理消息时调用 `get_curr_conversation_id(event.unified_msg_origin)`。因此只要在 `commit_event` 前用「会话作用域 umo」构造事件（`event` 的 session_id 或先 `switch_conversation`），该消息即进入目标会话的上下文。
- **`PlatformMessageHistoryManager`** 按 `(platform_id, user_id)` 精确字符串匹配，`user_id` 无长度限制。分会话历史 = 用会话作用域的 `user_id = f"{token}:{sid}"`。
- **`send_by_session`**（`adapter.py:83`）读 `session.session_id` 取 token：改为后缀 umo 后需从第三段切出裸 token 与 sid。

## 术语

- **账户（account）**：既有概念。`Account{id, label, serverUrl, token}`。账户 id = 本地 UUID（`base36(ms)+base36(计数器)`，**不含冒号**）。
- **会话（session）**：新概念。`ChatSession{id, name}`，属于某账户。服务端权威。
- **默认会话**：每账户首个会话，id 固定 `default`。无后缀 umo 与历史 key 专属于它（后详）。**存量历史零迁移**。
- **sid（server session id）**：服务端会话 id（uuid hex）；客户端通过它索引会话。

---

## 一、服务端：会话元数据模型

### 存储

会话列表随插件 config 持久化（与 tokens/nicknames 同处 `astrbot_config`），保证重启不丢、跨设备一致。

```json
// astrbot_config 中该平台条目新增字段
"tokens": [ "<token>", ... ],
"nicknames": { "<token>": "<昵称>" },
"sessions": {
  "<token>": [
    { "id": "default", "name": "默认会话", "created_at": 1719000000 },
    { "id": "7f3a...",  "name": "工作",      "created_at": 1719100000 }
  ]
}
```

- 顺序 = 列表序（App 展示用）。
- `default` 会话为每 token 隐式首个：`ensure_sessions(token)` 幂等补建。
- 修改会话时，沿 `main.py` 现有 `_persist_account_state` 模式：同步 `adapter.config` + `adapter.cfg` + `_cfg_singleton` 子树 + `save_config()`。

### 会话作用域键

| 概念 | 默认会话（`default`） | 其它会话（`sid`） |
|---|---|---|
| conversation umo | `{pid}:FriendMessage:{token}` | `{pid}:FriendMessage:{token}:{sid}` |
| history `user_id` | `{token}` | `{token}:{sid}` |
| SSE 队列 key | `token` | `{token}:{sid}` |

> 关键：**默认会话沿用现有无后缀键 → 所有存量历史/对话上下文归入默认会话，零迁移**；新会话从全新键开始。老客户端（不发 `session_id`）继续命中默认会话，**完全兼容**。

### adapter 运行时状态

- `_sse_clients: defaultdict(list)` 的 key 由 `token` 改为 **`scoped_key`（`token` 或 `token:sid`）**。
- `_token_to_origin` 由 `{token: umo}` 改为同时缓存默认 umo；会话 umo 现算即可。
- 广播函数不变（`_broadcast_to(scoped_key, evt)`），但 SSE 事件体**新增 `session_id` 字段**，让客户端把事件归属到会话（App 多设备/多会话可据此分发）。
- 会话级 SSE 事件体 `session_id` 取值：
  - 默认会话广播 → 空串 `""`（兼容老客户端：App 端 `?? ''` 归一为默认会话）。
  - 其余会话广播 → 该 `sid`。

---

## 二、服务端：会话 API

### Phone API（`/api/v1/botapi`，鉴权不变：Bearer token）

| 方法 | 路径 | 请求 | 响应 | 说明 |
|---|---|---|---|---|
| GET | `/sessions` | — | `{"sessions":[{"id","name","created_at"}...], "default_id":"default"}` | 会话列表（含默认） |
| POST | `/sessions` | `{"name":"工作"}` | `{"session":{"id","name","created_at"}}` | 新建 |
| POST | `/sessions/<sid>/rename` | `{"name":"新名"}` | `{"message":"会话已重命名"}` | 重命名 |
| POST | `/sessions/<sid>/delete` | — | `{"message":"会话已删除"}` | 删除（会删 `delete_conversation(umo)` + 历史 key 下历史） |

### 既有 Phone API 增加 `session_id`

- `POST /message`：body 增加可选 `session_id`。缺省/空 → 默认会话（老客户端兼容）。校验 sid 属于该 token，404 拒绝。
- `GET /stream`：query 增加可选 `session_id`。连接挂到 `_sse_clients[scoped_key]`。
- `GET /history`：query 增加可选 `session_id`。缺省 → `user_id={token}`。

### 实现要点

- `submit_inbound(adapter, token, text, file_ids=None, session_id="")`：
  - 解析 `sid = session_id or "default"`；`scoped_umo = umo_for(token, sid)`。
  - 构造 AstrBotMessage 时 `msg.session_id = scoped_umo`（**这是路由到正确会话的关键** —— pipeline 在 `get_curr_conversation_id(umo)` 时读的就是它）；`msg.sender.user_id = token`（persist/认证不变）。
  - `persist_inbound_text` 用 `scoped_key`。
- `BotApiMessageEvent`：`self.token = message_obj.sender.user_id`（不变）；**新增 `self.sid`**（从 `message_obj.session_id` 切出），`_broadcast` 改投 `_sse_clients[scoped_key]` 并带 `session_id` 字段。
- 清空会话 = `_do_clear` 加 `session_id`：`switch_conversation(umo, sid_cid)` 后 `new_conversation`（或按需删建）。
- 会话删除：`delete_conversation(scoped_umo, cid)` + 从 config 移除 + 断开该 scoped_key 的 SSE 队列。**默认会话不可删**（可改名为"默认会话"）。

### Web 管理（dashboard）

- `context.register_web_api` 新增：
  - `GET/POST astrbot_plugin_botapi/sessions/<token_hash>`（列表/新建）
  - `POST astrbot_plugin_botapi/sessions/<token_hash>/<sid>/rename`
  - `POST astrbot_plugin_botapi/sessions/<token_hash>/<sid>/delete`
- `pages/dashboard/app.js`：账户表「对话」按钮 → 先 GET 该账户 sessions → 显示会话列表（名称 + 新建/改名/删除按钮）→ 选中进入既有 chat 视图。chat/history/clear 请求体**加 `session_id`**。
- `index.html`：复用现有模态框（confirmDialog/promptDialog），新增会话列表容器。

---

## 三、App：会话管理

### 模型与持久化

- 新模型 `lib/models/chat_session.dart`：`ChatSession{id, name}`，`copyWith`。
- 新 `lib/services/session_store.dart`（纯逻辑 + `SessionStorage` 抽象，仿 `AccountStore`）：
  - 持久化到 SharedPreferences：`sessions_v1`（`Map<accountId, List<ChatSession>>`）+ `current_session_v1`（`Map<accountId, String>` 每账户记住当前会话，重启恢复）。
  - 能力：list/add/rename/delete/getCurrent/setCurrent；cap `kMaxSessionsPerAccount = 25`。
- **服务端权威**：`connect()` 时 `GET /sessions` 拉取权威列表 → 与本地镜像合并（服务端为准）→ 写回镜像。服务器 404 → 单会话降级（`default` 单条）。

### DB（`lib/services/cache_service.dart`）

- 沿用既有 `session_id` 列 + `idx_messages_session` 索引。**语义变更**：`session_id` 由 `= 账户id` 变为 `= 账户id:会话id`（`default` 会话 `= 账户id:default`）。
- 迁移（`_ensureSchema` 增加一次幂等 re-key）：
  - `UPDATE messages SET session_id = session_id || ':default' WHERE session_id IS NOT NULL AND instr(session_id, ':') = 0`
  - 账户 id 不含冒号（已验证）→ `instr=0` 精准匹配旧行；幂等（二次执行 instr 已非 0）。
- 所有既有 cache 调用点（`insertMessage/upsert/upsertBotText/getMessages/mergeHistory/maxServerId/getMessageCount/clearSession`）的 `accountId:` 参数语义改为 **scoped key**（`accountId:sid` 或 `accountId:default`）。`mergeHistory`/`maxServerId` 需按 `(accountId, sid)` 分区。`clearSession` 删除账户时级联 `账户id:%`（LIKE 前缀）。

### 状态（`lib/providers/chat_provider.dart`）

- `ChatState` 增加：`List<ChatSession> sessions`、`String currentSessionId`、`String? sessionsError`。
- 关键不变式：**一条 SSE 流、一套 `_http`/`_pendingQueue`/`_inflightTextCreatedAt` 只属于当前 `(账户, 会话)`**。切会话 = `connect()` 用 `stream?session_id=<sid>` 重建（现有 `ActiveConnection` 代际守卫已防旧流串扰）。SSE 事件解析新增 `session_id` 字段：若事件 sid ≠ 当前会话 sid，**丢弃**（防其它设备/会话事件串台）。
- `connect()`：load 账户 → **拉权威会话列表** → 切到每账户记住的当前会话（或 default）→ auth → `GET /sessions` → `GET /history?session_id=<sid>`（**带会话参数**）→ `stream?session_id=<sid>` → 本地 DB 立即展示。
- 会话 CRUD（`createSession`/`renameSession`/`deleteSession`/`selectSession`）走服务端 API，成功后更新本地镜像 + `connect()` 重建连接。

### UI（`lib/widgets/account_drawer.dart` + `lib/screens/chat_screen.dart`）

- 两级抽屉：账户列表（现有）→ 点账户 → **会话面板**（标题含账户名 + 返回键）。会话面板：列表（名称 + 相对时间）+ 「新建会话」按钮 + 每项长按/菜单（重命名/删除）。
- 进入会话面板时拉 `sessions`（连接已带权威列表则直接用）。切换会话 → `selectSession(sid)` → 重建连接。
- 默认会话不可删除（删除按钮置灰/隐藏）。

---

## 四、边界与降级

- **老客户端**：不发 `session_id` → 默认会话，行为与现状一致。
- **服务器无 `/sessions`**（旧插件版本，404）：app 本地降级单会话（`default`），会话面板不出现；连接照旧。404 检测：dio 捕获 statusCode 404。
- **默认会话不可删**；`session_id` 无效 → 400/404 明确报错。
- **离线**：会话面板可显示本地镜像（prefs）+ 已缓存消息；操作（增删改/切换）落本地，重连后同步（服务端为准，本地覆盖被拒即回滚 UI）。
- **SSE 断连重连**：按当前 `(token, sid)` 重建，`sinceCursor` 用该会话本地 `maxServerId`。
- 每账户会话数上限 25（与账户上限一致，服务端+客户端双重校验）。
- 越权：`session_id` 必须属于该 token；不存在则 404（不泄露其它 token 的会话存在性）。

---

## 五、测试

### 服务端（pytest，现有 conftest 模式）

- `test_sessions_api.py`：CRUD（含默认会话幂等 ensure、不可删默认）、rename 边界、name 长度/空校验。
- `test_sessions_routing.py`：`/message?session_id` 路由到正确 conversation（fake conversation_manager 断言 `switch_conversation`/umo）；会话 umo 格式。
- `test_sessions_history.py`：分会话历史独立（不同 sid 不同 user_id）；`/history?session_id` 过滤。
- `test_sessions_sse.py`：`_sse_clients[scoped_key]` 分区；事件带 `session_id`；默认会话兼容（不带 sid 事件 `session_id=""`）。
- `test_sessions_admin.py`：Web 路由 + 下钻会话列表。

### App（flutter test，沿用 buildClient/buildHttp seam）

- `test_session_store_test.dart`：session store CRUD/持久化/每账户当前会话。
- `test_cache_session_partition_test.dart`：DB 迁移 re-key（旧行→`accountid:default`）、分会话 getMessages/mergeHistory/maxServerId 隔离、clearSession LIKE 级联。
- `test_chat_session_provider_test.dart`：切会话重建连接、SSE 事件 sid 过滤、服务器 404 降级单会话、默认会话兼容。

---

## 六、兼容性 / 版本

- **版本下限**：AstrBot ≥ 4.10.0（`ConversationManager` 多会话 API 的验证版本）。插件 `metadata.yaml` 未声明核心版本约束；本设计不要求升级核心。
- 插件版本 → 次版本升（如 v2.x）；App 版本 → `1.8.0` 语义级（`pubspec.yaml` version bump）。
- 无数据库 schema 破坏（`session_id` 列已存在）；仅语义 re-key（幂等）。
