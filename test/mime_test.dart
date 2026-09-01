// test/mime_test.dart
//
// MIME 推断：语音发送从 wav 切到 AAC(m4a) 后，发送 MIME 应随扩展名变化，
// 服务端凭 audio/* 前缀把文件映射为 Record 语音消息。
import 'package:flutter_test/flutter_test.dart';
import 'package:astrbot_app/util/mime.dart';

void main() {
  group('mimeForExtension', () {
    test('m4a → audio/mp4', () {
      expect(mimeForExtension('draft_record.m4a'), 'audio/mp4');
      expect(mimeForExtension('/tmp/rec/draft_record.m4a'), 'audio/mp4');
    });
    test('aac/mp3/wav/ogg', () {
      expect(mimeForExtension('a.aac'), 'audio/aac');
      expect(mimeForExtension('a.mp3'), 'audio/mpeg');
      expect(mimeForExtension('a.wav'), 'audio/wav');
      expect(mimeForExtension('a.ogg'), 'audio/ogg');
      expect(mimeForExtension('a.opus'), 'audio/ogg');
    });
    test('图片/文档/压缩包', () {
      expect(mimeForExtension('x.jpg'), 'image/jpeg');
      expect(mimeForExtension('x.png'), 'image/png');
      expect(mimeForExtension('x.pdf'), 'application/pdf');
      expect(mimeForExtension('x.docx'), 'application/vnd.openxmlformats-officedocument.wordprocessingml.document');
      expect(mimeForExtension('x.zip'), 'application/zip');
      expect(mimeForExtension('x.mp4'), 'video/mp4');
    });
    test('无扩展名/大写扩展名/未知', () {
      expect(mimeForExtension('noext'), 'application/octet-stream');
      expect(mimeForExtension('a.M4A'), 'audio/mp4');
      expect(mimeForExtension('a.bin'), 'application/octet-stream');
      expect(mimeForExtension(''), 'application/octet-stream');
    });
  });

  group('mimeForMediaSend', () {
    test('语音 m4a → audio/mp4（AAC 新版本）', () {
      expect(mimeForMediaSend('/tmp/draft_record.m4a', 'voice'), 'audio/mp4');
    });
    test('语音 aac/mp3 → 对应音频 mime', () {
      expect(mimeForMediaSend('/tmp/v.aac', 'voice'), 'audio/aac');
      expect(mimeForMediaSend('/tmp/v.mp3', 'voice'), 'audio/mpeg');
    });
    test('语音老 wav → audio/wav（兼容旧录音重试）', () {
      expect(mimeForMediaSend('/tmp/v.wav', 'voice'), 'audio/wav');
    });
    test('图片 → image/jpeg', () {
      expect(mimeForMediaSend('/tmp/p.png', 'image'), 'image/jpeg');
    });
    test('文件走扩展名推断', () {
      expect(mimeForMediaSend('/tmp/report.pdf', 'file'), 'application/pdf');
    });
  });
}