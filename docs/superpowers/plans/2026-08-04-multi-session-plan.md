# 单账户多会话（Multi-Session）实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为每个账户（token）增加多个命名会话（会话），支持增/删/改名/切换；服务端为权威源，会话与消息跨 app 设备同步；Web 管理平台可管理会话。

**Architecture:** 服务端在每个 token 下维护一个权威会话列表（存插件 config），每个会话用「会话作用域 umo」（`{pid}:FriendMessage:{token}:{sid}`）获得独立的 AstrBot 对话上下文与历史；app 本地 DB 已存在的 `session_id` 列从 `=账户id` 重键为 `=账户id:会话id`。Phone API 增加会话 CRUD，既有 `/message` `/stream` `/history` 增加可选 `session_id`。Web 账户表下钻到会话列表。

**Tech Stack:** Python (Quart + asyncio + pytest) · Flutter/Dart (Riverpod + sqflite + flutter_test) · 静态 HTML/JS 管理页

## Global Constraints

（来自已批准 spec `docs/superpowers/specs/2026-08-04-multi-session-design.md`）

- **会话作用域键**：默认会话（`default`）用无后缀 `umo={pid}:FriendMessage:{token}` / `user_id={token}` / `SSE key={token}`；其它会话（`sid`）用 `umo={pid}:FriendMessage:{token}:{sid}` / `user_id={token}:{sid}` / `SSE key={token}:{sid}`。
- **默认会话 id 固定 `default`**，每 token 隐式首个（只读派生，不写存储），**不可删除**（可改名）。存量历史零迁移。
- **服务端权威**：会话列表存插件 config（`sessions: {token: [{id,name,created_at}, ...]}`），app/Web 都读写它；不在范围内：双向合并冲突解决。
- **持久化**：会话写操作走 `sessions.py` 模块的 `save_sessions`（同步 `adapter.config` + `adapter.cfg` + `astrbot_config` 平台子树 + `save_config()`），与 `main.py._persist_account_state` 同模式。**Phone API 路由层（routes.py）不得 import main.py（避免循环依赖）**——共享逻辑放 `sessions.py` 或 adapter。
- **SSE 事件体新增 `session_id` 字段**：默认会话广播 → 空串 `""`；其余 → `sid`。
- **App 本地 DB**：`session_id` 由 `=账户id` 变为 `=账户id:会话id`（默认会话 `=账户id:default`）；迁移幂等：`UPDATE messages SET session_id = session_id || ':default' WHERE session_id IS NOT NULL AND instr(session_id, ':') = 0`（账户 id 为 base36+计数器，不含冒号）。
- **App UI**：两级抽屉（账户列表 → 点账户 → 会话面板，可返回）；会话面板支持新建/重命名/删除；默认会话删除按钮隐藏/置灰。
- **App 降级**：服务器无 `/sessions`（404）→ 单会话模式（只有 `default`），会话面板不出现。
- **Web**：账户表「对话」下钻到会话列表；chat/history/clear 请求体加 `session_id`。
- **版本**：AstrBot ≥ 4.10.0；插件版本 → v2.x；App → `1.8.0`。
- **兼容**：老客户端（不发 `session_id`）→ 默认会话，行为与现状一致。
- **越权**：`session_id` 必须属于该 token；不存在则 404。
- 每账户会话数上限 25（服务端+客户端双重校验）。
- 不修改 AstrBot 核心；不修改既有单会话行为。

---

## 文件结构

### 服务端（`astrbot_plugin_botapi/`）

| 文件 | 职责 |
|---|---|
| `sessions.py`（新建） | 会话纯逻辑 + 持久化：`DEFAULT_SESSION_ID/NAME`、`MAX_SESSIONS`、`sessions_list`、`save_sessions`、`umo_for`、`scoped_key_for`、`resolve_sid`、`delete_session`（联 cleared SSE/conversation） |
| `models.py` | `BotApiConfig` 增加 `sessions: dict` 字段 |
| `adapter.py` | `BotApiAdapter.__init__` 传 `sessions` 给 config/cfg；`_push_media`/`send_by_session` 用 scoped_key + session_id |
| `routes.py` | `submit_inbound` 加 `session_id`；`/sessions` REST 端点；`/stream` `/history` 加 `session_id`；`_sse_clients` 用 scoped_key |
| `event.py` | `BotApiMessageEvent` 增加 `self.sid`；`_broadcast` 投 scoped_key 并带 session_id |
| `history.py` | `get_conversation_messages` 调用方传 scoped_key（函数本身不改） |
| `main.py` | Web 会话路由注册 + `_do_*` 会话处理 + `_do_chat/_do_history/_do_clear` 加 `session_id` + stats/disconnect/delete 的 scoped-key 聚合 |
| `pages/dashboard/app.js` `index.html` | Web 会话列表下钻 |

### App（`astrbot-app/`）

| 文件 | 职责 |
|---|---|
| `lib/models/chat_session.dart`（新建） | `ChatSession{id, name}` + copyWith + toJson/fromJson |
| `lib/services/session_store.dart`（新建） | `SessionStore`（仿 `AccountStore`）：每账户会话列表 + 当前会话的 prefs 持久化 |
| `lib/services/botapi_http.dart` | `BotApiHttp` 增加 `sessionId` 字段；`/sessions` CRUD 方法；`fetchHistory`/`sendMessage` 带 session_id |
| `lib/services/botapi_client.dart` | `BotApiClient` 增加 `sessionId` 字段；`connect` 带 `session_id` query |
| `lib/models/botapi_event.dart` | `BotApiEvent` 增加 `sessionId` 字段 |
| `lib/services/cache_service.dart` | 迁移 re-key；`clearSession` LIKE 前缀级联 |
| `lib/providers/chat_provider.dart` | `ChatState` 增加 sessions/currentSessionId；`connect` 拉权威会话列表；会话 CRUD；SSE 事件 sid 过滤；`_cacheKey` |
| `lib/widgets/account_drawer.dart` | 两级抽屉：账户 → 会话面板 |
| `lib/screens/chat_screen.dart` | 会话面板 UI（新建/改名/删除） |
| `test/` | 各新测试文件 |

---

### Task 1: 服务端 — sessions.py 模块 + BotApiConfig 字段

**Files:**
- Create: `astrbot_plugin_botapi/sessions.py`
- Modify: `astrbot_plugin_botapi/models.py`
- Modify: `astrbot_plugin_botapi/adapter.py`（`__init__` 传 sessions）
- Test: `astrbot_plugin_botapi/tests/test_sessions_storage.py`（新建）

**Interfaces:**
- Consumes: 既有 `BotApiConfig`、`BotApiAdapter`、`astrbot.core.astrbot_config`（adapter.py 已 import）
- Produces（`sessions.py` 模块级函数，全部接受 `adapter` 以取 `platform_id`/`config`）:
  - `DEFAULT_SESSION_ID = "default"`、`DEFAULT_SESSION_NAME = "默认会话"`、`MAX_SESSIONS = 25`
  - `sessions_list(adapter, token) -> list[dict]`（含默认在最前；**只读派生**，不改存储）
  - `save_sessions(adapter, token, sessions) -> None`（config+cfg+astrbot_config 平台子树+save_config）
  - `umo_for(adapter, token, sid) -> str`、`scoped_key_for(adapter, token, sid) -> str`
  - `resolve_sid(adapter, token, sid_str) -> str`（缺省/空/`default`→`"default"`；未知 raise `LookupError`）
  - `sse_queues_for(adapter, token) -> list`（聚合 token 及 `token:*` 全部 SSE 队列）
  - `async delete_session(adapter, token, sid) -> None`（删 conversation + 断 SSE + save_sessions）
  - `BotApiConfig.sessions: dict` 字段

- [ ] **Step 1: 写失败测试**（`tests/test_sessions_storage.py`）

```python
# tests/test_sessions_storage.py
from types import SimpleNamespace
import pytest

from astrbot_plugin_botapi.models import BotApiConfig
from astrbot_plugin_botapi import sessions as S


def _adapter(monkeypatch, sessions=None):
    from astrbot_plugin_botapi.adapter import BotApiAdapter
    _abs = BotApiAdapter.__abstractmethods__
    BotApiAdapter.__abstractmethods__ = frozenset()
    try:
        a = object.__new__(BotApiAdapter)
    finally:
        BotApiAdapter.__abstractmethods__ = _abs
    a.platform_id = "botapi"
    a.config = {"id": "botapi", "tokens": ["tok"], "nicknames": {}, "sessions": sessions or {}}
    a.cfg = SimpleNamespace(tokens=["tok"], nicknames={}, sessions=sessions or {})
    a._sse_clients = {}
    a._token_to_origin = {}
    fake_cfg = {"platform": [{"id": "botapi", "sessions": sessions or {}}]}
    monkeypatch.setattr(S, "astrbot_config", fake_cfg)
    return a


def test_config_has_sessions_field():
    c = BotApiConfig()
    assert hasattr(c, "sessions")
    assert c.sessions == {}


def test_sessions_list_derives_default_first():
    a = _adapter()
    s = S.sessions_list(a, "tok")
    assert s[0]["id"] == S.DEFAULT_SESSION_ID
    assert s[0]["name"] == "默认会话"
    assert len(s) == 1
    # 不改存储
    assert a.config["sessions"] == {}


def test_sessions_list_keeps_existing_after_default():
    a = _adapter(sessions={"tok": [{"id": "abc", "name": "工作", "created_at": 1}]})
    ids = [x["id"] for x in S.sessions_list(a, "tok")]
    assert ids == ["default", "abc"]


def test_umo_and_scoped_key():
    a = _adapter()
    assert S.umo_for(a, "tok", "default") == "botapi:FriendMessage:tok"
    assert S.umo_for(a, "tok", "abc123") == "botapi:FriendMessage:tok:abc123"
    assert S.scoped_key_for(a, "tok", "default") == "tok"
    assert S.scoped_key_for(a, "tok", "abc123") == "tok:abc123"


def test_resolve_sid():
    a = _adapter(sessions={"tok": [{"id": "abc", "name": "x", "created_at": 1}]})
    assert S.resolve_sid(a, "tok", "") == "default"
    assert S.resolve_sid(a, "tok", None) == "default"
    assert S.resolve_sid(a, "tok", "default") == "default"
    assert S.resolve_sid(a, "tok", "abc") == "abc"
    with pytest.raises(LookupError):
        S.resolve_sid(a, "tok", "nope")


def test_save_sessions_persists_config_cfg_global(monkeypatch):
    a = _adapter()
    S.save_sessions(a, "tok", [{"id": "abc", "name": "工作", "created_at": 1}])
    assert a.config["sessions"]["tok"][0]["id"] == "abc"
    assert a.cfg.sessions["tok"][0]["id"] == "abc"
    # astrobot_config 平台子树被更新
    assert S.astrbot_config["platform"][0]["sessions"]["tok"][0]["name"] == "工作"


def test_sse_queues_for_aggregates_scoped():
    import asyncio
    a = _adapter()
    a._sse_clients = {
        "tok": [asyncio.Queue(maxsize=1)],
        "tok:abc": [asyncio.Queue(maxsize=1)],
        "other": [asyncio.Queue(maxsize=1)],
    }
    assert len(S.sse_queues_for(a, "tok")) == 2


@pytest.mark.asyncio
async def test_delete_session_removes_and_saves():
    a = _adapter(sessions={"tok": [{"id": "abc", "name": "x", "created_at": 1}]})
    calls = []

    class FakeCM:
        async def delete_conversations_by_user_id(self, umo):
            calls.append(umo)

    from astrbot_plugin_botapi.runtime import runtime
    rt = runtime()
    rt.conversation_manager = FakeCM()
    await S.delete_session(a, "tok", "abc")
    assert calls == ["botapi:FriendMessage:tok:abc"]
    assert S.sessions_list(a, "tok") == [] or all(
        x["id"] != "abc" for x in S.sessions_list(a, "tok"))
```

- [ ] **Step 2: 运行测试验证失败**

Run: `cd astrbot_plugin_botapi && python -m pytest tests/test_sessions_storage.py -v`
Expected: FAIL（模块不存在 / 字段不存在）

- [ ] **Step 3: 实现最小代码**

`models.py` 增加字段：

```python
@dataclass
class BotApiConfig:
    host: str = "0.0.0.0"
    port: int = 9000
    tokens: list = field(default_factory=list)
    nicknames: dict = field(default_factory=dict)   # {token: 昵称}，仅管理展示用
    sessions: dict = field(default_factory=dict)    # {token: [{id,name,created_at}, ...]}
```

`sessions.py`（新建）：

```python
# sessions.py — 会话元数据纯逻辑 + 持久化（服务端权威源）
import time

from astrbot.core import astrbot_config

from .runtime import runtime

DEFAULT_SESSION_ID = "default"
DEFAULT_SESSION_NAME = "默认会话"
MAX_SESSIONS = 25


def sessions_list(adapter, token: str) -> list:
    """某 token 的会话列表（含默认在最前）。只读派生，不改存储。"""
    raw = (adapter.config.get("sessions") or {}).get(token, [])
    lst = list(raw)
    if not lst or lst[0].get("id") != DEFAULT_SESSION_ID:
        lst = [{
            "id": DEFAULT_SESSION_ID,
            "name": DEFAULT_SESSION_NAME,
            "created_at": 0,
        }] + [x for x in lst if x.get("id") != DEFAULT_SESSION_ID]
    return lst


def save_sessions(adapter, token: str, sessions: list) -> None:
    """写会话列表：adapter.config + adapter.cfg + astrbot_config 平台子树 + save_config。"""
    all_s = dict(adapter.config.get("sessions") or {})
    all_s[token] = list(sessions)
    adapter.config["sessions"] = all_s
    try:
        adapter.cfg.sessions = all_s
    except Exception:
        pass
    for p in astrbot_config.get("platform", []):
        if p.get("id") == adapter.config.get("id"):
            p["sessions"] = all_s
            break
    astrbot_config.save_config()


def umo_for(adapter, token: str, sid: str) -> str:
    base = f"{adapter.platform_id}:FriendMessage:{token}"
    if sid in ("", DEFAULT_SESSION_ID):
        return base
    return f"{base}:{sid}"


def scoped_key_for(adapter, token: str, sid: str) -> str:
    if sid in ("", DEFAULT_SESSION_ID):
        return token
    return f"{token}:{sid}"


def resolve_sid(adapter, token: str, sid_str) -> str:
    """解析请求里的 session_id：缺省/空/default → 'default'；校验属于该 token。"""
    sid = (sid_str or "").strip() or DEFAULT_SESSION_ID
    known = {x["id"] for x in sessions_list(adapter, token)}
    if sid not in known:
        raise LookupError(f"unknown session: {sid}")
    return sid


def sse_queues_for(adapter, token: str) -> list:
    """聚合某 token 全部会话的 SSE 队列（token 及 token:*）。"""
    out = []
    prefix = f"{token}:"
    for key, queues in list(getattr(adapter, "_sse_clients", {}).items()):
        if key == token or key.startswith(prefix):
            out.extend(queues)
    return out


async def delete_session(adapter, token: str, sid: str) -> None:
    """删除会话：删 conversation（含会话 umo）+ 断 SSE + 从存储移除。"""
    scoped_umo = umo_for(adapter, token, sid)
    cm = runtime().conversation_manager
    if cm is not None:
        try:
            await cm.delete_conversations_by_user_id(scoped_umo)
        except Exception:
            pass
    scoped = scoped_key_for(adapter, token, sid)
    for q in list(getattr(adapter, "_sse_clients", {}).get(scoped, [])):
        adapter._put(q, None)
    remaining = [x for x in sessions_list(adapter, token) if x["id"] != sid]
    save_sessions(adapter, token, remaining)
```

`adapter.py` `__init__` 传 sessions：

```python
        self.cfg = BotApiConfig(
            host=platform_config.get("host", "0.0.0.0"),
            port=int(platform_config.get("port", 9000)),
            tokens=list(platform_config.get("tokens", [])),
            nicknames=dict(platform_config.get("nicknames", {})),
            sessions=dict(platform_config.get("sessions", {})),
        )
```

- [ ] **Step 4: 运行测试验证通过**

Run: `cd astrbot_plugin_botapi && python -m pytest tests/test_sessions_storage.py -v`
Expected: PASS（9 tests）

- [ ] **Step 5: 提交**

```bash
git add tests/test_sessions_storage.py sessions.py models.py adapter.py
git commit -m "feat(server): sessions 模块（列表/持久化/scoped key）+ BotApiConfig 字段"
```

---

### Task 2: 服务端 — Phone API 会话 CRUD（routes.py）

**Files:**
- Modify: `astrbot_plugin_botapi/routes.py`
- Test: `astrbot_plugin_botapi/tests/test_sessions_api.py`（新建）

**Interfaces:**
- Consumes: Task 1 的 `sessions_list/save_sessions/resolve_sid/MAX_SESSIONS`
- Produces: `/sessions` 四个端点（GET 列表 / POST 新建 / POST `<sid>/rename` / POST `<sid>/delete`）

- [ ] **Step 1: 写失败测试**（`tests/test_sessions_api.py`）

```python
# tests/test_sessions_api.py
from types import SimpleNamespace
import pytest
from astrbot_plugin_botapi import sessions as S


def _adapter(monkeypatch):
    from astrbot_plugin_botapi.adapter import BotApiAdapter
    _abs = BotApiAdapter.__abstractmethods__
    BotApiAdapter.__abstractmethods__ = frozenset()
    try:
        a = object.__new__(BotApiAdapter)
    finally:
        BotApiAdapter.__abstractmethods__ = _abs
    a.platform_id = "botapi"
    a.config = {"id": "botapi", "tokens": ["tok"], "nicknames": {}, "sessions": {}}
    a.cfg = SimpleNamespace(tokens=["tok"], nicknames={}, sessions={})
    a._sse_clients = {}
    a._token_to_origin = {}
    a._put = lambda q, e: None
    fake_cfg = {"platform": [{"id": "botapi", "sessions": {}}]}
    monkeypatch.setattr(S, "astrbot_config", fake_cfg)
    return a


def test_create_session_appends():
    a = _adapter()
    s = S.sessions_list(a, "tok")
    s.append({"id": "abc", "name": "工作", "created_at": 2})
    S.save_sessions(a, "tok", s)
    names = [x["name"] for x in S.sessions_list(a, "tok")]
    assert names == ["默认会话", "工作"]
```

（端点测试用 Quart test_client 模式，参照 `tests/test_routes_stream.py::_make_adapter`。断言：GET `/sessions` 返回列表含默认；POST `/sessions` 建会话；POST `<sid>/rename` 改名；POST `<sid>/delete` 移除且默认不可删返回 400。）

- [ ] **Step 2: 运行测试验证失败**

Run: `cd astrbot_plugin_botapi && python -m pytest tests/test_sessions_api.py -v`
Expected: FAIL（端点未注册）

- [ ] **Step 3: 实现最小代码**

`routes.py` `_setup_routes` 内增加（`/history` 之后）：

```python
    @app.get("/api/v1/botapi/sessions")
    async def list_sessions():
        token = _extract_token(adapter)
        return jsonify({"sessions": _sessions_list(adapter, token),
                        "default_id": _sessions.DEFAULT_SESSION_ID})

    @app.post("/api/v1/botapi/sessions")
    async def create_session():
        token = _extract_token(adapter)
        data = await request.get_json() or {}
        name = (data.get("name") or "").strip()
        if not name:
            return jsonify({"error": "name_required"}), 400
        cur = _sessions.sessions_list(adapter, token)
        if len(cur) >= _sessions.MAX_SESSIONS:
            return jsonify({"error": "session_limit"}), 400
        new = {"id": uuid.uuid4().hex[:12], "name": name,
               "created_at": int(time.time())}
        cur.append(new)
        _sessions.save_sessions(adapter, token, cur)
        return jsonify({"session": new})

    @app.post("/api/v1/botapi/sessions/<sid>/rename")
    async def rename_session(sid):
        token = _extract_token(adapter)
        data = await request.get_json() or {}
        name = (data.get("name") or "").strip()
        if not name:
            return jsonify({"error": "name_required"}), 400
        cur = _sessions.sessions_list(adapter, token)
        for x in cur:
            if x["id"] == sid:
                x["name"] = name
                _sessions.save_sessions(adapter, token, cur)
                return jsonify({"message": "会话已重命名"})
        return jsonify({"error": "not_found"}), 404

    @app.post("/api/v1/botapi/sessions/<sid>/delete")
    async def delete_session(sid):
        token = _extract_token(adapter)
        if sid == _sessions.DEFAULT_SESSION_ID:
            return jsonify({"error": "default_not_deletable"}), 400
        if not any(x["id"] == sid for x in _sessions.sessions_list(adapter, token)):
            return jsonify({"error": "not_found"}), 404
        await _sessions.delete_session(adapter, token, sid)
        return jsonify({"message": "会话已删除"})
```

`routes.py` 顶部 import：`from . import sessions as _sessions`（`sessions_list` 直接 `_sessions.sessions_list`；无需本文件包一层）。`/message` 端点 body 增加 `session_id`（在 `submit_inbound` 处理，见 Task 3）。

- [ ] **Step 4: 运行测试验证通过**

Run: `cd astrbot_plugin_botapi && python -m pytest tests/test_sessions_api.py -v`
Expected: PASS

- [ ] **Step 5: 提交**

```bash
git add tests/test_sessions_api.py routes.py
git commit -m "feat(server): Phone API 会话 CRUD"
```

---

### Task 3: 服务端 — 消息/流/历史带 session_id 路由

**Files:**
- Modify: `astrbot_plugin_botapi/routes.py`
- Modify: `astrbot_plugin_botapi/event.py`
- Modify: `astrbot_plugin_botapi/history.py`（仅调用方传参，不改函数签名）
- Test: `astrbot_plugin_botapi/tests/test_sessions_routing.py`（新建）

**Interfaces:**
- Consumes: Task 1 的 `umo_for/scoped_key_for/resolve_sid`
- Produces:
  - `submit_inbound(adapter, token, text, file_ids=None, session_id="")`（`msg.session_id = umo_for(token, sid)`）
  - `BotApiMessageEvent.sid` 属性；`_broadcast` 投 `scoped_key_for` 并带 `session_id`
  - `/stream` `/history` 解析 `session_id`

- [ ] **Step 1: 写失败测试**（`tests/test_sessions_routing.py`）

```python
# tests/test_sessions_routing.py
from types import SimpleNamespace
import pytest
from astrbot_plugin_botapi import sessions as S


def _adapter(monkeypatch):
    from astrbot_plugin_botapi.adapter import BotApiAdapter
    _abs = BotApiAdapter.__abstractmethods__
    BotApiAdapter.__abstractmethods__ = frozenset()
    try:
        a = object.__new__(BotApiAdapter)
    finally:
        BotApiAdapter.__abstractmethods__ = _abs
    a.platform_id = "botapi"
    a.config = {"id": "botapi", "tokens": ["tok"], "nicknames": {}, "sessions": {}}
    a.cfg = SimpleNamespace(tokens=["tok"], nicknames={}, sessions={})
    a._sse_clients = {}
    a._token_to_origin = {}
    a.client_self_id = "self"
    a._uploaded_files = {}
    a._serializer = SimpleNamespace()
    a.commit_event = lambda e: None
    monkeypatch.setattr(S, "astrbot_config", {"platform": []})
    return a


@pytest.mark.asyncio
async def test_submit_inbound_routes_to_session(monkeypatch):
    from astrbot_plugin_botapi import routes as routes_mod
    a = _adapter(monkeypatch)
    captured = {}

    async def fake_persist(key, mid, text):
        captured["key"] = key

    monkeypatch.setattr(routes_mod, "persist_inbound_text", fake_persist)

    def fake_commit(event):
        captured["session_id"] = event.message_obj.session_id
        captured["sender"] = event.message_obj.sender.user_id

    a.commit_event = fake_commit
    await routes_mod.submit_inbound(a, "tok", "hi")
    assert captured["session_id"] == "botapi:FriendMessage:tok"
    assert captured["sender"] == "tok"
    assert captured["key"] == "tok"


@pytest.mark.asyncio
async def test_submit_inbound_scoped_sid(monkeypatch):
    from astrbot_plugin_botapi import routes as routes_mod
    a = _adapter(monkeypatch)
    cur = S.sessions_list(a, "tok")
    cur.append({"id": "abc", "name": "x", "created_at": 1})
    S.save_sessions(a, "tok", cur)
    captured = {}

    async def fake_persist(key, mid, text):
        captured["key"] = key

    monkeypatch.setattr(routes_mod, "persist_inbound_text", fake_persist)

    def fake_commit(event):
        captured["session_id"] = event.message_obj.session_id

    a.commit_event = fake_commit
    await routes_mod.submit_inbound(a, "tok", "hi", session_id="abc")
    assert captured["session_id"] == "botapi:FriendMessage:tok:abc"
    assert captured["key"] == "tok:abc"


@pytest.mark.asyncio
async def test_event_broadcast_carries_session_id(monkeypatch):
    from astrbot_plugin_botapi.event import BotApiMessageEvent
    from astrbot_plugin_botapi.models import SSEEvent
    a = _adapter(monkeypatch)
    a._sse_clients = {}
    q = __import__("asyncio").Queue(maxsize=10)
    a._sse_clients["tok:abc"] = [q]

    async def fake_broadcast(scoped, evt):
        a._sse_clients[scoped][0].put_nowait(evt)

    # 用最小 fake message_obj
    msg = SimpleNamespace(sender=SimpleNamespace(user_id="tok"))
    ev = BotApiMessageEvent("hi", msg, SimpleNamespace(), "botapi:FriendMessage:tok:abc", a)
    assert ev.sid == "abc"
```

- [ ] **Step 2: 运行测试验证失败**

Run: `cd astrbot_plugin_botapi && python -m pytest tests/test_sessions_routing.py -v`
Expected: FAIL（`submit_inbound` 无 `session_id`；event 无 `sid`）

- [ ] **Step 3: 实现最小代码**

`routes.py` 修改 `submit_inbound`：

```python
async def submit_inbound(adapter, token, text, file_ids=None, session_id="") -> str:
    """构造入站 AstrBotMessage + BotApiMessageEvent，persist + commit。
    手机 /message 与管理页 /chat 共用。session_id 缺省/空 → 默认会话。"""
    sid = _sessions.resolve_sid(adapter, token, session_id)
    scoped_umo = _sessions.umo_for(adapter, token, sid)
    scoped_key = _sessions.scoped_key_for(adapter, token, sid)
    _get_or_create_origin(adapter, token)
    msg = AstrBotMessage()
    msg.type = MessageType.FRIEND_MESSAGE
    msg.self_id = adapter.client_self_id
    msg.session_id = scoped_umo   # 路由到正确会话的关键
    msg.message_id = f"botapi_{uuid.uuid4().hex[:12]}"
    msg.sender = MessageMember(user_id=token, nickname="User")
    msg.timestamp = int(time.time())
    components = []
    if text:
        components.append(Plain(text))
    if file_ids:
        for fid in file_ids:
            info = adapter._uploaded_files.get(fid)
            if info:
                components.append(_file_info_to_component(info))
    msg.message = components
    msg.message_str = text or "[消息]"
    msg.raw_message = {"text": text, "file_ids": file_ids or []}

    event = BotApiMessageEvent(message_str=msg.message_str, message_obj=msg,
                               platform_meta=adapter.meta(), session_id=scoped_umo,
                               adapter=adapter)
    event.set_extra("enable_streaming", True)
    await persist_inbound_text(scoped_key, msg.message_id, text)
    adapter.commit_event(event)
    return msg.message_id
```

`event.py` 修改：

```python
class BotApiMessageEvent(AstrMessageEvent):
    def __init__(self, message_str, message_obj, platform_meta, session_id, adapter):
        super().__init__(message_str, message_obj, platform_meta, session_id)
        self.adapter = adapter
        self.token = message_obj.sender.user_id
        # session_id 形如 {pid}:FriendMessage:{token}[:{sid}]
        parts = (session_id or "").split(":")
        self.sid = parts[3] if len(parts) > 3 else "default"
        self._text_buf: list = []

    async def _broadcast(self, evt: SSEEvent):
        scoped = self.adapter.scoped_key_for(self.token, self.sid)
        evt.data = dict(evt.data or {})
        evt.data["session_id"] = "" if self.sid == "default" else self.sid
        await self.adapter._broadcast_to(scoped, evt)
```

注意：`send()`/`send_streaming()` 已调用 `self._broadcast`（自动带 session_id）。但 `send()` 内 `await self.adapter._push_media(message, self.token, mid)` 需带 `self.sid`（Task 4 改签名后调用方同步）。

`routes.py` `/message` body 取 `session_id`：

```python
    @app.post("/api/v1/botapi/message")
    async def send_message():
        token = _extract_token(adapter)
        data = await request.get_json()
        text = (data or {}).get("text", "")
        file_ids = (data or {}).get("file_ids", [])
        session_id = (data or {}).get("session_id", "")
        message_id = await submit_inbound(adapter, token, text, file_ids, session_id)
        return jsonify({"message_id": message_id})
```

`/stream` 与 `/history`：

```python
    @app.get("/api/v1/botapi/stream")
    async def stream():
        from quart import make_response
        token = _extract_token(adapter)
        sid = _sessions.resolve_sid(adapter, token, request.args.get("session_id"))
        scoped = _sessions.scoped_key_for(adapter, token, sid)
        q: asyncio.Queue = asyncio.Queue(maxsize=256)
        adapter._sse_clients[scoped].append(q)
        since = request.args.get("since")
        resp = await make_response(_stream_gen(adapter, scoped, q, since), {
            "Content-Type": "text/event-stream", "Cache-Control": "no-cache",
            "Connection": "keep-alive", "Transfer-Encoding": "chunked",
            "X-Accel-Buffering": "no",
        })
        resp.timeout = None
        return resp

    @app.get("/api/v1/botapi/history")
    async def get_history():
        from . import history as hist_mod
        token = _extract_token(adapter)
        sid = _sessions.resolve_sid(adapter, token, request.args.get("session_id"))
        scoped = _sessions.scoped_key_for(adapter, token, sid)
        since = request.args.get("since")
        before = request.args.get("before")
        limit = min(int(request.args.get("limit", 50)), 200)
        msgs, has_more = await hist_mod.get_history(adapter.platform_id, scoped, since, before, limit)
        return jsonify({"messages": msgs, "has_more": has_more})
```

`_stream_gen(adapter, scoped, q, since)` 的 finally 清理用传入 `scoped` key。

- [ ] **Step 4: 运行测试验证通过**

Run: `cd astrbot_plugin_botapi && python -m pytest tests/test_sessions_routing.py tests/test_routes_stream.py tests/test_routes_history.py tests/test_routes_message.py -v`
Expected: PASS

- [ ] **Step 5: 提交**

```bash
git add tests/test_sessions_routing.py routes.py event.py
git commit -m "feat(server): 消息/流/历史按 session_id 路由到分会话"
```

---

### Task 4: 服务端 — SSE 分区投递 + 媒体推送带会话（adapter.py）

**Files:**
- Modify: `astrbot_plugin_botapi/adapter.py`
- Modify: `astrbot_plugin_botapi/event.py`（`_push_media` 调用带 sid）
- Test: `astrbot_plugin_botapi/tests/test_sessions_sse.py`（新建）

**Interfaces:**
- Consumes: Task 1 的 `scoped_key_for`；Task 3 的 `BotApiMessageEvent.sid`
- Produces: `adapter._push_media(chain, token, message_id, sid="default")`；`adapter.send_by_session` 用 scoped_key + session_id

- [ ] **Step 1: 写失败测试**（`tests/test_sessions_sse.py`）

```python
# tests/test_sessions_sse.py
import asyncio
from types import SimpleNamespace
import pytest
from astrbot_plugin_botapi.adapter import BotApiAdapter
from astrbot_plugin_botapi.models import SSEEvent
from astrbot_plugin_botapi import sessions as S


def _adapter(monkeypatch):
    _abs = BotApiAdapter.__abstractmethods__
    BotApiAdapter.__abstractmethods__ = frozenset()
    try:
        a = object.__new__(BotApiAdapter)
    finally:
        BotApiAdapter.__abstractmethods__ = _abs
    a.platform_id = "botapi"
    a.config = {"id": "botapi", "sessions": {}}
    a.cfg = SimpleNamespace(sessions={})
    a._sse_clients = {}
    a._serializer = SimpleNamespace()
    a._media_enabled = True
    monkeypatch.setattr(S, "astrbot_config", {"platform": []})
    return a


@pytest.mark.asyncio
async def test_broadcast_to_scoped_partitions():
    a = _adapter()
    q_d = asyncio.Queue(maxsize=10)
    q_a = asyncio.Queue(maxsize=10)
    a._sse_clients["tok"] = [q_d]
    a._sse_clients["tok:abc"] = [q_a]
    await a._broadcast_to("tok", SSEEvent("message", {"session_id": ""}))
    await a._broadcast_to("tok:abc", SSEEvent("message", {"session_id": "abc"}))
    assert (await q_d.get()).data["session_id"] == ""
    assert (await q_a.get()).data["session_id"] == "abc"


@pytest.mark.asyncio
async def test_push_media_scoped(monkeypatch):
    from astrbot.api.message_components import Image
    from astrbot.api.event import MessageChain
    a = _adapter()
    q = asyncio.Queue(maxsize=10)
    a._sse_clients["tok:abc"] = [q]

    async def fake_media_url(comp):
        return "https://dash/api/file/x"

    a._serializer._media_url = fake_media_url
    chain = MessageChain([Image.fromFileSystem("/x.png")])
    await a._push_media(chain, "tok", "mid1", sid="abc")
    e = await q.get()
    assert e.data["type"] == "image"
    assert e.data["session_id"] == "abc"
```

- [ ] **Step 2: 运行测试验证失败**

Run: `cd astrbot_plugin_botapi && python -m pytest tests/test_sessions_sse.py -v`
Expected: FAIL（`_push_media` 无 `sid` 参数）

- [ ] **Step 3: 实现最小代码**

`adapter.py` 修改 `send_by_session` 与 `_push_media`：

```python
    async def send_by_session(self, session, message_chain) -> None:
        await super().send_by_session(session, message_chain)
        sess_id = session.session_id  # umo 或 scoped umo
        parts = sess_id.split(":")
        # session_id 形如 {pid}:FriendMessage:{token}[:{sid}]
        token = parts[2] if len(parts) > 2 else sess_id
        sid = parts[3] if len(parts) > 3 else "default"
        mid = f"botapi_proactive_{uuid.uuid4().hex[:12]}"
        payload = await self._serializer.serialize_chain(message_chain, None)
        scoped = self.scoped_key_for(token, sid)
        evt = SSEEvent("message", {**payload, "streaming": False, "final": True,
                                   "session_id": "" if sid == "default" else sid})
        await self._broadcast_to(scoped, evt)
        await self._push_media(message_chain, token, mid, sid)

    async def _push_media(self, chain, token: str, message_id: str, sid="default") -> None:
        if chain is None:
            return
        scoped = self.scoped_key_for(token, sid)
        queues = list(self._sse_clients.get(scoped, []))
        for comp in (chain.chain or []):
            ct = comp.type.value.lower() if hasattr(comp.type, "value") else str(comp.type).lower()
            if ct not in ("image", "record", "file"):
                continue
            mtype = {"image": "image", "record": "audio", "file": "file"}[ct]
            for q in queues:
                url = await self._serializer._media_url(comp)
                if not url:
                    continue
                data = {"message_id": message_id, "type": mtype,
                        "content": ({"name": getattr(comp, "name", "file"), "url": url}
                                    if mtype == "file" else url),
                        "streaming": False, "final": False, "timestamp": int(time.time()),
                        "session_id": "" if sid == "default" else sid}
                self._put(q, SSEEvent("message", data))
```

`adapter.py` 顶部加 `from .sessions import scoped_key_for` 或直接 `from . import sessions as _sessions`（`_push_media` 内 `self.scoped_key_for` 需 adapter 上有该方法——改为 `_sessions.scoped_key_for(self, token, sid)`；`send_by_session` 同理）。

`event.py` 的 `_push_media` 调用点（`send` 与 `send_streaming` 内 `self.adapter._push_media(message, self.token, mid)`）改为 `self.adapter._push_media(message, self.token, mid, self.sid)`。

- [ ] **Step 4: 运行测试验证通过**

Run: `cd astrbot_plugin_botapi && python -m pytest tests/test_sessions_sse.py tests/test_adapter_core.py tests/test_integration_streaming.py tests/test_routes_stream.py -v`
Expected: PASS（既有测试兼容，`sid="default"` 默认参）

- [ ] **Step 5: 提交**

```bash
git add tests/test_sessions_sse.py adapter.py event.py
git commit -m "feat(server): SSE 按会话分区投递 + 媒体带 session_id"
```

---

### Task 5: 服务端 — Web 路由 + 会话清空/删除 + stats/disconnect scoped 聚合

**Files:**
- Modify: `astrbot_plugin_botapi/main.py`
- Modify: `astrbot_plugin_botapi/history.py`（调用方传 scoped_key）
- Test: `astrbot_plugin_botapi/tests/test_sessions_admin.py`（新建）

**Interfaces:**
- Consumes: Task 1 的 `sessions_list/umo_for/scoped_key_for/resolve_sid/sse_queues_for/delete_session`
- Produces:
  - `_do_sessions(token_hash)`、`_do_create_session(token_hash, name)`、`_do_rename_session(token_hash, sid, name)`、`_do_delete_session(token_hash, sid)`
  - `_do_clear(token_hash, session_id="")`（会话 umo 上 `new_conversation`）
  - `_do_chat(token_hash, text, session_id="")`、`_do_history(token_hash, since, limit, session_id="")`
  - `_do_stats/_do_disconnect/_do_delete` 用 `sse_queues_for` 聚合
  - Web 路由注册：`GET/POST sessions/<token_hash>`、`POST sessions/<token_hash>/<sid>/rename`、`POST sessions/<token_hash>/<sid>/delete`

- [ ] **Step 1: 写失败测试**（`tests/test_sessions_admin.py`）

```python
# tests/test_sessions_admin.py
from types import SimpleNamespace
from astrbot_plugin_botapi.main import BotApiStar
from astrbot_plugin_botapi import sessions as S


def test_session_admin_routes_registered():
    registered = []

    class FakeContext:
        conversation_manager = SimpleNamespace()
        message_history_manager = SimpleNamespace()
        def register_web_api(self, route, handler, methods, desc):
            registered.append(route)

    BotApiStar(FakeContext(), None)
    assert any(r.endswith("/sessions/<token_hash>") for r in registered)
    assert any("rename" in r for r in registered)
    assert any("delete" in r for r in registered)


def test_do_clear_uses_scoped_umo(monkeypatch):
    import hashlib
    from astrbot_plugin_botapi import runtime as rt_mod
    tok = "tok"
    th = hashlib.sha256(tok.encode()).hexdigest()[:16]

    class FakeCM:
        async def new_conversation(self, umo):
            self.umo = umo

    cm = FakeCM()
    ctx = SimpleNamespace(conversation_manager=cm, message_history_manager=SimpleNamespace())
    star = BotApiStar(ctx, None)
    monkeypatch.setattr(star, "_persist_account_state", lambda *a, **k: None)
    a = SimpleNamespace(platform_id="botapi",
                        config={"id": "botapi", "tokens": [tok], "nicknames": {}, "sessions": {}},
                        cfg=SimpleNamespace(tokens=[tok], nicknames={}, sessions={}),
                        _sse_clients={}, _disabled_tokens=set(), _last_active={},
                        _put=lambda q, e: None, _token_to_origin={})
    rt = rt_mod.runtime()
    rt.adapter = a
    import asyncio
    asyncio.get_event_loop().run_until_complete(star._do_clear(th, session_id="abc"))
    assert cm.umo == "botapi:FriendMessage:tok:abc"
```

（`_do_create_session/_do_rename_session/_do_delete_session` 的测试参照 `test_admin_handlers.py::_make_star` 模式，断言 config 更新 / `delete_conversations_by_user_id` 被调。）

- [ ] **Step 2: 运行测试验证失败**

Run: `cd astrbot_plugin_botapi && python -m pytest tests/test_sessions_admin.py -v`
Expected: FAIL（路由未注册 / `_do_clear` 无 session_id）

- [ ] **Step 3: 实现最小代码**

`main.py` `__init__` 增加注册：

```python
        context.register_web_api(f"/{P}/sessions/<token_hash>", self._sessions_web, ["GET"], "会话列表")
        context.register_web_api(f"/{P}/sessions/<token_hash>", self._create_session_web, ["POST"], "新建会话")
        context.register_web_api(
            f"/{P}/sessions/<token_hash>/<sid>/rename", self._rename_session_web, ["POST"], "重命名会话"
        )
        context.register_web_api(
            f"/{P}/sessions/<token_hash>/<sid>/delete", self._delete_session_web, ["POST"], "删除会话"
        )
```

`_do_clear` 改（`session_id=""` 可选）：

```python
    async def _do_clear(self, token_hash, session_id=""):
        ...
        target = next((t for t in (adapter.cfg.tokens or []) if self._hash_tok(t) == token_hash), None)
        if not target:
            return Response().error("未找到会话").__dict__
        from . import sessions as _sessions
        sid = _sessions.resolve_sid(adapter, target, session_id)
        umo = _sessions.umo_for(adapter, target, sid)
        await rt.conversation_manager.new_conversation(umo)
        return Response().ok({"message": "历史已清除"}).__dict__
```

新增 `_do_*` 会话方法（参照既有 `_do_*` 模式，用 `_sessions.sessions_list/save_sessions/resolve_sid/delete_session`）。

`_do_stats` / `_do_disconnect` / `_do_delete` 的 SSE 聚合：`online = bool(_sessions.sse_queues_for(adapter, token))`、`sse_connections = len(_sessions.sse_queues_for(adapter, token))`；disconnect/delete 的 `for q in adapter._sse_clients.pop(target, [])` 改为 `for q in _sessions.sse_queues_for(adapter, target)`（保留 `_sse_clients` 各 scoped key 清理——pop 逐个 scoped key）。

`_do_chat`/`_do_history` 加 `session_id`：`submit_inbound(adapter, target, text, session_id=...)` / `get_conversation_messages(rt, pid, scoped_key, limit)`（scoped_key = `_sessions.scoped_key_for(adapter, target, sid)`）。

Web handler 薄封装（`_sessions_web/_create_session_web/_rename_session_web/_delete_session_web`）取参调 `_do_*`。

- [ ] **Step 4: 运行测试验证通过**

Run: `cd astrbot_plugin_botapi && python -m pytest tests/test_sessions_admin.py tests/test_admin_handlers.py tests/test_admin_routing.py tests/test_chat.py tests/test_star.py -v`
Expected: PASS

- [ ] **Step 5: 提交**

```bash
git add tests/test_sessions_admin.py main.py history.py
git commit -m "feat(server): Web 会话路由 + 清空/删除联动 + stats 聚合 scoped key"
```

---

### Task 6: 服务端 — Web 管理页下钻会话

**Files:**
- Modify: `astrbot_plugin_botapi/pages/dashboard/app.js`
- Modify: `astrbot_plugin_botapi/pages/dashboard/index.html`

**Interfaces:**
- Consumes: Task 5 的 Web 路由
- Produces: 无（纯前端）

- [ ] **Step 1: 阅读现有前端结构**

Read: `pages/dashboard/app.js`（`openChat`、`setupChat`、`wireDelegation`）、`index.html`（模态框/表格结构）

- [ ] **Step 2: 实现会话下钻**

`app.js`：
- `openChat(hash, nick)` 改为 `openSessions(hash, nick)`：先 `bridge.apiGet("sessions/<hash>")` → 渲染会话列表（新建/改名/删除/进入）。
- `openChatSession(hash, nick, sid)`：既有 chat 视图，chat/history/clear 请求体加 `session_id: sid`。
- 新增 `createSession/renameSession/deleteSession` 走 `bridge.apiPost`。
- 会话列表容器在 `index.html` 新增 div（复用现有 confirmDialog/promptDialog 模态框）。

- [ ] **Step 3: 手动核对**

检查 `app.js` 无语法错误（`node --check pages/dashboard/app.js`）。

- [ ] **Step 4: 提交**

```bash
git add pages/dashboard/app.js pages/dashboard/index.html
git commit -m "feat(server): Web 管理页下钻会话列表 + 会话 CRUD"
```

---

### Task 7: 服务端 — 全量回归 + 版本 bump

**Files:**
- Modify: `astrbot_plugin_botapi/metadata.yaml`
- Modify: `astrbot_plugin_botapi/CHANGELOG.md`

- [ ] **Step 1: 全量跑测试**

Run: `cd astrbot_plugin_botapi && python -m pytest -v`
Expected: 全部 PASS

- [ ] **Step 2: 版本 bump**

读 `metadata.yaml` 版本（如 `1.x.y`），次版本升（新增主要功能 → `2.x.y`）。`CHANGELOG.md` 增补条目。

- [ ] **Step 3: 提交**

```bash
git add metadata.yaml CHANGELOG.md
git commit -m "chore(server): 多会话功能版本 bump"
```

---

### Task 8: App — ChatSession 模型 + SessionStore + API 会话字段

**Files:**
- Create: `astrbot-app/lib/models/chat_session.dart`
- Create: `astrbot-app/lib/services/session_store.dart`
- Modify: `astrbot-app/lib/services/botapi_http.dart`
- Modify: `astrbot-app/lib/services/botapi_client.dart`
- Test: `astrbot-app/test/session_store_test.dart`（新建）

**Interfaces:**
- Consumes: 既有 `Account`/`AccountStore` 模式
- Produces:
  - `ChatSession{id, name}` + `copyWith` + `toJson`/`fromJson`
  - `SessionStore`（抽象 `SessionStorage`；prefs 键 `sessions_v1`/`current_session_v1`；`kMaxSessionsPerAccount = 25`；`load/list/add/rename/delete/getCurrent/setCurrent`）
  - `SessionApiUnavailable` 异常（服务器 404 `/sessions` 时抛，供降级判断）
  - `BotApiHttp(serverUrl, token, {sessionId = ''})`：`fetchSessions() -> List<ChatSession>`（404 → 抛 `SessionApiUnavailable`）；`sendMessage` body 带 `session_id`；`fetchHistory` query 带 `session_id`
  - `BotApiClient(serverUrl, token, {sessionId = ''})`：`connect` 带 `session_id` query

- [ ] **Step 1: 写失败测试**（`test/session_store_test.dart`）

```dart
// test/session_store_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:astrbot_app/services/session_store.dart';
import 'package:astrbot_app/models/chat_session.dart';

class MemSessionStorage implements SessionStorage {
  final Map<String, String> _m = {};
  @override
  Future<String?> readString(String key) async => _m[key];
  @override
  Future<void> writeString(String key, String value) async { _m[key] = value; }
}

void main() {
  test('add/rename/delete/list', () async {
    final store = SessionStore(MemSessionStorage());
    await store.load();
    await store.add('acc1', '工作');
    final s = await store.list('acc1');
    expect(s!.length, 1);
    expect(s.first.name, '工作');
    await store.rename('acc1', s.first.id, '新名');
    expect((await store.list('acc1'))!.first.name, '新名');
    await store.delete('acc1', s.first.id);
    expect((await store.list('acc1'))!.isEmpty, true);
  });

  test('per-account current session', () async {
    final store = SessionStore(MemSessionStorage());
    await store.load();
    await store.add('acc1', 'A');
    await store.add('acc1', 'B');
    final list = await store.list('acc1');
    await store.setCurrent('acc1', list![1].id);
    expect(await store.getCurrent('acc1'), list[1].id);
    expect(await store.getCurrent('acc2'), null);
  });

  test('cap 25', () async {
    final store = SessionStore(MemSessionStorage());
    await store.load();
    for (var i = 0; i < 26; i++) {
      await store.add('acc1', 's$i');
    }
    expect((await store.list('acc1'))!.length, 25);
  });
}
```

- [ ] **Step 2: 运行测试验证失败**

Run: `cd astrbot-app && flutter test test/session_store_test.dart`
Expected: FAIL（文件不存在）

- [ ] **Step 3: 实现最小代码**

按接口实现 `ChatSession`、`SessionStore`、`SessionApiUnavailable`、`BotApiHttp`/`BotApiClient` 会话字段。`SessionStore` 仿 `AccountStore`（`_ensureLoaded` + prefs JSON 持久化；`list` 返回 `List<ChatSession>?`，无会话返回 `null` 或空列表——测试用空列表 `[]`，但 store 内部需区分「未初始化」与「空」；采用返回空列表 + `add` 时补 `default` 于首）。`BotApiHttp.fetchSessions`：dio GET `$_base/sessions`，404 → `throw SessionApiUnavailable()`；解析 `sessions` 数组。`sendMessage`/`fetchHistory` 仅在 `sessionId.isNotEmpty && sessionId != 'default'` 时带参（`default` 不发，保老服务器兼容）。

- [ ] **Step 4: 运行测试验证通过**

Run: `cd astrbot-app && flutter test test/session_store_test.dart`
Expected: PASS（3 tests）

- [ ] **Step 5: 提交**

```bash
cd astrbot-app && git add lib/models/chat_session.dart lib/services/session_store.dart lib/services/botapi_http.dart lib/services/botapi_client.dart test/session_store_test.dart
git commit -m "feat(app): ChatSession 模型 + SessionStore + API 会话字段"
```

---

### Task 9: App — DB 迁移 re-key + clearSession 级联

**Files:**
- Modify: `astrbot-app/lib/services/cache_service.dart`
- Test: `astrbot-app/test/cache_session_partition_test.dart`（新建）

**Interfaces:**
- Consumes: 既有 `CacheService`（`dbPathOverride`/`resetDbForTesting` seams）
- Produces: `rekeyLegacySessions()`；`_ensureSchema` 调用它；`clearSession(accountId)` LIKE 前缀级联

- [ ] **Step 1: 写失败测试**（`test/cache_session_partition_test.dart`）

```dart
// test/cache_session_partition_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:astrbot_app/services/cache_service.dart';
import 'package:astrbot_app/models/message.dart';

void main() {
  sqfliteFfiInit();
  setUp(() {
    CacheService.dbPathOverride = inMemoryDatabasePath;
    CacheService.resetDbForTesting();
  });
  tearDown(() => CacheService.resetDbForTesting());

  test('legacy rows re-key to :default', () async {
    final c = CacheService();
    final db = await c.db;
    await db.insert('messages', {
      'msg_type': 'text', 'content': 'old', 'is_from_me': 0,
      'status': 'sent', 'created_at': 1, 'session_id': 'acc1',
    });
    await c.rekeyLegacySessions();
    final rows = await db.query('messages', where: 'session_id = ?', whereArgs: ['acc1:default']);
    expect(rows.length, 1);
  });

  test('sessions partition messages', () async {
    final c = CacheService();
    await c.insertMessage(LocalMessage(
      msgType: 'text', content: 'in-default', isFromMe: false,
      status: MessageStatus.sent, createdAt: 1,
    ), accountId: 'acc1:default');
    await c.insertMessage(LocalMessage(
      msgType: 'text', content: 'in-abc', isFromMe: false,
      status: MessageStatus.sent, createdAt: 2,
    ), accountId: 'acc1:abc');
    final def = await c.getMessages(accountId: 'acc1:default');
    final abc = await c.getMessages(accountId: 'acc1:abc');
    expect(def.map((m) => m.content), contains('in-default'));
    expect(def.map((m) => m.content), isNot(contains('in-abc')));
    expect(abc.map((m) => m.content), contains('in-abc'));
  });

  test('clearSession deletes all sessions of account', () async {
    final c = CacheService();
    await c.insertMessage(LocalMessage(
      msgType: 'text', content: 'a', isFromMe: false,
      status: MessageStatus.sent, createdAt: 1,
    ), accountId: 'acc1:default');
    await c.insertMessage(LocalMessage(
      msgType: 'text', content: 'b', isFromMe: false,
      status: MessageStatus.sent, createdAt: 2,
    ), accountId: 'acc1:abc');
    await c.clearSession('acc1');
    expect(await c.getMessageCount(accountId: 'acc1:default'), 0);
    expect(await c.getMessageCount(accountId: 'acc1:abc'), 0);
  });
}
```

- [ ] **Step 2: 运行测试验证失败**

Run: `cd astrbot-app && flutter test test/cache_session_partition_test.dart`
Expected: FAIL（无 `rekeyLegacySessions`；`clearSession` 不级联）

- [ ] **Step 3: 实现最小代码**

`cache_service.dart`：
- `_ensureSchema` 末尾调用 `await rekeyLegacySessions()`。
- 新方法：

```dart
  /// 幂等 re-key：session_id 语义从「账户id」升级为「账户id:会话id」。
  /// 账户 id 不含冒号（base36+计数器），故 instr(session_id, ':')=0 精准匹配旧行。
  Future<void> rekeyLegacySessions() async {
    final d = await db;
    await d.rawUpdate(
        "UPDATE messages SET session_id = session_id || ':default' "
        "WHERE session_id IS NOT NULL AND instr(session_id, ':') = 0");
  }
```

- `clearSession` 改 LIKE 前缀：

```dart
  Future<void> clearSession(String accountId) async {
    final d = await db;
    await d.delete('messages',
        where: 'session_id = ? OR session_id LIKE ?',
        whereArgs: [accountId, '$accountId:%']);
  }
```

- 既有方法签名保持 `accountId` 参数名（语义为 scoped key），调用方传 `账户id:会话id`；`getMessageCount`/`maxServerId` 等继续 `=` 精确匹配（天然分区）。

- [ ] **Step 4: 运行测试验证通过**

Run: `cd astrbot-app && flutter test test/cache_session_partition_test.dart`
Expected: PASS（3 tests）

- [ ] **Step 5: 提交**

```bash
cd astrbot-app && git add lib/services/cache_service.dart test/cache_session_partition_test.dart
git commit -m "feat(app): DB session_id 重键为 account:sid + clearSession 级联"
```

---

### Task 10: App — ChatState 会话字段 + connect 拉权威会话列表 + SSE sid 过滤

**Files:**
- Modify: `astrbot-app/lib/providers/chat_provider.dart`
- Modify: `astrbot-app/lib/models/botapi_event.dart`
- Test: `astrbot-app/test/chat_session_provider_test.dart`（新建）

**Interfaces:**
- Consumes: Task 8 的 `BotApiHttp.fetchSessions`/`SessionApiUnavailable`、`BotApiClient.sessionId`；Task 9 的 scoped key 语义
- Produces:
  - `ChatState.sessions: List<ChatSession>`、`currentSessionId: String`、`sessionsError: String?`
  - `connect()` 流程：load 账户 → 拉权威会话列表（404 降级单会话）→ 恢复每账户当前会话 → auth → history(session_id) → stream(session_id)
  - `selectSession/createSession/renameSession/deleteSession`
  - `_cacheKey = '${_accounts.currentId}:${state.currentSessionId}'`（currentSessionId 默认 `'default'`）
  - `_handleEvent` 开头按 `event.sessionId` 过滤
  - `deleteAccount` 级联清 `SessionStore` 该账户条目
  - `BotApiEvent.sessionId` 字段（`fromSse` 解析 `json['session_id']`，缺省 `null`）

- [ ] **Step 1: 写失败测试**（`test/chat_session_provider_test.dart`）

```dart
// test/chat_session_provider_test.dart（骨架；用 buildClient/buildHttp seam + FakeBotApi）
```

（覆盖：connect 拉取会话列表写入 state；服务器 404 → 单会话降级 `[default]`；切会话后 `_cacheKey` 变化、history/stream 带新 session_id；事件 sid 不匹配被丢弃；默认事件（sessionId null/''）→ `default` 被接受。）

- [ ] **Step 2: 运行测试验证失败**

Run: `cd astrbot-app && flutter test test/chat_session_provider_test.dart`
Expected: FAIL

- [ ] **Step 3: 实现最小代码**

按上述接口改 `ChatState`/`ChatNotifier`。要点：
- `ChatState` 加 `sessions`/`currentSessionId`/`sessionsError` + copyWith。
- `buildHttp`/`buildClient` 传 `sessionId: state.currentSessionId`。
- `connect()` 在 auth 后、history 前：`_loadAuthoritativeSessions(acc)` → `http.fetchSessions()` → `state.sessions = fetched` + 写 `SessionStore` 镜像 + 恢复该账户 `currentSession`（store.getCurrent 或 default）；catch `SessionApiUnavailable` → `state.sessions = [ChatSession(id:'default', name:'默认会话')]`。
- `_cacheKey` getter 替代 `_cacheAccountId` 全部使用点（含 `_doDownloadAndPersist`、`_handleMedia`、`_commitBotText`、`_flushInterruptedStream`、`_catchupHistory`、`_alignCheck`、`_catchupAfterReply`、`loadMoreHistory`）。
- `_handleEvent` 开头：
```dart
    if (event.sessionId != null) {
      final esid = (event.sessionId!.isEmpty) ? 'default' : event.sessionId!;
      if (esid != state.currentSessionId) return; // 其它会话事件丢弃
    }
```
- 会话 CRUD：
  - `selectSession(sid)`：`SessionStore.setCurrent(accId, sid)` → `connect()`
  - `createSession(name)`：`http.createSession(name)` → 更新 store/state → 刷新
  - `renameSession(sid, name)` / `deleteSession(sid)`：类似，成功后若删当前会话切到 default
- `deleteAccount`：`SessionStore` 移除该账户条目。
- `BotApiEvent` 加 `sessionId` 字段 + fromSse 解析。

- [ ] **Step 4: 运行测试验证通过**

Run: `cd astrbot-app && flutter test test/chat_session_provider_test.dart test/chat_provider_test.dart`
Expected: PASS

- [ ] **Step 5: 提交**

```bash
cd astrbot-app && git add lib/providers/chat_provider.dart lib/models/botapi_event.dart test/chat_session_provider_test.dart
git commit -m "feat(app): ChatState 会话字段 + connect 拉权威会话列表 + SSE sid 过滤"
```

---

### Task 11: App — 两级抽屉（账户 → 会话面板）

**Files:**
- Modify: `astrbot-app/lib/widgets/account_drawer.dart`
- Modify: `astrbot-app/lib/screens/chat_screen.dart`
- Test: `astrbot-app/test/account_drawer_test.dart`（新建，widget test）

**Interfaces:**
- Consumes: Task 10 的 `state.sessions/currentSessionId` + notifier 会话方法
- Produces: 会话面板 UI（列表 + 新建/重命名/删除 + 返回；默认会话无删除按钮）

- [ ] **Step 1: 写失败测试**（`test/account_drawer_test.dart`）

```dart
// test/account_drawer_test.dart（骨架：点账户 → 出现会话面板；默认会话无删除按钮）
```

- [ ] **Step 2: 运行测试验证失败**

Run: `cd astrbot-app && flutter test test/account_drawer_test.dart`
Expected: FAIL

- [ ] **Step 3: 实现最小代码**

`account_drawer.dart`：账户 tile `onTap` 改为进入该账户的会话面板（`_SessionPanel` StatefulWidget：返回键 + 会话列表 + 新建按钮 + 每项菜单重命名/删除）。选中会话 → `selectSession(sid)` + 关抽屉。默认会话删除项隐藏。`chat_screen.dart` 无需布局改动（`currentSessionId` 变化经 `connect()` 反映）。

- [ ] **Step 4: 运行测试验证通过**

Run: `cd astrbot-app && flutter test test/account_drawer_test.dart`
Expected: PASS

- [ ] **Step 5: 提交**

```bash
cd astrbot-app && git add lib/widgets/account_drawer.dart lib/screens/chat_screen.dart test/account_drawer_test.dart
git commit -m "feat(app): 两级抽屉账户→会话面板 + 会话 CRUD UI"
```

---

### Task 12: App — 全量回归 + 版本 bump + 构建

**Files:**
- Modify: `astrbot-app/pubspec.yaml`（`1.8.0`）
- Modify: `astrbot-app/CHANGELOG.md`（若存在）

- [ ] **Step 1: 全量跑测试**

Run: `cd astrbot-app && flutter test`
Expected: 全部 PASS

- [ ] **Step 2: 静态分析**

Run: `cd astrbot-app && flutter analyze`
Expected: No issues found

- [ ] **Step 3: 版本 bump**

`pubspec.yaml` `version: 1.8.0+39`（build +1）。

- [ ] **Step 4: 构建 APK**

Run: `cd astrbot-app && export ANDROID_HOME=/home/zzt/android-sdk && export JAVA_HOME=/usr/lib/jvm/java-17-openjdk && export PATH="/home/zzt/flutter/bin:$JAVA_HOME/bin:$ANDROID_HOME/cmdline-tools/latest/bin:$PATH" && flutter build apk --release`
Expected: APK 产出

- [ ] **Step 5: 提交**

```bash
cd astrbot-app && git add pubspec.yaml CHANGELOG.md
git commit -m "chore(app): 多会话版本 1.8.0"
```

---

## Self-Review

### Spec 覆盖核对

| Spec 要求 | 对应 Task |
|---|---|
| 会话 CRUD（增/删/改/重命名） | Task 2（Phone API）+ Task 5（Web 路由）+ Task 8/10（App）+ Task 6（前端） |
| 每账户会话隔离 | Task 1（scoped_key/umo） |
| 跨 app 同步（服务端权威） | Task 1（持久化 save_sessions）+ Task 2（API）+ Task 8/10（App 拉取） |
| Web 管理平台管理会话 | Task 5（Web 路由）+ Task 6（前端下钻） |
| 默认会话兼容/存量零迁移 | Task 1（无后缀键/只读派生）+ Task 9（DB re-key） |
| 老客户端兼容 | Task 3（缺省 session_id→默认） |
| SSE 事件带 session_id | Task 3/4 |
| App 切会话重建连接 | Task 10 |
| App 降级（404 单会话） | Task 10 |
| 会话数上限 25 | Task 2（服务端）+ Task 8（App store cap） |
| 越权 404 | Task 1（resolve_sid LookupError→404） |
| 默认会话不可删 | Task 2（delete 拒绝）+ Task 11（UI 隐藏） |
| 会话清空历史 | Task 5（_do_clear 会话 umo new_conversation） |
| 删除会话清 conversation/SSE | Task 1（delete_session） |
| stats/disconnect 按 scoped 聚合 | Task 5（sse_queues_for） |

### 类型/签名一致性

- `sessions_list/save_sessions/umo_for/scoped_key_for/resolve_sid/delete_session` 全部在 `sessions.py`，Task 1 定义，Task 2-6 引用，签名一致。
- `_push_media(chain, token, message_id, sid="default")` 默认参向后兼容（Task 4 定义）。
- App `_cacheKey = '${_accounts.currentId}:${state.currentSessionId}'` 全 provider 一致（Task 10）。
- `BotApiEvent.sessionId`：`null`/`''` → provider 归一 `default` 比较。
- App `sendMessage`/`fetchHistory`/`connect` 对 `default` 会话不发 `session_id` 参数（保老服务器兼容）。

### 占位符扫描

所有步骤含具体代码/命令；测试为可运行骨架。无 TBD/TODO。Task 6 前端步骤因依赖既有 DOM 结构，以「阅读+实现」代替精确代码块——符合「前端跟随既有模式」约束。
