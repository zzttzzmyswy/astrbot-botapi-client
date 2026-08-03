// lib/util/active_connection.dart
import 'dart:async';

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
