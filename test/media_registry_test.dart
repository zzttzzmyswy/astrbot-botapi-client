// test/media_registry_test.dart
//
// 下载管理页数据源：消息行 + 附件目录合并、去重、过滤半成品、分类与排序。
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:astrbot_app/models/message.dart';
import 'package:astrbot_app/services/media_registry.dart';

void main() {
  late Directory tmp;
  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('media_registry_test_');
  });
  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  Future<File> touch(String name, {int modifiedMs = 1000}) async {
    final f = File('${tmp.path}/$name');
    await f.writeAsBytes(const [1, 2, 3]);
    await f.setLastModified(DateTime.fromMillisecondsSinceEpoch(modifiedMs));
    return f;
  }

  group('categoryFor*', () {
    test('消息类型分类', () {
      expect(categoryForMsgType('image'), DownloadCategory.image);
      expect(categoryForMsgType('photo'), DownloadCategory.image);
      expect(categoryForMsgType('voice'), DownloadCategory.audio);
      expect(categoryForMsgType('audio'), DownloadCategory.audio);
      expect(categoryForMsgType('record'), DownloadCategory.audio);
      expect(categoryForMsgType('file'), DownloadCategory.file);
      expect(categoryForMsgType('text'), DownloadCategory.file);
    });
    test('文件扩展名分类', () {
      expect(categoryForPath('a.JPG'), DownloadCategory.image);
      expect(categoryForPath('/x/y.png'), DownloadCategory.image);
      expect(categoryForPath('v.m4a'), DownloadCategory.audio);
      expect(categoryForPath('v.mp3'), DownloadCategory.audio);
      expect(categoryForPath('r.pdf'), DownloadCategory.file);
      expect(categoryForPath('noext'), DownloadCategory.file);
    });
  });

  group('MediaRegistry.build', () {
    test('消息行带现有文件 → 条目（file 用 content 作名,其余用文件名）', () async {
      final img = await touch('photo_1.png', modifiedMs: 2000);
      final file = await touch('report.pdf', modifiedMs: 3000);
      final entries = await MediaRegistry.build(
        messages: [
          LocalMessage(
              msgType: 'image',
              content: null,
              localPath: img.path,
              isFromMe: false,
              status: MessageStatus.sent,
              createdAt: 500),
          LocalMessage(
              msgType: 'file',
              content: '报告.pdf',
              localPath: file.path,
              isFromMe: false,
              status: MessageStatus.sent,
              createdAt: 600),
        ],
        attachmentsDir: tmp,
      );
      expect(entries.length, 2);
      final byName = {for (final e in entries) e.name: e};
      expect(byName['photo_1.png']!.category, DownloadCategory.image);
      expect(byName['photo_1.png']!.createdAt, 500);
      expect(byName['报告.pdf']!.name, '报告.pdf');
      expect(byName['报告.pdf']!.category, DownloadCategory.file);
      expect(byName['报告.pdf']!.fromMessage, isTrue);
    });

    test('消息行的文件已不存在 → 剔除（消息仍在,可重新下载）', () async {
      final gh = File('${tmp.path}/gone.png');
      final entries = await MediaRegistry.build(
        messages: [
          LocalMessage(
              msgType: 'image',
              localPath: gh.path,
              isFromMe: false,
              status: MessageStatus.sent,
              createdAt: 5),
        ],
        attachmentsDir: tmp,
      );
      expect(entries, isEmpty);
    });

    test('孤立文件补录 + 半成品 .part 过滤', () async {
      await touch('orphan.m4a', modifiedMs: 9000);
      await touch('half.zip.part', modifiedMs: 9000);
      await touch('.hidden', modifiedMs: 9000);
      final entries = await MediaRegistry.build(
        messages: const [],
        attachmentsDir: tmp,
      );
      expect(entries.length, 1);
      expect(entries.single.name, 'orphan.m4a');
      expect(entries.single.category, DownloadCategory.audio);
      expect(entries.single.createdAt, 9000);
      expect(entries.single.fromMessage, isFalse);
    });

    test('被消息引用的目录文件不重复出现', () async {
      final img = await touch('pic.png', modifiedMs: 4000);
      final entries = await MediaRegistry.build(
        messages: [
          LocalMessage(
              msgType: 'image',
              localPath: img.path,
              isFromMe: false,
              status: MessageStatus.sent,
              createdAt: 777),
        ],
        attachmentsDir: tmp,
      );
      expect(entries.length, 1);
      expect(entries.single.fromMessage, isTrue);
    });

    test('按时间倒序（消息与孤立混合）', () async {
      await touch('old.png', modifiedMs: 100);
      await touch('new.zip', modifiedMs: 9999);
      final entries = await MediaRegistry.build(
        messages: [
          LocalMessage(
              msgType: 'image',
              localPath: '${tmp.path}/old.png',
              isFromMe: false,
              status: MessageStatus.sent,
              createdAt: 100),
        ],
        attachmentsDir: tmp,
      );
      expect(entries.map((e) => e.name).toList(), ['new.zip', 'old.png']);
    });
  });
}