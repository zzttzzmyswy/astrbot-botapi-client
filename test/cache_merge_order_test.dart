// test/cache_merge_order_test.dart
//
// CacheService 真库（sqflite ffi 内存库）回归：
// - 同一 created_at 的行按落库顺序返回（思考不跑到正文之后）
// - mergeHistory 关联本地实时行时同时置 sent（不再残留「发送中」）
// - 秒级服务端时间戳不会让后发生的行排到已贴 id 的毫秒级本地行之前
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:astrbot_app/models/history_row.dart';
import 'package:astrbot_app/models/message.dart';
import 'package:astrbot_app/services/cache_service.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  setUp(() {
    CacheService.dbPathOverride = inMemoryDatabasePath;
    CacheService.resetDbForTesting();
  });
  tearDown(() => CacheService.resetDbForTesting());

  // 内存库在同进程内共享，每个用例用独立分区避免串数据。
  var seq = 0;
  late String part;
  setUp(() => part = 'acc${seq++}:default');

  test('同秒历史行按服务端行序返回：思考在正文之前', () async {
    final c = CacheService();
    await c.mergeHistory(const [
      HistoryRow(messageId: 1, role: 'user', type: 'text', content: 'q', timestamp: 100),
      HistoryRow(messageId: 2, role: 'assistant', type: 'thinking', content: 't', timestamp: 200),
      HistoryRow(messageId: 3, role: 'assistant', type: 'text', content: 'a', timestamp: 200),
    ], accountId: part);
    final rows = await c.getMessages(accountId: part);
    expect(rows.map((m) => m.content).toList(), ['q', 't', 'a']);
  });

  test('关联本地实时行时置 sent', () async {
    final c = CacheService();
    await c.insertMessage(
        const LocalMessage(
            msgType: 'text',
            content: 'hello',
            isFromMe: true,
            status: MessageStatus.pending,
            createdAt: 100500),
        accountId: part);
    await c.mergeHistory(const [
      HistoryRow(messageId: 7, role: 'user', type: 'text', content: 'hello', timestamp: 100),
    ], accountId: part);
    final rows = await c.getMessages(accountId: part);
    expect(rows.single.serverId, 7);
    expect(rows.single.status, MessageStatus.sent);
  });

  test('秒级截断的后续行不排到同秒的本地毫秒行之前', () async {
    final c = CacheService();
    // 本地用户消息 100.567s 发出，服务端记为 100s；工具状态同秒、id 更大。
    await c.insertMessage(
        const LocalMessage(
            msgType: 'text',
            content: 'go',
            isFromMe: true,
            status: MessageStatus.sent,
            createdAt: 100567),
        accountId: part);
    await c.mergeHistory(const [
      HistoryRow(messageId: 10, role: 'user', type: 'text', content: 'go', timestamp: 100),
      HistoryRow(messageId: 11, role: 'assistant', type: 'tool_status', content: 'tool', timestamp: 100),
    ], accountId: part);
    final rows = await c.getMessages(accountId: part);
    expect(rows.map((m) => m.content).toList(), ['go', 'tool']);
  });

  test('真实时钟差（>1s）不被改写', () async {
    final c = CacheService();
    await c.mergeHistory(const [
      HistoryRow(messageId: 1, role: 'user', type: 'text', content: 'x', timestamp: 500),
      HistoryRow(messageId: 2, role: 'assistant', type: 'text', content: 'y', timestamp: 100),
    ], accountId: part);
    final rows = await c.getMessages(accountId: part);
    final y = rows.firstWhere((m) => m.content == 'y');
    expect(y.createdAt, 100000);
  });
}
