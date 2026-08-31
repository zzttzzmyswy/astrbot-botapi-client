// test/cache_clear_local_path_test.dart
//
// 下载管理删除文件后清空消息 local_path 引用：气泡不再指向缺失文件，可重新下载。
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

  test('clearLocalPath 只清空匹配路径的 local_path，消息保留', () async {
    final c = CacheService();
    await c.insertMessage(const LocalMessage(
      msgType: 'image',
      localPath: '/data/attachments/pic_1.png',
      isFromMe: false,
      status: MessageStatus.sent,
      createdAt: 1,
    ), accountId: 'acc:default');
    await c.insertMessage(const LocalMessage(
      msgType: 'image',
      localPath: '/data/attachments/pic_2.png',
      isFromMe: false,
      status: MessageStatus.sent,
      createdAt: 2,
    ), accountId: 'acc:default');

    final affected =
        await c.clearLocalPath('/data/attachments/pic_1.png');
    expect(affected, 1);

    final rows = await c.getMessages();
    expect(rows.length, 2, reason: '消息行本身不删除');
    final pic1 = rows.singleWhere((m) => m.createdAt == 1);
    final pic2 = rows.singleWhere((m) => m.createdAt == 2);
    expect(pic1.localPath, isEmpty);
    expect(pic1.attachmentId, isNull); // 仍保留 URL 字段供重新下载
    expect(pic2.localPath, '/data/attachments/pic_2.png');
  });
}