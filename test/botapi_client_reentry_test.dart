// test/botapi_client_reentry_test.dart
import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
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
