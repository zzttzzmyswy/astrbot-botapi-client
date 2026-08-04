// test/cache_session_partition_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:astrbot_app/services/cache_service.dart';
import 'package:astrbot_app/models/message.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
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
    await c.insertMessage(const LocalMessage(
      msgType: 'text', content: 'in-default', isFromMe: false,
      status: MessageStatus.sent, createdAt: 1,
    ), accountId: 'acc1:default');
    await c.insertMessage(const LocalMessage(
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
    await c.insertMessage(const LocalMessage(
      msgType: 'text', content: 'a', isFromMe: false,
      status: MessageStatus.sent, createdAt: 1,
    ), accountId: 'acc1:default');
    await c.insertMessage(const LocalMessage(
      msgType: 'text', content: 'b', isFromMe: false,
      status: MessageStatus.sent, createdAt: 2,
    ), accountId: 'acc1:abc');
    await c.clearSession('acc1');
    expect(await c.getMessageCount(accountId: 'acc1:default'), 0);
    expect(await c.getMessageCount(accountId: 'acc1:abc'), 0);
  });
}
