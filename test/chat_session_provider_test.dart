// test/chat_session_provider_test.dart
//
// ChatNotifier 会话功能测试：
// - connect() 拉服务端权威会话列表 → 写 SessionStore 镜像 → 恢复每账户当前会话
// - 服务器 404（SessionApiUnavailable）→ 降级单会话 [default]
// - _cacheKey 随会话切换而变 → 消息 DB 分区
// - _handleEvent 按 event.sessionId 过滤（其它会话事件丢弃）
// - selectSession/createSession/renameSession/deleteSession 更新 state + store
// - deleteAccount 级联清 SessionStore 该账户条目
import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus_platform_interface/connectivity_plus_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:astrbot_app/models/account.dart';
import 'package:astrbot_app/models/botapi_event.dart';
import 'package:astrbot_app/models/chat_session.dart';
import 'package:astrbot_app/models/history_row.dart';
import 'package:astrbot_app/providers/chat_provider.dart';
import 'package:astrbot_app/services/botapi_client.dart';
import 'package:astrbot_app/services/botapi_http.dart';
import 'package:astrbot_app/services/cache_service.dart';
import 'package:astrbot_app/services/config_service.dart';
import 'package:astrbot_app/services/session_store.dart' show kDefaultSessionId;

/// 假 Connectivity 平台：onConnectivityChanged 恒空流（测试不会收到
/// 连接变化事件，避免 connect() 里订阅真实平台方法通道抛 MissingPluginException）。
class _FakeConnectivityPlatform extends ConnectivityPlatform {
  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => [ConnectivityResult.wifi];
  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged => const Stream.empty();
}

/// 假 REST 客户端：记录会话调用，历史/媒体返回空。
class _FakeHttp implements BotApiHttp {
  List<ChatSession> sessions = const [];
  Object? sessionsError; // 若置为 SessionApiUnavailable 实例则 fetchSessions 抛之
  final calls = <String>[];
  String _sid = '';
  final List<String> createdNames = [];
  final List<String> renamed = [];
  final List<String> deleted = [];

  @override
  String get serverUrl => 'http://fake';
  @override
  String get token => 't';
  @override
  String get sessionId => _sid;
  set sid(String v) => _sid = v;
  @override
  Map<String, String> get authHeaders => {'Authorization': 'Bearer t'};

  @override
  Future<bool> auth() async {
    calls.add('auth');
    return true;
  }

  @override
  Future<String?> sendMessage({String? text, List<String>? fileIds}) async {
    return 'msg_id';
  }

  @override
  Future<({UploadResult? result, String? error})> uploadFile(File file,
      String contentType,
      {void Function(int sent, int total)? onProgress}) async {
    return (result: null, error: null);
  }

  @override
  Future<File?> downloadByUrl(String url) async => null;

  @override
  Future<List<ChatSession>> fetchSessions() async {
    calls.add('fetchSessions');
    if (sessionsError != null) throw sessionsError!;
    return sessions;
  }

  @override
  Future<HistoryResult> fetchHistory({int? since, int? before, int limit = 50}) async {
    calls.add('fetchHistory');
    return const HistoryResult(messages: [], hasMore: false);
  }

  @override
  Future<ChatSession?> createSession(String name) async {
    calls.add('createSession');
    createdNames.add(name);
    final s = ChatSession(id: 's_new_${createdNames.length}', name: name);
    sessions = [...sessions, s];
    return s;
  }

  @override
  Future<bool> renameSession(String sid, String name) async {
    calls.add('renameSession');
    renamed.add(sid);
    sessions = sessions.map((s) => s.id == sid ? s.copyWith(name: name) : s).toList();
    return true;
  }

  @override
  Future<bool> deleteSession(String sid) async {
    calls.add('deleteSession');
    deleted.add(sid);
    sessions = sessions.where((s) => s.id != sid).toList();
    return true;
  }
}

/// 假 SSE 客户端：connect 记录收到的 sessionId；不真正联网。
class _FakeClient implements BotApiClient {
  _FakeClient(this._sessionId);

  final String _sessionId;
  final _events = StreamController<BotApiEvent>.broadcast();
  final _states = StreamController<ConnState>.broadcast();
  int? _sinceCursor;
  bool _disposed = false;
  int connectCount = 0;

  @override
  String get serverUrl => 'http://fake';
  @override
  String get token => 't';
  @override
  String get sessionId => _sessionId;
  @override
  Stream<BotApiEvent> get events => _events.stream;
  @override
  Stream<ConnState> get state => _states.stream;
  @override
  set sinceCursor(int? c) => _sinceCursor = c;
  int? get receivedCursor => _sinceCursor;

  @override
  Future<void> connect({int? sinceCursor}) async {
    connectCount++;
    _states.add(ConnState.connected);
  }

  @override
  Future<http.StreamedResponse> sendRequest(
      http.Client client, http.Request request) async {
    throw StateError('_FakeClient 不实际联网');
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    await _events.close();
    await _states.close();
  }

  @override
  bool get isDisposed => _disposed;
}

/// 测试子类：覆写两个 @visibleForTesting 构造 seam，注入假实现。
/// 复用同一个 [_FakeHttp] 实例（会话变更跨 connect 保持），记录每次 build 的
/// sessionId 供断言「切换会话后 client/http 带新 sid」。
class TestNotifier extends ChatNotifier {
  TestNotifier(super.config);

  final _fakeHttp = _FakeHttp();
  final httpBuilt = <String>[];
  final clientBuilt = <String>[];

  /// 权威会话列表（转发到共享假 http）。
  set sessions(List<ChatSession> v) => _fakeHttp.sessions = v;
  set sessionsError(Object? e) => _fakeHttp.sessionsError = e;

  @override
  BotApiHttp buildHttp(Account acc, {String sessionId = ''}) {
    httpBuilt.add(sessionId);
    _fakeHttp.sid = sessionId;
    return _fakeHttp;
  }

  @override
  BotApiClient buildClient(Account acc, {String sessionId = ''}) {
    clientBuilt.add(sessionId);
    return _FakeClient(sessionId);
  }
}

/// 构造一个已登录的 ChatNotifier（SharedPreferences + 内存 DB）。
Future<TestNotifier> makeNotifier() async {
  SharedPreferences.setMockInitialValues({});
  final config = ConfigService();
  await config.init();
  final n = TestNotifier(config);
  addTearDown(() => n.dispose());
  // 加一个账户
  await n.addAccount(
      serverUrl: 'http://fake/api/v1/botapi', token: 'tok1', label: 'BotA');
  return n;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  setUp(() {
    ConnectivityPlatform.instance = _FakeConnectivityPlatform();
    CacheService.dbPathOverride = inMemoryDatabasePath;
    CacheService.resetDbForTesting();
  });
  tearDown(() => CacheService.resetDbForTesting());

  test('connect 拉权威会话列表：state.sessions + 恢复当前会话 + client 带 sessionId',
      () async {
    final n = await makeNotifier();
    n.sessions = [
      const ChatSession(id: 'default', name: '默认会话'),
      const ChatSession(id: 's1', name: '工作'),
    ];
    // 预置 SessionStore：当前会话为 s1 → connect 恢复它，http/client 带 s1。
    await n.selectSession('s1'); // 内部触发一次 connect
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(n.state.sessions.map((s) => s.id), containsAll(['default', 's1']));
    expect(n.state.currentSessionId, 's1');
    expect(n.clientBuilt.last, 's1'); // client 构造携带恢复后的 sessionId
    expect(n.httpBuilt.last, 's1');
    expect(n.state.connectionState, ConnState.connected);
    expect(n.state.sessionsError, isNull);
  });

  test('fetchSessions 抛 SessionApiUnavailable → 降级单会话 [default]', () async {
    final n = await makeNotifier();
    n.sessionsError = SessionApiUnavailable();
    await n.connect();
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(n.state.sessions, [
      const ChatSession(id: kDefaultSessionId, name: '默认会话'),
    ]);
    expect(n.state.currentSessionId, kDefaultSessionId);
    expect(n.state.sessionsError, isNull);
  });

  test('默认事件(sessionId null/空)被接受；其它会话事件被丢弃', () async {
    final n = await makeNotifier();
    n.sessions = const [ChatSession(id: 'default', name: '默认会话')];
    await n.connect();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(n.state.currentSessionId, kDefaultSessionId);

    // 无 sessionId（老服务器）→ 接受。
    BotApiEvent e = BotApiEvent.fromSse('message', {
      'type': 'text', 'content': '无sid', 'final': true,
    });
    await n.handleEventForTest(e);
    expect(n.state.messages.where((m) => m.isFromMe == false).length, 1);

    // 空 sessionId（默认会话）→ 接受。
    e = BotApiEvent.fromSse('message', {
      'type': 'text', 'content': '空sid', 'final': true,
      'session_id': '',
    });
    await n.handleEventForTest(e);
    expect(n.state.messages.where((m) => m.isFromMe == false).length, 2);

    // 非默认会话 s1 → 丢弃。
    e = BotApiEvent.fromSse('message', {
      'type': 'text', 'content': '其它会话', 'final': true,
      'session_id': 's1',
    });
    await n.handleEventForTest(e);
    expect(n.state.messages.where((m) => m.isFromMe == false).length, 2);
  });

  test('selectSession 切换 currentSessionId 且 client/http 带新 sessionId', () async {
    final n = await makeNotifier();
    n.sessions = [
      const ChatSession(id: 'default', name: '默认会话'),
      const ChatSession(id: 's1', name: '工作'),
    ];
    await n.connect();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(n.state.currentSessionId, kDefaultSessionId);

    await n.selectSession('s1');
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(n.state.currentSessionId, 's1');
    expect(n.clientBuilt.last, 's1');
    expect(n.httpBuilt.last, 's1');
    // 切回 default
    await n.selectSession('default');
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(n.state.currentSessionId, 'default');
    // seam 收到的是 state.currentSessionId（默认会话即 'default'；
    // 底层 BotApiHttp/BotApiClient 对 'default' 会省略 session_id 参数）。
    expect(n.clientBuilt.last, 'default');
  });

  test('createSession / renameSession / deleteSession 更新 state + store', () async {
    final n = await makeNotifier();
    n.sessions = const [ChatSession(id: 'default', name: '默认会话')];
    await n.connect();
    await Future<void>.delayed(const Duration(milliseconds: 20));

    // create
    final created = await n.createSession('工作');
    expect(created, isNotNull);
    expect(n.state.sessions.map((s) => s.id), contains(created!.id));
    expect(n.state.sessions.map((s) => s.name), contains('工作'));

    // rename
    final ok = await n.renameSession(created.id, '工作改名');
    expect(ok, isTrue);
    expect(
        n.state.sessions.firstWhere((s) => s.id == created.id).name, '工作改名');

    // delete 非当前会话：状态更新、不重连。
    final okDel = await n.deleteSession(created.id);
    expect(okDel, isTrue);
    expect(n.state.sessions.map((s) => s.id), isNot(contains(created.id)));
  });

  test('deleteSession 当前会话 → 切回 default 并重连', () async {
    final n = await makeNotifier();
    n.sessions = [
      const ChatSession(id: 'default', name: '默认会话'),
      const ChatSession(id: 's1', name: '工作'),
    ];
    await n.connect();
    await n.selectSession('s1');
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(n.state.currentSessionId, 's1');

    final connectsBefore = (n.clientBuilt).length;
    final ok = await n.deleteSession('s1');
    expect(ok, isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(n.state.currentSessionId, kDefaultSessionId);
    expect(n.state.sessions.map((s) => s.id), isNot(contains('s1')));
    expect(n.clientBuilt.length, greaterThan(connectsBefore)); // 触发重连
    expect(n.clientBuilt.last, 'default'); // 切回 default 后 client 带 'default'（底层会省略该参数）
  });

  test('消息 DB 按会话分区：_cacheKey 随 currentSessionId 变化', () async {
    final n = await makeNotifier();
    n.sessions = [
      const ChatSession(id: 'default', name: '默认会话'),
      const ChatSession(id: 's1', name: '工作'),
    ];
    await n.connect();
    await Future<void>.delayed(const Duration(milliseconds: 20));

    final accId = n.state.currentAccountId;
    // default 分区写一条
    n.sendText('在默认会话');
    await Future<void>.delayed(const Duration(milliseconds: 20));

    // 切到 s1 分区写一条
    await n.selectSession('s1');
    await Future<void>.delayed(const Duration(milliseconds: 20));
    n.sendText('在s1会话');
    await Future<void>.delayed(const Duration(milliseconds: 20));

    final cache = CacheService();
    final defMsgs = await cache.getMessages(accountId: '$accId:default');
    final s1Msgs = await cache.getMessages(accountId: '$accId:s1');
    expect(defMsgs.map((m) => m.content), contains('在默认会话'));
    expect(defMsgs.map((m) => m.content), isNot(contains('在s1会话')));
    expect(s1Msgs.map((m) => m.content), contains('在s1会话'));
    expect(s1Msgs.map((m) => m.content), isNot(contains('在默认会话')));
  });

  test('默认会话不持久化：镜像过滤 + select/delete 不写 current=default', () async {
    final n = await makeNotifier();
    final accId = n.state.currentAccountId;
    final store = n.sessionStoreForTest;
    n.sessions = [
      const ChatSession(id: 'default', name: '默认会话'),
      const ChatSession(id: 's1', name: '工作'),
    ];
    // connect 拉权威列表（含 default）：store 镜像必须过滤掉 default。
    await n.connect();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final mirrored = await store.list(accId);
    expect(mirrored.map((s) => s.id), isNot(contains(kDefaultSessionId)));
    expect(mirrored.map((s) => s.id), contains('s1'));

    // selectSession('default')：不写 current=default。
    await n.selectSession('s1');
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await n.selectSession('default');
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(n.state.currentSessionId, kDefaultSessionId);
    expect(await store.getCurrent(accId), isNull);

    // deleteSession(当前 s1) 切回默认：不 setCurrent('default')，仅移除 current 记录。
    await n.selectSession('s1');
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await n.deleteSession('s1');
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(n.state.currentSessionId, kDefaultSessionId);
    expect(await store.getCurrent(accId), isNull);
  });

  test('deleteAccount 级联清 SessionStore 该账户条目', () async {
    final n = await makeNotifier();
    final accId = n.state.currentAccountId;
    n.sessions = const [ChatSession(id: 'default', name: '默认会话')];
    await n.connect();
    await n.createSession('临时');
    await Future<void>.delayed(const Duration(milliseconds: 20));

    final sessionStoreOf = n.sessionStoreForTest;
    expect((await sessionStoreOf.list(accId)).length, greaterThan(0));

    await n.deleteAccount(accId);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(await sessionStoreOf.list(accId), isEmpty);
    expect(await sessionStoreOf.getCurrent(accId), isNull);
  });
}
