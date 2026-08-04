// test/account_drawer_test.dart
//
// 两级抽屉（账户 → 会话面板）widget 测试。
//
// 测试策略说明：
// 本抽屉（AccountDrawer）在真实环境由 ProviderScope 解析 configServiceProvider
// 构造 ChatNotifier；ChatNotifier 依赖 SharedPreferences、sqflite 内存库、
// Connectivity、record（方法通道）等。要在 widget 测试中驱动「点账户 → 选会话」,
// 需要 ChatNotifier 正常工作（selectAccount 会 connect() 拉会话列表）。本测试把
// chatProvider 覆写为「预先登录一个账户」的 _TestNotifier（注入假 http/client）,
// 抽屉在 ProviderScope + MaterialApp + Scaffold 中真实渲染、真实交互,并断言
// notifier 状态与方法调用。
//
// 计时要点：ChatNotifier.connect() 使用 sqflite 内存库。这里选用
// databaseFactoryFfiNoIsolate（同步 FFI,无 isolate/端口往返,不依赖 FakeAsync
// 计时器即可完成）,且 connect() 的 auth/fetch 均被假实现短路为同步 future。
// 因此每个 await 都由 pumpAndSettle 排空（其内部 flush 微任务与到期定时器）,
// 无需真实 sleep,也不会命中 pump(duration) 只能推进 FakeAsync 计时的限制。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:connectivity_plus_platform_interface/connectivity_plus_platform_interface.dart';

import 'package:astrbot_app/models/account.dart';
import 'package:astrbot_app/models/botapi_event.dart';
import 'package:astrbot_app/models/chat_session.dart';
import 'package:astrbot_app/models/history_row.dart';
import 'package:astrbot_app/providers/chat_provider.dart';
import 'package:astrbot_app/providers/config_provider.dart';
import 'package:astrbot_app/services/botapi_client.dart';
import 'package:astrbot_app/services/botapi_http.dart';
import 'package:astrbot_app/services/cache_service.dart';
import 'package:astrbot_app/services/config_service.dart';
import 'package:astrbot_app/widgets/account_drawer.dart';

class _FakeConnectivityPlatform extends ConnectivityPlatform {
  @override
  Future<List<ConnectivityResult>> checkConnectivity() async =>
      [ConnectivityResult.wifi];
  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      const Stream.empty();
}

/// 假 REST 客户端：会话/历史/媒体全部内存实现,不联网。
class _FakeHttp implements BotApiHttp {
  List<ChatSession> sessions = const [];

  @override
  String get serverUrl => 'http://fake';
  @override
  String get token => 't';
  @override
  String get sessionId => '';
  @override
  Map<String, String> get authHeaders => {'Authorization': 'Bearer t'};

  @override
  Future<bool> auth() async => true;

  @override
  Future<String?> sendMessage({String? text, List<String>? fileIds}) async =>
      'msg_id';

  @override
  Future<({UploadResult? result, String? error})> uploadFile(File file,
      String contentType,
      {void Function(int sent, int total)? onProgress}) async {
    return (result: null, error: null);
  }

  @override
  Future<File?> downloadByUrl(String url) async => null;

  @override
  Future<List<ChatSession>> fetchSessions() async => sessions;

  @override
  Future<HistoryResult> fetchHistory(
          {int? since, int? before, int limit = 50}) async =>
      const HistoryResult(messages: [], hasMore: false);

  @override
  Future<ChatSession?> createSession(String name) async {
    final s = ChatSession(id: 's_${sessions.length}', name: name);
    sessions = [...sessions, s];
    return s;
  }

  @override
  Future<bool> renameSession(String sid, String name) async {
    sessions =
        sessions.map((s) => s.id == sid ? s.copyWith(name: name) : s).toList();
    return true;
  }

  @override
  Future<bool> deleteSession(String sid) async {
    sessions = sessions.where((s) => s.id != sid).toList();
    return true;
  }
}

/// 假 SSE 客户端：connect 恒连,不真正联网。
class _FakeClient implements BotApiClient {
  @override
  String get serverUrl => 'http://fake';
  @override
  String get token => 't';
  @override
  String get sessionId => '';
  @override
  Stream<BotApiEvent> get events => const Stream.empty();
  @override
  Stream<ConnState> get state => const Stream.empty();
  @override
  set sinceCursor(int? c) {}
  @override
  Future<void> connect({int? sinceCursor}) async {}
  @override
  Future<http.StreamedResponse> sendRequest(
          http.Client client, http.Request request) async =>
      throw StateError('_FakeClient 不实际联网');
  @override
  Future<void> dispose() async {}
  @override
  bool get isDisposed => false;
}

/// 测试子类：注入假 http/client,构造即登录一个账户。
class _TestNotifier extends ChatNotifier {
  _TestNotifier(super.config);

  final fakeHttp = _FakeHttp();
  bool added = false;

  @override
  BotApiHttp buildHttp(Account acc, {String sessionId = ''}) => fakeHttp;

  @override
  BotApiClient buildClient(Account acc, {String sessionId = ''}) =>
      _FakeClient();

  /// 登录一个账户（幂等）：先于首帧 connect 前预置,使抽屉一打开即有账户。
  Future<void> ensureAccount() async {
    if (added) return;
    added = true;
    await addAccount(
        serverUrl: 'http://fake/api/v1/botapi',
        token: 'tok1',
        label: 'BotA');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  // 同步 FFI 工厂：无 isolate 往返,配合 FakeAsync（testWidgets）可完成。
  databaseFactory = databaseFactoryFfiNoIsolate;

  // record 插件的方法通道：测试环境无平台实现,抽屉不录音,替换为恒 true。
  const recordChannel = MethodChannel('com.llfbandit.record/methods');

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ConnectivityPlatform.instance = _FakeConnectivityPlatform();
    CacheService.dbPathOverride = inMemoryDatabasePath;
    CacheService.resetDbForTesting();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(recordChannel, (call) async => true);
  });

  tearDown(() {
    CacheService.resetDbForTesting();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(recordChannel, null);
  });

  /// 构造抽屉测试环境并打开抽屉。
  /// 返回已登录的 [ChatNotifier],供断言状态/方法调用。
  Future<ChatNotifier> pumpDrawer(
    WidgetTester tester, {
    List<ChatSession> sessions = const [],
  }) async {
    final config = ConfigService();
    await config.init();
    final notifier = _TestNotifier(config);
    notifier.fakeHttp.sessions = sessions;
    await notifier.ensureAccount();
    // 注意：notifier 由 ProviderScope element 持有并在其 dispose 时统一释放,
    // 不要再 addTearDown(notifier.dispose),否则与容器销毁造成二次 dispose。

    await tester.pumpWidget(ProviderScope(
      overrides: [
        configServiceProvider.overrideWithValue(config),
        chatProvider.overrideWith((ref) => notifier),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => Center(
              child: Builder(
                builder: (innerCtx) => TextButton(
                  onPressed: () => Scaffold.of(innerCtx).openDrawer(),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
          drawer: const AccountDrawer(),
        ),
      ),
    ));

    // 打开抽屉
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // 让 connect() 内部同步 FFI 工作排空（假实现也全同步）。
    await tester.pumpAndSettle();
    return notifier;
  }

  testWidgets('点账户 → 打开该账户的会话面板；返回 → 回到账户列表', (tester) async {
    final n = await pumpDrawer(tester, sessions: const [
      ChatSession(id: 'default', name: '默认会话'),
      ChatSession(id: 's1', name: '工作'),
      ChatSession(id: 's2', name: '生活'),
    ]);
    expect(n.state.accounts.map((a) => a.displayName), contains('BotA'));

    // 账户列表可见
    expect(find.text('账户'), findsOneWidget);

    // 点账户 tile → 会话面板
    await tester.tap(find.text('BotA'));
    await tester.pumpAndSettle();

    // 面板标题为账户名 + 返回键；「账户」标题消失
    expect(find.byIcon(Icons.arrow_back_rounded), findsOneWidget);
    expect(find.text('默认会话'), findsOneWidget);
    expect(find.text('工作'), findsOneWidget);
    expect(find.text('生活'), findsOneWidget);
    // 当前会话（默认）有「当前」徽标,非当前会话无
    expect(find.text('当前'), findsOneWidget);

    // 返回键 → 账户列表
    await tester.tap(find.byIcon(Icons.arrow_back_rounded));
    await tester.pumpAndSettle();
    expect(find.text('账户'), findsOneWidget);
    expect(find.text('BotA'), findsOneWidget);
    expect(find.text('默认会话'), findsNothing);
  });

  testWidgets('当前会话显示「当前」徽标；默认会话无删除按钮', (tester) async {
    await pumpDrawer(tester, sessions: const [
      ChatSession(id: 'default', name: '默认会话'),
      ChatSession(id: 's1', name: '工作'),
    ]);

    await tester.tap(find.text('BotA'));
    await tester.pumpAndSettle();

    // 当前会话（默认）行有「当前」徽标
    expect(find.text('当前'), findsOneWidget);

    // 打开默认会话菜单：无「删除」项（默认会话不可删）
    final defaultMenu = find.descendant(
        of: find.ancestor(
            of: find.text('默认会话'), matching: find.byType(InkWell)),
        matching: find.byIcon(Icons.more_horiz));
    await tester.tap(defaultMenu);
    await tester.pumpAndSettle();
    expect(find.text('重命名'), findsOneWidget);
    expect(find.text('删除'), findsNothing);

    // 关闭菜单（点菜单外）
    await tester.tapAt(const Offset(400, 300));
    await tester.pumpAndSettle();

    // 打开「工作」会话菜单：有「删除」
    final workMenu = find.descendant(
        of: find.ancestor(
            of: find.text('工作'), matching: find.byType(InkWell)),
        matching: find.byIcon(Icons.more_horiz));
    await tester.tap(workMenu);
    await tester.pumpAndSettle();
    expect(find.text('重命名'), findsOneWidget);
    expect(find.text('删除'), findsOneWidget);
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    // 确认删除对话框
    expect(find.text('删除会话'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
  });

  testWidgets('点会话 → 调用 selectSession 并关闭抽屉', (tester) async {
    final n = await pumpDrawer(tester, sessions: const [
      ChatSession(id: 'default', name: '默认会话'),
      ChatSession(id: 's1', name: '工作'),
    ]);
    expect(n.state.currentSessionId, 'default');

    await tester.tap(find.text('BotA'));
    await tester.pumpAndSettle();

    // 点「工作」会话 → selectSession('s1') + 抽屉关闭
    await tester.tap(find.text('工作'));
    await tester.pumpAndSettle();

    expect(n.state.currentSessionId, 's1');
    // 抽屉已关闭：会话面板标题「工作」不可见
    expect(find.text('工作'), findsNothing);
    expect(find.text('账户'), findsNothing);
  });

  testWidgets('新建会话 → 弹名称输入框 → 调用 createSession', (tester) async {
    final n = await pumpDrawer(tester, sessions: const [
      ChatSession(id: 'default', name: '默认会话'),
    ]);

    await tester.tap(find.text('BotA'));
    await tester.pumpAndSettle();

    // 点「新建会话」按钮
    await tester.tap(find.text('新建会话'));
    await tester.pumpAndSettle();

    // 输入名称并点创建
    await tester.enterText(find.byType(TextField), '工作');
    await tester.tap(find.text('创建'));
    await tester.pumpAndSettle();

    // createSession 被调用：会话面板出现新会话
    expect(n.state.sessions.map((s) => s.name), contains('工作'));
    expect(find.text('工作'), findsOneWidget);
  });
}
