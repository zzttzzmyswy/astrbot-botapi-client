// test/session_store_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:astrbot_app/models/chat_session.dart';
import 'package:astrbot_app/services/session_store.dart' show SessionStore, SessionStorage, kDefaultSessionId;

class MemSessionStorage implements SessionStorage {
  final Map<String, String> _m = {};
  @override
  Future<String?> readString(String key) async => _m[key];
  @override
  Future<void> writeString(String key, String value) async { _m[key] = value; }
}

void main() {
  test('add/rename/delete/list', () async {
    final store = SessionStore(MemSessionStorage());
    await store.load();
    await store.add('acc1', '工作');
    final s = await store.list('acc1');
    expect(s.length, 1);
    expect(s.first.name, '工作');
    await store.rename('acc1', s.first.id, '新名');
    expect((await store.list('acc1')).first.name, '新名');
    await store.delete('acc1', s.first.id);
    expect((await store.list('acc1')).isEmpty, true);
  });

  test('per-account current session', () async {
    final store = SessionStore(MemSessionStorage());
    await store.load();
    await store.add('acc1', 'A');
    await store.add('acc1', 'B');
    final list = await store.list('acc1');
    await store.setCurrent('acc1', list[1].id);
    expect(await store.getCurrent('acc1'), list[1].id);
    expect(await store.getCurrent('acc2'), null);
  });

  test('clearCurrent removes current record', () async {
    final store = SessionStore(MemSessionStorage());
    await store.load();
    await store.add('acc1', 'A');
    final list = await store.list('acc1');
    await store.setCurrent('acc1', list.first.id);
    expect(await store.getCurrent('acc1'), list.first.id);
    await store.clearCurrent('acc1');
    expect(await store.getCurrent('acc1'), null);
  });

  test('cap 25', () async {
    final store = SessionStore(MemSessionStorage());
    await store.load();
    for (var i = 0; i < 26; i++) {
      await store.add('acc1', 's$i');
    }
    expect((await store.list('acc1')).length, 25);
  });

  test('replaceAll filters out default session', () async {
    final store = SessionStore(MemSessionStorage());
    await store.load();
    // 模拟服务端返回包含 default 的列表（不应该发生，但防御性处理）
    final sessions = [
      const ChatSession(id: kDefaultSessionId, name: '默认会话'),
      const ChatSession(id: 'explicit1', name: 'Explicit 1'),
      const ChatSession(id: 'explicit2', name: 'Explicit 2'),
    ];
    await store.replaceAll('acc1', sessions);
    final list = await store.list('acc1');
    expect(list.length, 2);
    expect(list.map((s) => s.id).toList(), ['explicit1', 'explicit2']);
  });
}
