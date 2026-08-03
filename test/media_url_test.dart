// test/media_url_test.dart
//
// 验证媒体下载 URL 规整:服务端 file 事件的 url 可能是相对路径(/files/xxx),
// dio 无法解析 host 会 connectionError;相对路径须拼 serverUrl origin。
import 'package:flutter_test/flutter_test.dart';
import 'package:astrbot_app/services/botapi_http.dart';

void main() {
  group('resolveMediaUrl', () {
    test('绝对 URL 原样返回', () {
      const url = 'https://cdn.example.com/files/abc.pdf';
      expect(resolveMediaUrl(url, 'https://astrbot.example.com'),
          'https://cdn.example.com/files/abc.pdf');
    });

    test('相对路径拼 serverUrl origin', () {
      expect(
        resolveMediaUrl('/files/abc.pdf', 'https://astrbot.example.com'),
        'https://astrbot.example.com/files/abc.pdf',
      );
    });

    test('相对路径无前导斜杠自动补', () {
      expect(
        resolveMediaUrl('files/abc.pdf', 'https://astrbot.example.com'),
        'https://astrbot.example.com/files/abc.pdf',
      );
    });

    test('serverUrl 带 /api/v1/botapi 后缀:origin 去掉路径部分', () {
      expect(
        resolveMediaUrl('/files/abc.pdf', 'https://astrbot.example.com/api/v1/botapi'),
        'https://astrbot.example.com/files/abc.pdf',
      );
    });

    test('serverUrl 带尾斜杠:去尾斜杠再取 origin', () {
      expect(
        resolveMediaUrl('/files/abc.pdf', 'https://astrbot.example.com/'),
        'https://astrbot.example.com/files/abc.pdf',
      );
    });

    test('带端口的 serverUrl', () {
      expect(
        resolveMediaUrl('/files/abc.pdf', 'http://192.168.1.10:6185'),
        'http://192.168.1.10:6185/files/abc.pdf',
      );
    });
  });

  group('BotApiHttp.authHeaders', () {
    test('包含 Bearer token', () {
      final http = BotApiHttp(serverUrl: 'https://test.example.com', token: 'tok123');
      expect(http.authHeaders, {'Authorization': 'Bearer tok123'});
    });
  });
}
