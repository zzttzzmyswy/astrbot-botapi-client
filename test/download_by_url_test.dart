// test/download_by_url_test.dart
//
// BotApiHttp.downloadByUrl 端到端（进程内 HttpServer + 假 path_provider）：
// 首次下载时 .part 尚不存在。旧实现一上来 `await part.length()`，对不存在的
// 文件抛 PathNotFoundException，被外层 catch 吞成 null —— 所有首次媒体下载
// 都失败，对方发来的图片/文件/语音永远停在占位态。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:astrbot_app/services/botapi_http.dart';

class _FakePaths extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  _FakePaths(this.dir);
  final String dir;
  @override
  Future<String?> getApplicationDocumentsPath() async => dir;
  @override
  Future<String?> getTemporaryPath() async => dir;
}

void main() {
  late HttpServer server;
  late Directory tmp;
  final payload = List<int>.generate(4096, (i) => i % 251);

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('dl_by_url');
    PathProviderPlatform.instance = _FakePaths(tmp.path);
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) {
      req.response.headers.contentType = ContentType('image', 'png');
      req.response.add(payload);
      req.response.close();
    });
  });

  tearDown(() async {
    await server.close(force: true);
    tmp.deleteSync(recursive: true);
  });

  test('首次下载（无 .part）成功落盘并返回文件', () async {
    final base = 'http://127.0.0.1:${server.port}';
    final h = BotApiHttp(serverUrl: base, token: 't');
    final f = await h.downloadByUrl('$base/files/pic.png');
    expect(f, isNotNull);
    expect(await f!.readAsBytes(), payload);
    expect(File('${f.path}.part').existsSync(), isFalse);
  });
}
