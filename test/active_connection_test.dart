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
