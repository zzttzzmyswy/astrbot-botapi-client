# 流式三分重复修复 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 消除手机 App 流式回复的成组 N 倍重复与「旧坏消息残留」，根因是 `ChatNotifier.connect()` 非重入导致孤儿 `BotApiClient` 与泄漏的 `_handleEvent` 订阅。

**Architecture:** 引入 `ActiveConnection`（封装「当前唯一连接」+ 世代号），让 `ChatNotifier.connect()` 重入安全、接管即拆旧；给 `BotApiClient.connect()` 加世代号护栏，防同一 client 重叠 `_parseStream`。两端都从「靠时序碰运气」改为「靠世代号/接管语义保证至多一个激活」。

**Tech Stack:** Dart / Flutter / Riverpod StateNotifier / `package:http` SSE / `flutter_test`。

## Global Constraints

- 仓库：`astrbot-app`（Flutter 客户端）。改动不触及服务端插件、不动 SSE 协议。
- 测试用 `flutter_test`，纯 Dart 单测；不新增 platform 依赖。
- 命名/注释沿用现有中文注释风格（见 `lib/util/retry.dart`、`lib/util/stream_text.dart`）。
- 遵循 `analysis_options.yaml`（lint 零警告）。
- spec：`docs/superpowers/specs/2026-08-01-streaming-triple-duplication-fix-design.md`。

---

## 文件结构

| 文件 | 职责 | 动作 |
|---|---|---|
| `lib/util/active_connection.dart` | 「当前唯一连接」+ 世代号：`install` 拆旧装新、`disposeCurrent` 拆旧、`beginIntent`/`isCurrent` 世代号 | 新建 |
| `lib/services/botapi_client.dart` | SSE 客户端；加 `isDisposed` 测试 seam、`sendRequest` 测试 seam、`_connectGen` 世代号护栏 | 改 |
| `lib/providers/chat_provider.dart` | 用 `ActiveConnection` 取代裸 `_client/_eventSub/_stateSub`；`connect()` 加世代号 + 接管前清理 + `buildClient/buildHttp` seam | 改 |
| `test/active_connection_test.dart` | `ActiveConnection` 接管拆旧、世代号语义 | 新建 |
| `test/botapi_client_reentry_test.dart` | `BotApiClient` 重叠 `connect()` 不重复投递事件 | 新建 |

### 与 spec §5.1 的偏差（已确认，见下）

spec §5.1 原写「chat_provider 重入单测」。`ChatNotifier.connect()` 依赖 `connectivity_plus`（platform channel）、`SharedPreferences`、`CacheService`、`Dio` 网络，单测需大量桩且本仓库无 ChatNotifier 单测先例（既有测试都是纯函数/纯 util）。**改用 `ActiveConnection` 单测锁定核心不变量「接管即拆旧」，`BotApiClient` 单测锁定「重叠 parse 不重复」，ChatNotifier 级集成改由手动 E2E 覆盖（Task 4）。** spec §5.1 在 Task 2 同步修订。

---

## Task 1: `ActiveConnection` helper + `BotApiClient.isDisposed` seam + 单测

**Files:**
- Create: `lib/util/active_connection.dart`
- Modify: `lib/services/botapi_client.dart`（加 `@visibleForTesting bool get isDisposed`）
- Test: `test/active_connection_test.dart`

**Interfaces:**
- Produces: `class ActiveConnection` with
  - `BotApiClient? get client`
  - `StreamSubscription<BotApiEvent>? get eventSub`
  - `StreamSubscription<ConnState>? get stateSub`
  - `int beginIntent()`、`bool isCurrent(int intent)`
  - `Future<void> install({required BotApiClient client, required StreamSubscription<BotApiEvent> eventSub, required StreamSubscription<ConnState> stateSub})`
  - `Future<void> disposeCurrent()`
- Produces: `BotApiClient` 增加 `@visibleForTesting bool get isDisposed => _disposed;`

- [ ] **Step 1: 给 `BotApiClient` 加 `isDisposed` 测试 seam**

`lib/services/botapi_client.dart` 顶部 import 改：

```dart
import 'package:flutter/foundation.dart' show visibleForTesting;
```

在 `BotApiClient` 内（`bool _disposed = false;` 字段附近）加：

```dart
  /// 测试用：是否已 dispose（单测断言「旧 client 被 ActiveConnection 拆掉」）。
  @visibleForTesting
  bool get isDisposed => _disposed;
```

- [ ] **Step 2: 写失败的单测**

`test/active_connection_test.dart`：

```dart
// test/active_connection_test.dart
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:astrbot_app/models/botapi_event.dart';
import 'package:astrbot_app/services/botapi_client.dart';
import 'package:astrbot_app/util/active_connection.dart';

void main() {
  group('ActiveConnection', () {
    test('install 取代旧的：cancel 旧 event sub、dispose 旧 client', () async {
      final conn = ActiveConnection();

      // 旧连接（client 真实但未 connect；subs 来自独立 broadcast 控制器，
      // 这样往源 ctrl 发事件可验证 sub 是否已 cancel）。
      final c1 = BotApiClient(serverUrl: 'http://x', token: 't');
      final e1Ctrl = StreamController<BotApiEvent>.broadcast();
      int e1Hits = 0;
      final e1Sub = e1Ctrl.stream.listen((_) => e1Hits++);
      final s1Ctrl = StreamController<ConnState>.broadcast();
      final s1Sub = s1Ctrl.stream.listen((_) {});
      await conn.install(client: c1, eventSub: e1Sub, stateSub: s1Sub);
      expect(conn.client, same(c1));

      // 新连接接管
      final c2 = BotApiClient(serverUrl: 'http://x', token: 't');
      final e2Ctrl = StreamController<BotApiEvent>.broadcast();
      final e2Sub = e2Ctrl.stream.listen((_) {});
      final s2Ctrl = StreamController<ConnState>.broadcast();
      final s2Sub = s2Ctrl.stream.listen((_) {});
      await conn.install(client: c2, eventSub: e2Sub, stateSub: s2Sub);

      // 旧 client 被 dispose，新 client 活着
      expect(c1.isDisposed, isTrue);
      expect(c2.isDisposed, isFalse);
      expect(conn.client, same(c2));

      // 旧 event sub 被 cancel：往其源 ctrl 发事件，监听不再触发
      e1Ctrl.add(BotApiEvent.fromSse(
          'message', {'type': 'text', 'content': 'x', 'streaming': true}));
      await Future.delayed(Duration.zero);
      expect(e1Hits, 0);

      await e1Ctrl.close();
      await e2Ctrl.close();
      await s1Ctrl.close();
      await s2Ctrl.close();
    });

    test('disposeCurrent 拆掉当前连接', () async {
      final conn = ActiveConnection();
      final c = BotApiClient(serverUrl: 'http://x', token: 't');
      final eCtrl = StreamController<BotApiEvent>.broadcast();
      final eSub = eCtrl.stream.listen((_) {});
      final sCtrl = StreamController<ConnState>.broadcast();
      final sSub = sCtrl.stream.listen((_) {});
      await conn.install(client: c, eventSub: eSub, stateSub: sSub);
      await conn.disposeCurrent();
      expect(c.isDisposed, isTrue);
      expect(conn.client, isNull);
      await eCtrl.close();
      await sCtrl.close();
    });

    test('beginIntent / isCurrent：新轮超越旧轮', () {
      final conn = ActiveConnection();
      final a = conn.beginIntent();
      expect(conn.isCurrent(a), isTrue);
      final b = conn.beginIntent();
      expect(conn.isCurrent(b), isTrue);
      expect(conn.isCurrent(a), isFalse, reason: '旧轮已被新轮超越');
    });

    test('install 到空连接不抛', () async {
      final conn = ActiveConnection();
      final c = BotApiClient(serverUrl: 'http://x', token: 't');
      final eCtrl = StreamController<BotApiEvent>.broadcast();
      final eSub = eCtrl.stream.listen((_) {});
      final sCtrl = StreamController<ConnState>.broadcast();
      final sSub = sCtrl.stream.listen((_) {});
      await conn.install(client: c, eventSub: eSub, stateSub: sSub);
      expect(conn.client, same(c));
      await conn.disposeCurrent();
      await eCtrl.close();
      await sCtrl.close();
    });
  });
}
```

- [ ] **Step 3: 运行，确认失败**

```bash
cd astrbot-app && flutter test test/active_connection_test.dart
```
Expected: FAIL（`ActiveConnection` 不存在 / `isDisposed` 未定义）。

- [ ] **Step 4: 实现 `ActiveConnection`**

`lib/util/active_connection.dart`：

```dart
// lib/util/active_connection.dart
import 'dart:async';

import 'package:flutter/foundation.dart' show visibleForTesting;

import '../models/botapi_event.dart';
import '../services/botapi_client.dart';

/// 持有「当前唯一激活的 SSE 连接」：一个 [BotApiClient] + 其事件/状态订阅。
///
/// 修复 `ChatNotifier.connect()` 非重入导致的泄漏：旧实现把
/// `_client`/`_eventSub`/`_stateSub` 当普通字段，重叠 `connect()` 在赋新值
/// 时覆盖引用却不 cancel/dispose 旧的，留下孤儿 `BotApiClient` 永久挂着 SSE、
/// 泄漏的 `_handleEvent` 订阅各往同一 `streamingText` 追加 delta → 成组 N 倍
/// 重复。
///
/// 本类把「接管即拆旧」封装为一处：
/// - [install] 先 cancel 旧 sub、dispose 旧 client，再存新的；
/// - [beginIntent]/[isCurrent] 用世代号让「过时的 connect 轮」在 await 苏醒
///   后自废，不再赋值，杜绝覆盖引用。
class ActiveConnection {
  BotApiClient? _client;
  StreamSubscription<BotApiEvent>? _eventSub;
  StreamSubscription<ConnState>? _stateSub;
  int _intent = 0; // 最新一次 connect() 入口的世代号

  BotApiClient? get client => _client;
  StreamSubscription<BotApiEvent>? get eventSub => _eventSub;
  StreamSubscription<ConnState>? get stateSub => _stateSub;

  /// `connect()` 入口调用：世代号 +1，返回本轮 intent。
  int beginIntent() {
    _intent += 1;
    return _intent;
  }

  /// 本轮 intent 是否仍是最新的（未被更新的 `connect()` 超越）。
  bool isCurrent(int intent) => intent == _intent;

  /// 安装新连接：先拆旧的（cancel sub + dispose client），再存新的。
  /// 由「已通过 [isCurrent] 校验」的最新轮调用。
  Future<void> install({
    required BotApiClient client,
    required StreamSubscription<BotApiEvent> eventSub,
    required StreamSubscription<ConnState> stateSub,
  }) async {
    await _teardown();
    _client = client;
    _eventSub = eventSub;
    _stateSub = stateSub;
  }

  /// 拆掉当前连接（cancel sub + dispose client），不装新的。
  /// 幂等：无连接时为 no-op。
  Future<void> disposeCurrent() async {
    await _teardown();
  }

  Future<void> _teardown() async {
    await _eventSub?.cancel();
    _eventSub = null;
    await _stateSub?.cancel();
    _stateSub = null;
    await _client?.dispose();
    _client = null;
  }
}
```

- [ ] **Step 5: 运行，确认通过**

```bash
cd astrbot-app && flutter test test/active_connection_test.dart
```
Expected: PASS（4 个用例）。

- [ ] **Step 6: 提交**

```bash
cd astrbot-app && git add lib/util/active_connection.dart lib/services/botapi_client.dart test/active_connection_test.dart
git commit -m "feat(util): ActiveConnection 接管即拆旧 + BotApiClient.isDisposed seam

为修复 ChatNotifier.connect() 非重入泄漏做铺垫：ActiveConnection 封装
「当前唯一连接」+ 世代号，install/disposeCurrent 先 cancel 旧 sub、
dispose 旧 client 再装新的；beginIntent/isCurrent 让过时 connect 轮自废。"
```

---

## Task 2: 把 `ActiveConnection` 接入 `ChatNotifier.connect()` + 修订 spec §5.1

**Files:**
- Modify: `lib/providers/chat_provider.dart`
- Modify: `docs/superpowers/specs/2026-08-01-streaming-triple-duplication-fix-design.md`（§5.1）
- Test: 既有测试回归

**Interfaces:**
- Consumes: `ActiveConnection`（Task 1）
- Produces: `ChatNotifier` 新增 `@visibleForTesting BotApiClient buildClient(Account acc)`、`@visibleForTesting BotApiHttp buildHttp(Account acc)`；`connect()` 重入安全。

- [ ] **Step 1: 修订 spec §5.1（与实际可测范围对齐）**

把 `docs/superpowers/specs/2026-08-01-streaming-triple-duplication-fix-design.md` 的 §5.1 两条改为：

```markdown
### 5.1 单元测试（`astrbot-app/test/`）

- `ActiveConnection` 接管语义：install 取代旧连接时 cancel 旧 event/state sub、
  dispose 旧 client；disposeCurrent 拆当前；beginIntent/isCurrent 新轮超越旧轮
  （`test/active_connection_test.dart`）。—— 锁定核心不变量「至多一个激活
  连接，接管即拆旧」，正是泄漏的根因对症。
- `BotApiClient` 重入：模拟「connect() 在 await send 期间再次 connect」，断言
  只有最新一轮 `_parseStream` 激活、事件不被重复 `add`（见 Task 3）。
- `ChatNotifier.connect()` 集成由手动 E2E（§5.2）覆盖：connect() 依赖
  `connectivity_plus`（platform channel）、`SharedPreferences`、`CacheService`、
  `Dio` 网络，单测需大量桩且本仓库无 ChatNotifier 单测先例；其不变量已由
  `ActiveConnection` 单测 + `BotApiClient` 单测共同锁定。
```

- [ ] **Step 2: 改 `chat_provider.dart` 字段与 import**

`lib/providers/chat_provider.dart`：

顶部 import 加：

```dart
import 'package:flutter/foundation.dart' show visibleForTesting;
import '../util/active_connection.dart';
```

把字段块（原 107–111 行附近）：

```dart
  BotApiClient? _client;
  BotApiHttp? _http;
  StreamSubscription<BotApiEvent>? _eventSub;
  StreamSubscription<ConnState>? _stateSub;
```

改为：

```dart
  BotApiHttp? _http;
  final ActiveConnection _conn = ActiveConnection();
```

- [ ] **Step 3: 加 `buildClient` / `buildHttp` 测试 seam**

在 `ChatNotifier` 内（`attachPlayback` 附近）加：

```dart
  /// 构造 SSE 客户端（测试可覆写注入假实现）。生产用真实 [BotApiClient]。
  @visibleForTesting
  BotApiClient buildClient(Account acc) =>
      BotApiClient(serverUrl: acc.serverUrl, token: acc.token);

  /// 构造 REST 客户端（测试可覆写）。生产用真实 [BotApiHttp]。
  @visibleForTesting
  BotApiHttp buildHttp(Account acc) =>
      BotApiHttp(serverUrl: acc.serverUrl, token: acc.token);
```

- [ ] **Step 4: 重写 `connect()`（世代号 + 接管前清理 + install）**

把 `connect()`（原 252–342 行）整体替换为：

```dart
  Future<void> connect() async {
    final intent = _conn.beginIntent();
    _connectivitySub?.cancel();
    _connectivitySub = null;
    _alignTimer?.cancel();
    _alignTimer = null;
    await _conn.disposeCurrent(); // 顶部拆掉上一轮连接
    try {
      state = state.copyWith(
          errorMessage: null,
          streamingText: null,
          streamingThinking: null);
      await _ensureAccountsLoaded();
      if (!_conn.isCurrent(intent)) return; // 被更新的 connect 超越
      final acc = _currentAccount;
      if (acc == null) {
        state = state.copyWith(
            connectionState: ConnState.disconnected,
            errorMessage: '未添加账户，请点击左上角菜单添加');
        _syncAccountState();
        return;
      }
      _http = buildHttp(acc);

      final total = await _cache.getMessageCount(accountId: acc.id);
      final history = await _cache.getMessages(
          accountId: acc.id, limit: _pageSize);
      _hasMoreHistory = history.length >= _pageSize && total > _pageSize;
      _syncAccountState(messages: history);
      if (!_conn.isCurrent(intent)) return;

      // 校验 token（带 transient 重试，克服冷启动 DNS 解析失败）
      final ok = await _http!.auth();
      if (!_conn.isCurrent(intent)) return;
      if (!ok) {
        state = state.copyWith(
            connectionState: ConnState.disconnected,
            errorMessage: 'token 无效或服务器不可达，请在账户管理中更新');
        return;
      }

      final hist = await _http!.fetchHistory(since: 0);
      if (!_conn.isCurrent(intent)) return;
      try {
        await _cache.mergeHistory(hist.messages, accountId: acc.id);
      } catch (_) {}
      final cursor = await _cache.maxServerId(acc.id);
      final refreshed = await _cache.getMessages(
          accountId: acc.id, limit: _pageSize);
      final newTotal = await _cache.getMessageCount(accountId: acc.id);
      _hasMoreHistory =
          refreshed.length >= _pageSize && newTotal > _pageSize;
      if (!_conn.isCurrent(intent)) return;
      _syncAccountState(messages: refreshed);

      // 接管前再清理一次：防兄弟轮在 isCurrent 校验与 install 之间装了连接。
      await _conn.disposeCurrent();
      if (!_conn.isCurrent(intent)) return;
      final client = buildClient(acc);
      final stateSub = client.state.listen((s) {
        if (s == ConnState.disconnected || s == ConnState.reconnecting) {
          _flushInterruptedStream();
        }
        final err = (s == ConnState.connected) ? null : state.errorMessage;
        state = state.copyWith(connectionState: s, errorMessage: err);
        if (s == ConnState.connected && _pendingQueue.isNotEmpty) {
          final pending = List<_PendingSend>.from(_pendingQueue);
          _pendingQueue.clear();
          for (final p in pending) {
            _dispatchPending(p);
          }
        }
      });
      final eventSub = client.events.listen(_handleEvent);
      await _conn.install(
          client: client, eventSub: eventSub, stateSub: stateSub);
      await client.connect(sinceCursor: cursor);
      _startAlignCheck();

      _connectivitySub =
          Connectivity().onConnectivityChanged.listen((results) {
        if (!results.contains(ConnectivityResult.none) &&
            state.connectionState == ConnState.disconnected) {
          connect();
        }
      });
    } catch (e) {
      state = state.copyWith(errorMessage: '连接失败: $e');
    }
  }
```

- [ ] **Step 5: 改其余 `_client`/`_eventSub`/`_stateSub` 引用点**

`_catchupHistory`（原 167 行附近）：

```dart
      _client?.sinceCursor = cursor; // 供下次 SSE 重连用更准的游标
```
→
```dart
      _conn.client?.sinceCursor = cursor; // 供下次 SSE 重连用更准的游标
```

`_alignCheck`（原 198 行附近）：

```dart
      _client?.sinceCursor = await _cache.maxServerId(acc.id);
```
→
```dart
      _conn.client?.sinceCursor = await _cache.maxServerId(acc.id);
```

`_handleEvent` 的 `SESSION_KICKED` 分支（原 525–526 行附近）：

```dart
        await _client?.dispose();
        _client = null;
```
→
```dart
        await _conn.disposeCurrent();
```

`_catchupAfterReply`（原 711 行附近）：

```dart
      _client?.sinceCursor = await _cache.maxServerId(acc.id);
```
→
```dart
      _conn.client?.sinceCursor = await _cache.maxServerId(acc.id);
```

`dispose()`（原 847–857 行附近）整体替换为：

```dart
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _connectivitySub?.cancel();
    _alignTimer?.cancel();
    _replyCatchupTimer?.cancel();
    // _eventSub/_stateSub/_client 的释放统一由 ActiveConnection 负责。
    _conn.disposeCurrent(); // async，fire-and-forget（与旧 _client?.dispose() 同语义）
    super.dispose();
  }
```

- [ ] **Step 6: 回归既有测试 + 全量分析**

```bash
cd astrbot-app && flutter test
```
Expected: 全绿（既有 20 个测试不受影响；`active_connection_test.dart` 也绿）。

```bash
cd astrbot-app && flutter analyze
```
Expected: 无 lint 警告（含无 `cancel`/`await` 相关提示以外的项）。

- [ ] **Step 7: 提交**

```bash
cd astrbot-app && git add lib/providers/chat_provider.dart docs/superpowers/specs/2026-08-01-streaming-triple-duplication-fix-design.md
git commit -m "fix(chat): connect() 重入安全 + 接管即拆旧，根治流式三分重复

ChatNotifier.connect() 非重入：顶部清理与赋新 _client/_eventSub 之间隔着
多个 await，并发 connect() 在 _eventSub 仍为 null 时跳过清理，赋值时覆盖
引用却不 cancel/dispose 旧的，留下孤儿 BotApiClient 永久挂 SSE、泄漏的
_handleEvent 订阅各往同一 streamingText 追加 delta → 成组 N 倍重复；
重连误 flush 把 N 倍文本落为中断占位行，reconciler 识别不了 → 旧坏消息残留。

改用 ActiveConnection：beginIntent 世代号让过时轮自废、install 接管即拆旧
（cancel sub + dispose client）。buildClient/buildHttp 暴露测试 seam。
spec §5.1 同步修订为 ActiveConnection + BotApiClient 单测 + 手动 E2E。"
```

---

## Task 3: `BotApiClient.connect()` 世代号护栏 + `sendRequest` seam + 单测

**Files:**
- Modify: `lib/services/botapi_client.dart`
- Test: `test/botapi_client_reentry_test.dart`

**Interfaces:**
- Produces: `BotApiClient` 新增 `@visibleForTesting Future<http.StreamedResponse> sendRequest(http.Client client, http.Request request)`；`connect()` 加 `_connectGen` 世代号；`_parseStream` 增加 `gen` 形参与退出校验。

- [ ] **Step 1: 写失败的单测**

`test/botapi_client_reentry_test.dart`：

```dart
// test/botapi_client_reentry_test.dart
import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:astrbot_app/models/botapi_event.dart';
import 'package:astrbot_app/services/botapi_client.dart';

http.StreamedResponse _resp(Stream<List<int>> s) => http.StreamedResponse(
      http.ByteStream(s),
      200,
      headers: {'content-type': 'text/event-stream'},
    );

List<int> _bytes(String s) => utf8.encode(s);

const _delta = 'event: message\n'
    'data: {"message_id":"m","type":"text","content":"A","streaming":true}\n\n';

/// 通过覆写 sendRequest 注入两条假流，模拟同 client 两次 connect() 重叠。
class _SpyClient extends BotApiClient {
  final Future<http.StreamedResponse> Function() _send;
  _SpyClient({required Future<http.StreamedResponse> Function() send})
      : _send = send,
        super(serverUrl: 'http://x', token: 't');

  @override
  Future<http.StreamedResponse> sendRequest(
      http.Client client, http.Request request) async {
    client.close(); // 测试不真正用 client，关掉避免资源告警
    return _send();
  }
}

void main() {
  test('重叠 connect() 不重复投递事件：旧 parse 被世代号超越而退出', () async {
    final ctrlA = StreamController<List<int>>();
    final ctrlB = StreamController<List<int>>();
    final sends = <StreamController<List<int>>>[ctrlA, ctrlB];
    var i = 0;
    final client = _SpyClient(send: () async => _resp(sends[i++].stream));
    final recv = <String>[];
    final sub = client.events.listen((e) {
      if (e.content != null) recv.add(e.content!);
    });

    final c1 = client.connect(); // 第一轮，消费 ctrlA
    await Future.delayed(const Duration(milliseconds: 30)); // 让 _parseStream 启动
    final c2 = client.connect(); // 第二轮超越（gen=2），令第一轮 parse 退出
    await Future.delayed(const Duration(milliseconds: 30));

    // 两条流都投同一条 delta（模拟服务端对两条连接各自投递一份）
    ctrlA.add(_bytes(_delta));
    ctrlB.add(_bytes(_delta));
    await Future.delayed(const Duration(milliseconds: 60));

    await ctrlA.close();
    await ctrlB.close();
    await c1;
    await c2;
    await sub.cancel();

    // 修复后：第一轮 parse 已被超越退出，仅第二轮投递一次 → 'A' 恰好 1 个。
    // 修复前会 2 个（两个 parse 都把 'A' add 进同一 controller）。
    expect(recv.where((c) => c == 'A').length, 1,
        reason: '重叠 connect 不得让同一条 delta 被投递多次');
  });
}
```

- [ ] **Step 2: 运行，确认失败**

```bash
cd astrbot-app && flutter test test/botapi_client_reentry_test.dart
```
Expected: FAIL（`sendRequest` 未定义 / `_parseStream` 无 gen 退出 → `recv` 出现 2 个 'A'）。

- [ ] **Step 3: 给 `BotApiClient` 加世代号与 `sendRequest` seam**

`lib/services/botapi_client.dart` 顶部 import 改：

```dart
import 'package:flutter/foundation.dart' show visibleForTesting;
```

在 `BotApiClient` 内字段区加：

```dart
  int _connectGen = 0; // connect() 世代号：新轮超越旧轮，令旧 _parseStream 退出
```

把 `connect()`（原 53–91 行）整体替换为：

```dart
  Future<void> connect({int? sinceCursor}) async {
    if (_disposed) return;
    final gen = ++_connectGen;
    _sinceCursor = sinceCursor;
    _setState(ConnState.connecting);
    try {
      final uri = sinceCursor != null
          ? Uri.parse('$_base/stream?since=$sinceCursor')
          : Uri.parse('$_base/stream');
      final request = http.Request('GET', uri);
      request.headers.addAll({
        'Authorization': 'Bearer $token',
        'Accept': 'text/event-stream',
      });
      _httpClient?.close();
      _httpClient = http.Client();
      final streamedResponse = await withRetry(
        () => sendRequest(_httpClient!, request),
        isTransient: isTransientHttpError,
        maxAttempts: 3,
        delayFor: (i) => Duration(milliseconds: 1000 << i),
      );
      if (gen != _connectGen) return; // 被更新的内部重连超越，本轮作废
      if (streamedResponse.statusCode != 200) {
        _eventController.add(BotApiEvent.fromSse('error', {
          'code': 'CONNECT_FAILED',
          'message': 'HTTP ${streamedResponse.statusCode}',
        }));
        _setState(ConnState.disconnected);
        return;
      }
      _reconnect.reset();
      _lastReceivedAt = DateTime.now();
      _setState(ConnState.connected);
      _startIdleWatchdog();
      _parseStream(streamedResponse, gen);
    } catch (e) {
      if (gen == _connectGen) _scheduleReconnect();
    }
  }

  /// 发送 SSE GET 请求（测试可覆写注入假 [http.StreamedResponse]）。
  @visibleForTesting
  Future<http.StreamedResponse> sendRequest(
      http.Client client, http.Request request) async {
    return client.send(request).timeout(const Duration(seconds: 300));
  }
```

把 `_parseStream`（原 124–165 行）签名与循环改为带 `gen` 退出校验：

```dart
  void _parseStream(http.StreamedResponse resp, int gen) async {
    String? eventType;
    final dataBuf = StringBuffer();
    try {
      final lines = resp.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter());
      await for (final line in lines) {
        if (_disposed || gen != _connectGen) break; // 被超越则退出，不再喂数据
        _lastReceivedAt = DateTime.now();
        if (line.startsWith(':')) {
          continue;
        } else if (line.startsWith('event:')) {
          eventType = line.substring(6).trim();
        } else if (line.startsWith('data:')) {
          dataBuf.write(line.substring(5).trim());
        } else if (line.isEmpty && eventType != null) {
          final raw = dataBuf.toString();
          dataBuf.clear();
          final type = eventType;
          eventType = null;
          if (raw.isEmpty) {
            if (type == 'ping') {
              _eventController.add(BotApiEvent.fromSse('ping', {}));
            }
            continue;
          }
          try {
            final json = jsonDecode(raw) as Map<String, dynamic>;
            _eventController.add(BotApiEvent.fromSse(type, json));
          } catch (_) {}
        }
      }
    } catch (_) {}
    if (gen != _connectGen) return; // 被超越：不触发重连（由超越轮接管）
    _idleWatchdog?.cancel();
    if (!_disposed) {
      _setState(ConnState.disconnected);
      _scheduleReconnect();
    }
  }
```

- [ ] **Step 4: 运行单测，确认通过**

```bash
cd astrbot-app && flutter test test/botapi_client_reentry_test.dart
```
Expected: PASS（`recv` 中 'A' 恰好 1 个）。

- [ ] **Step 5: 全量回归 + 分析**

```bash
cd astrbot-app && flutter test
cd astrbot-app && flutter analyze
```
Expected: 全绿、无 lint 警告。

- [ ] **Step 6: 提交**

```bash
cd astrbot-app && git add lib/services/botapi_client.dart test/botapi_client_reentry_test.dart
git commit -m "fix(botapi): connect() 世代号护栏，防同 client 重叠 _parseStream 重复投递

内部重连（_scheduleReconnect/_forceReconnect）与外部 connect() 可能并发，
导致同一 _eventController 被两个 _parseStream 喂数据 → 事件被 add 多次。
加 _connectGen：新轮令旧 parse 在下一行 break 退出、且不触发重连；
sendRequest 暴露测试 seam 注入假流。"
```

---

## Task 4: 手动 E2E 验证（spec §5.2/§5.3）

**Files:**
- 无源码改动；仅运行验证。

- [ ] **Step 1: 跑通全量测试与分析**

```bash
cd astrbot-app && flutter test && flutter analyze
```
Expected: 全绿、无警告。

- [ ] **Step 2: 真机流式无重复**

用测试账户 token（管理员已在 astrbot.zztweb.top 配置）连接 App，发：
`请用一句话介绍你自己，然后数1到5`。
Expected：气泡逐字增长，**无成组重复**；完成后仅 1 条干净消息，**无残留坏消息**。

- [ ] **Step 3: 重连后仍无重复**

切后台 ≥90s 触发空闲看门狗重连（或开关飞行模式）后再发一条。
Expected：流式无重复、无残留坏消息。

- [ ] **Step 4: 快速切账户无累积重复**

在账户抽屉来回切账户 3 次后发消息。
Expected：无累积重复（无遗留孤儿客户端）。

- [ ] **Step 5: 诊断日志确认（可选，验后移除）**

如需坐实「泄漏消失」，临时在 `BotApiClient` 构造与 `dispose` 打 `debugPrint`
实例 id，复现一次确认构造/释放成对；验后 `git revert` 或手改移除。
Expected：构造数 == 释放数（无泄漏）。

- [ ] **Step 6: 收尾**

```bash
cd astrbot-app && git log --oneline -5
```
Expected：Task 1/2/3 三条 commit 在列，工作树干净。

---

## Self-Review 记录

- **Spec 覆盖**：§4.1（ChatNotifier 重入 + 接管清理）→ Task 2；§4.2（BotApiClient 重入护栏）→ Task 3；§4.3（不动 reconciler）→ 未触及，符合；§5.1（单测）→ Task 1 + Task 3，§5.1 已在 Task 2 Step1 同步修订；§5.2/§5.3（E2E + 诊断）→ Task 4；§6（风险回滚）→ 各 Task 独立可回滚；§7（变更清单）→ 文件结构表覆盖。
- **Placeholder 扫描**：无 TBD/TODO；每步含实际代码或实际命令。
- **类型一致**：`ActiveConnection.install/disposeCurrent` 返回 `Future<void>`，`beginIntent` 返回 `int`，`isCurrent(int)` 返回 `bool`，与 Task 2 用法一致；`BotApiClient.sendRequest` 签名 `(http.Client, http.Request) → Future<http.StreamedResponse>`、`_parseStream(resp, gen)` 与 Task 3 调用一致；`isDisposed` getter 在 Task 1 定义、Task 1 测试使用。
