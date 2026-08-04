// lib/services/session_store.dart
//
// 会话注册表纯逻辑（依赖 SessionStorage 抽象，便于单测用内存实现）。
// 职责：按账户加载/持久化会话列表与当前会话 id；增删改；25 上限；切换当前会话。
// 注：本地不持久化默认会话（id="default"）。"default" 是隐式会话：
// 账户无任何会话时，上层（provider）回退用 id="default"，且发消息/拉历史/连流
// 时省略 session_id（兼容老服务器）。本 store 只管理显式创建的会话。
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/chat_session.dart';

abstract class SessionStorage {
  Future<String?> readString(String key);
  Future<void> writeString(String key, String value);
}

const _kSessionsKey = 'sessions_v1';
const _kCurrentKey = 'current_session_v1';

/// 单账户最多保留的会话数（产品约束）。
const int kMaxSessionsPerAccount = 25;

/// 隐式默认会话 id：无会话时的回退；发消息/拉历史/连流时省略 session_id。
const String kDefaultSessionId = 'default';

class SessionStore {
  final SessionStorage _storage;
  SessionStore(this._storage);

  Map<String, List<ChatSession>> _byAccount = {};
  Map<String, String> _currentByAccount = {};
  bool _loaded = false;

  void _ensureLoaded() {
    if (!_loaded) {
      throw StateError('SessionStore 未加载，先调用 load()');
    }
  }

  Future<void> load() async {
    _byAccount = {};
    _currentByAccount = {};
    final raw = await _storage.readString(_kSessionsKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final obj = jsonDecode(raw);
        if (obj is Map) {
          obj.forEach((k, v) {
            if (k is String && v is List) {
              _byAccount[k] = v
                  .whereType<Map>()
                  .map((e) => ChatSession.fromJson(Map<String, dynamic>.from(e)))
                  .toList();
            }
          });
        }
      } catch (_) {
        _byAccount = {}; // 损坏 JSON 不致命
      }
    }
    final cur = await _storage.readString(_kCurrentKey);
    if (cur != null && cur.isNotEmpty) {
      try {
        final obj = jsonDecode(cur);
        if (obj is Map) {
          obj.forEach((k, v) {
            if (k is String && v is String) _currentByAccount[k] = v;
          });
        }
      } catch (_) {}
    }
    _loaded = true;
  }

  /// 某账户的会话列表。无会话返回空列表（非 null）。
  Future<List<ChatSession>> list(String accountId) async {
    _ensureLoaded();
    return List.unmodifiable(_byAccount[accountId] ?? const []);
  }

  /// 新增会话。已达 25 上限返回 null。
  Future<ChatSession?> add(String accountId, String name) async {
    _ensureLoaded();
    final list = _byAccount[accountId] ?? const <ChatSession>[];
    if (list.length >= kMaxSessionsPerAccount) return null;
    final s = ChatSession(id: _uuid(), name: name);
    _byAccount[accountId] = [...list, s];
    await _persist();
    return s;
  }

  Future<bool> rename(String accountId, String sessionId, String name) async {
    _ensureLoaded();
    final list = _byAccount[accountId];
    if (list == null) return false;
    final idx = list.indexWhere((s) => s.id == sessionId);
    if (idx < 0) return false;
    final updated = [...list]..[idx] = list[idx].copyWith(name: name);
    _byAccount[accountId] = updated;
    await _persist();
    return true;
  }

  Future<bool> delete(String accountId, String sessionId) async {
    _ensureLoaded();
    final list = _byAccount[accountId];
    if (list == null) return false;
    _byAccount[accountId] = list.where((s) => s.id != sessionId).toList();
    if (_currentByAccount[accountId] == sessionId) {
      _currentByAccount.remove(accountId);
    }
    await _persist();
    return true;
  }

  /// 某账户当前会话 id；未设置返回 null。
  Future<String?> getCurrent(String accountId) async {
    _ensureLoaded();
    return _currentByAccount[accountId];
  }

  Future<void> setCurrent(String accountId, String sessionId) async {
    _ensureLoaded();
    _currentByAccount[accountId] = sessionId;
    await _persist();
  }

  /// 整表替换某账户的会话列表（服务端权威镜像）。会话 id 以服务端为准，
  /// 不重新生成本地 id。用于 connect 拉权威列表、以及 create/rename/delete 后同步。
  Future<void> replaceAll(String accountId, List<ChatSession> sessions) async {
    _ensureLoaded();
    _byAccount[accountId] = List<ChatSession>.of(sessions);
    await _persist();
  }

  /// 删除某账户的全部会话与当前会话记录（删除账户时级联清理）。
  Future<void> clearForAccount(String accountId) async {
    _ensureLoaded();
    _byAccount.remove(accountId);
    _currentByAccount.remove(accountId);
    await _persist();
  }

  Future<void> _persist() async {
    final obj = <String, dynamic>{};
    _byAccount.forEach((k, v) => obj[k] = v.map((s) => s.toJson()).toList());
    await _storage.writeString(_kSessionsKey, jsonEncode(obj));
    await _storage.writeString(_kCurrentKey, jsonEncode(_currentByAccount));
  }
}

int _uuidCounter = 0;

/// 本地会话 id：时间戳 + 自增计数器（避免同毫秒多 add 碰撞）。
String _uuid() {
  _uuidCounter += 1;
  return '${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}${_uuidCounter.toRadixString(36)}';
}

/// 生产用 SharedPreferences 包装。
class PrefsSessionStorage implements SessionStorage {
  final SharedPreferences _prefs;
  PrefsSessionStorage(this._prefs);
  @override
  Future<String?> readString(String key) async => _prefs.getString(key);
  @override
  Future<void> writeString(String key, String value) async =>
      _prefs.setString(key, value);
}
