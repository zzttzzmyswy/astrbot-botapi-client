// test/media_event_test.dart
//
// 同一毫秒内连续到达多条媒体事件（服务端一次回复推多张图 / 图+文件+语音）：
// - 每条消息的 created_at 必须唯一：本地库 upsert 以 created_at 为键，撞键会
//   互相覆盖，重启后只剩一条且 attachment/localPath 错乱。
// - 自动下载完成后内存与库里的 localPath 都要落到对应那一条。
//
// 下方 fakes 复制自 chat_session_provider_test.dart。
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
  int sendCount = 0; // 已发送消息数（断线队列误发检测）
  final sentSessionIds = <String>[]; // 每次 sendMessage 时 http 携带的 sessionId

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
    sendCount++;
    sentSessionIds.add(_sid);
    return 'msg_id';
  }

  @override
  Future<({UploadResult? result, String? error})> uploadFile(File file,
      String contentType,
      {void Function(int sent, int total)? onProgress}) async {
    return (result: null, error: null);
  }

  /// url → 下载结果（测试注入）。
  final Map<String, File> downloads = {};

  @override
  Future<File?> downloadByUrl(String url,
          {void Function(int received, int? total)? onProgress}) async =>
      downloads[url];

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

  /// 测试 seam：手动播报连接状态（模拟断线/重连中）。
  void emitState(ConnState s) => _states.add(s);

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
    final c = _FakeClient(sessionId);
    return c;
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

  BotApiEvent media(String type, Object content) =>
      BotApiEvent.fromSse('message', {'type': type, 'content': content});

  test('同一时刻连续到达的多条媒体事件各自独立落库，不互相覆盖', () async {
    final n = await makeNotifier();
    final tmp = Directory.systemTemp.createTempSync('media_evt');
    final img = File('${tmp.path}/a.png')..writeAsBytesSync([1, 2, 3]);
    final voice = File('${tmp.path}/v.m4a')..writeAsBytesSync([4, 5]);
    n._fakeHttp.downloads['http://h/a.png'] = img;
    n._fakeHttp.downloads['http://h/v.m4a'] = voice;

    // 不 await：模拟 SSE 在同一事件循环片段里连推三条。
    final f1 = n.handleEventForTest(media('image', 'http://h/a.png'));
    final f2 = n.handleEventForTest(
        media('file', {'name': 'r.pdf', 'url': 'http://h/r.pdf'}));
    final f3 = n.handleEventForTest(media('audio', 'http://h/v.m4a'));
    await Future.wait([f1, f2, f3]);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final bots = n.state.messages.where((m) => !m.isFromMe).toList();
    expect(bots.length, 3);
    expect(bots.map((m) => m.createdAt).toSet().length, 3,
        reason: 'created_at 是本地库 upsert 键，必须唯一');

    // 内存：自动下载结果落到对应消息。
    final image = bots.firstWhere((m) => m.msgType == 'image');
    final audio = bots.firstWhere((m) => m.msgType == 'audio');
    expect(image.localPath, img.path);
    expect(audio.localPath, voice.path);

    // 库：三条都在，且各自字段正确（重启后看到的就是这个）。
    final rows = await CacheService().getMessages(
        accountId: '${n.state.currentAccountId}:${n.state.currentSessionId}');
    final dbBots = rows.where((m) => !m.isFromMe).toList();
    expect(dbBots.length, 3);
    expect(dbBots.firstWhere((m) => m.msgType == 'image').attachmentId,
        'http://h/a.png');
    expect(dbBots.firstWhere((m) => m.msgType == 'image').localPath, img.path);
    expect(dbBots.firstWhere((m) => m.msgType == 'file').content, 'r.pdf');
    tmp.deleteSync(recursive: true);
  });

  test('本地消息 created_at 单调递增（连续发送不撞键）', () async {
    final n = await makeNotifier();
    n.sendText('a');
    n.sendText('b');
    final k = n.createPendingMedia(msgType: 'image', localPath: '/x.jpg');
    final mine = n.state.messages.where((m) => m.isFromMe).toList();
    expect(mine.length, 3);
    expect(mine.map((m) => m.createdAt).toSet().length, 3);
    expect(mine.last.createdAt, k);
    expect(mine[0].createdAt < mine[1].createdAt, isTrue);
    expect(mine[1].createdAt < mine[2].createdAt, isTrue);
  });

  test('删除最后一个账户：清空残留的消息与会话', () async {
    final n = await makeNotifier();
    n.sessions = [
      const ChatSession(id: 'default', name: '默认会话'),
      const ChatSession(id: 's1', name: '旅行计划'),
    ];
    await n.selectSession('s1');
    await n.handleEventForTest(BotApiEvent.fromSse(
        'message', {'type': 'text', 'content': 'hi', 'final': true, 'session_id': 's1'}));
    expect(n.state.messages, isNotEmpty);
    expect(n.state.currentSessionName, '旅行计划');

    await n.deleteAccount(n.state.currentAccountId);
    expect(n.state.accounts, isEmpty);
    expect(n.state.messages, isEmpty);
    expect(n.state.sessions, isEmpty);
    expect(n.state.currentSessionName, '默认会话');
  });
}
