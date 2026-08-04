// lib/widgets/account_drawer.dart
//
// 左侧账户选择栏：列表/添加/重命名/编辑凭据/删除。最多 25（上限由 provider 拦截）。
// 点账户 tile 进入该账户的「会话面板」（两级导航：账户 → 会话）。
// 会话面板：会话列表 + 新建/重命名/删除 + 返回；默认会话无删除按钮。
// 风格与聊天页统一：accent 0xFF5B4BD6。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/account.dart';
import '../models/chat_session.dart';
import '../providers/chat_provider.dart';
import '../screens/account_editor_screen.dart';
import '../services/session_store.dart' show kDefaultSessionId;

/// 抽屉内部两个「视图」的导航状态：账户列表 or 某账户的会话面板。
/// 独立于 Navigator 维护，故保持 Drawer 打开；返回键切回账户列表。
class _ViewState {
  bool showSessions = false;
  Account? account;
}

class AccountDrawer extends ConsumerStatefulWidget {
  const AccountDrawer({super.key});
  @override
  ConsumerState<AccountDrawer> createState() => _AccountDrawerState();
}

class _AccountDrawerState extends ConsumerState<AccountDrawer> {
  /// 两级导航状态：放在 State 上，跨重建保持（点账户 → 会话面板时
  /// selectAccount 触发 connect 更新 state，若状态在 build 内新建会丢失）。
  final _ViewState _view = _ViewState();

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(chatProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final theme = _Theme(isDark: isDark);

    final accounts = state.accounts;
    final current = state.currentAccountId;

    return Drawer(
      backgroundColor: theme.bg,
      elevation: 0,
      width: 308,
      child: SafeArea(
        child: accounts.isEmpty
            ? _AccountListView(
                theme: theme,
                accounts: accounts,
                current: current,
                view: _view,
                onRefresh: () => ref.refresh(chatProvider),
                onNeedRebuild: () => setState(() {}),
              )
            : _TwoLevelView(
                theme: theme, view: _view, onNeedRebuild: () => setState(() {})),
      ),
    );
  }
}

/// 抽屉两级内容：底层「账户列表」→ 上层「会话面板」。
/// 切换只影响 Drawer 子树，不弹 Navigator 路由，故 Drawer 全程保持打开。
class _TwoLevelView extends ConsumerWidget {
  final _Theme theme;
  final _ViewState view;
  final VoidCallback onNeedRebuild;
  const _TwoLevelView({
    required this.theme,
    required this.view,
    required this.onNeedRebuild,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(chatProvider);
    final accounts = state.accounts;
    final current = state.currentAccountId;
    final acc = view.account;

    if (view.showSessions) {
      final accSafe = acc ?? _accountOf(state, current);
      return _SessionPanel(
        theme: theme,
        account: accSafe,
        sessions: state.sessions,
        currentSessionId: state.currentSessionId,
        onBack: () {
          view.showSessions = false;
          onNeedRebuild();
        },
        onSelect: (sid) {
          Navigator.of(context).pop(); // 关抽屉
          ref.read(chatProvider.notifier).selectSession(sid);
        },
        onCreate: (name) =>
            ref.read(chatProvider.notifier).createSession(name),
        onRename: (sid, name) =>
            ref.read(chatProvider.notifier).renameSession(sid, name),
        onDelete: (sid) =>
            ref.read(chatProvider.notifier).deleteSession(sid),
      );
    }

    return _AccountListView(
      theme: theme,
      accounts: accounts,
      current: current,
      view: view,
      onRefresh: () => ref.refresh(chatProvider),
      onNeedRebuild: onNeedRebuild,
    );
  }
}

Account _accountOf(ChatState state, String current) {
  for (final a in state.accounts) {
    if (a.id == current) return a;
  }
  return state.accounts.isNotEmpty ? state.accounts.first : _emptyAccount;
}

const Account _emptyAccount = Account(
    id: '?', serverUrl: '', token: '', createdAt: 0, lastUsedAt: 0);

class _AccountListView extends ConsumerWidget {
  final _Theme theme;
  final List<Account> accounts;
  final String current;
  final _ViewState view;
  final VoidCallback onRefresh;
  final VoidCallback onNeedRebuild;
  const _AccountListView({
    required this.theme,
    required this.accounts,
    required this.current,
    required this.view,
    required this.onRefresh,
    required this.onNeedRebuild,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
        child: Row(children: [
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                  colors: [Color(0xFF5B4BD6), Color(0xFF7661D8)]),
              borderRadius: BorderRadius.circular(9),
            ),
            child: const Icon(Icons.smart_toy_rounded,
                color: Colors.white, size: 18),
          ),
          const SizedBox(width: 10),
          Text('账户',
              style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: theme.fg)),
          const Spacer(),
          _NewButton(
              accent: theme.accent,
              isDark: theme.isDark,
              fg: theme.fg,
              onTap: () => _onNew(context, ref)),
        ]),
      ),
      Divider(height: 1, thickness: 0.5, color: theme.div),
      Expanded(
        child: accounts.isEmpty
            ? _Empty(sub: theme.sub)
            : ListView(
                padding: const EdgeInsets.symmetric(vertical: 6),
                children: [
                  for (final a in accounts)
                    _AccountTile(
                      name: a.displayName,
                      subtitle:
                          '${_host(a.serverUrl)} · ${_relTime(a.lastUsedAt)}',
                      isCurrent: a.id == current,
                      isDark: theme.isDark,
                      card: theme.card,
                      cardActive: theme.cardActive,
                      fg: theme.fg,
                      sub: theme.sub,
                      accent: theme.accent,
                      onTap: () {
                        // 两级导航：先选中该账户（selectAccount→connect 拉其会话），
                        // 再展示其会话面板。sessionId 切换经 connect() 反映。
                        view.account = a;
                        view.showSessions = true;
                        onNeedRebuild(); // 面板视图在 State 上,需主动触发重建
                        ref.read(chatProvider.notifier).selectAccount(a.id);
                      },
                      onRename: () => _onRename(context, ref, a),
                      onEdit: () => _onEdit(context, a),
                      onDelete: () => _onDelete(context, ref, a),
                    ),
                ],
              ),
      ),
    ]);
  }

  String _host(String url) {
    try {
      final h = Uri.parse(url).host;
      return h.isNotEmpty
          ? h
          : (url.length > 24 ? '${url.substring(0, 24)}…' : url);
    } catch (_) {
      return url.length > 24 ? '${url.substring(0, 24)}…' : url;
    }
  }

  String _relTime(int ms) {
    final diff = DateTime.now().millisecondsSinceEpoch - ms;
    if (diff < 60000) return '刚刚';
    if (diff < 3600000) return '${diff ~/ 60000}分钟前';
    if (diff < 86400000) return '${diff ~/ 3600000}小时前';
    if (diff < 7 * 86400000) return '${diff ~/ 86400000}天前';
    final d = DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toLocal();
    return '${d.month}-${d.day}';
  }

  void _onNew(BuildContext context, WidgetRef ref) async {
    final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(
        builder: (_) => const AccountEditorScreen()));
    if (ok == true && context.mounted) Navigator.of(context).pop();
  }

  void _onRename(BuildContext context, WidgetRef ref, Account a) {
    final ctrl = TextEditingController(text: a.label ?? a.displayName);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重命名账户'),
        content: TextField(
            controller: ctrl,
            autofocus: true,
            decoration: InputDecoration(
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                ref
                    .read(chatProvider.notifier)
                    .renameAccount(a.id, ctrl.text);
              },
              child: const Text('保存')),
        ],
      ),
    );
  }

  void _onEdit(BuildContext context, Account a) {
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => AccountEditorScreen(
              editId: a.id,
              initialLabel: a.label,
              initialServerUrl: a.serverUrl,
              initialToken: a.token,
            )));
  }

  void _onDelete(BuildContext context, WidgetRef ref, Account a) {
    showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除账户'),
        content: Text('确定删除「${a.displayName}」?该账户本地消息将被清除,且无法恢复。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('删除',
                  style: TextStyle(color: Colors.redAccent))),
        ],
      ),
    ).then((confirmed) async {
      if (confirmed == true) {
        if (!context.mounted) return;
        Navigator.of(context).pop();
        await ref.read(chatProvider.notifier).deleteAccount(a.id);
      }
    });
  }
}

/// 会话面板：返回 + 标题 + 新建按钮 + 会话列表。
/// 每项：tap 选中（关抽屉）；菜单 重命名/删除；当前会话显示「当前」徽标。
/// 默认会话（id == kDefaultSessionId）不显示删除项。
/// 账户切换未完成（state.currentAccountId != account.id）时显示 loading，
/// 避免误读/误操作旧账户会话；会话加载失败且无会话时显示错误提示。
class _SessionPanel extends ConsumerWidget {
  final _Theme theme;
  final Account account;
  final List<ChatSession> sessions;
  final String currentSessionId;
  final VoidCallback onBack;
  final ValueChanged<String> onSelect;
  final ValueChanged<String> onCreate;
  final void Function(String sid, String name) onRename;
  final ValueChanged<String> onDelete;
  const _SessionPanel({
    required this.theme,
    required this.account,
    required this.sessions,
    required this.currentSessionId,
    required this.onBack,
    required this.onSelect,
    required this.onCreate,
    required this.onRename,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 账户切换进行中：view.account 已被设为新账户，但 selectAccount/connect()
    // 尚未完成，state.currentAccountId 仍是旧账户、state.sessions 也还是旧账户
    // 的列表。此刻渲染会话列表会短暂显示旧账户会话，用户可能误点/误删。故在
    // currentAccountId 与面板账户一致前显示 loading，避免误操作旧账户会话。
    final state = ref.watch(chatProvider);
    final switching = state.currentAccountId != account.id;

    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(8, 10, 8, 8),
        child: Row(children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: onBack,
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Icon(Icons.arrow_back_rounded,
                    size: 20, color: theme.fg),
              ),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(account.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: theme.fg)),
          ),
          const SizedBox(width: 8),
          _NewButton(
              accent: theme.accent,
              isDark: theme.isDark,
              fg: theme.fg,
              label: '新建会话',
              onTap: () => _promptNewSession(context, ref, onCreate)),
        ]),
      ),
      Divider(height: 1, thickness: 0.5, color: theme.div),
      Expanded(
        child: switching
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2.5)),
                      const SizedBox(height: 12),
                      Text('会话加载中…',
                          style: TextStyle(color: theme.sub, fontSize: 13)),
                    ],
                  ),
                ),
              )
            : sessions.isEmpty
                ? (state.sessionsError != null
                    ? _ErrorHint(sub: theme.sub, message: state.sessionsError!)
                    : _EmptySessions(sub: theme.sub))
                : ListView(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    children: [
                      for (final s in sessions)
                        _SessionTile(
                          session: s,
                          isCurrent: s.id == currentSessionId,
                          isDark: theme.isDark,
                          card: theme.card,
                          cardActive: theme.cardActive,
                          fg: theme.fg,
                          sub: theme.sub,
                          accent: theme.accent,
                          onTap: () => onSelect(s.id),
                          onRename: () =>
                              _promptRename(context, ref, s, onRename),
                          onDelete: s.id == kDefaultSessionId
                              ? null // 默认会话不可删除
                              : () => _confirmDelete(context, ref, s, onDelete),
                        ),
                    ],
                  ),
      ),
    ]);
  }

  Future<void> _promptNewSession(
      BuildContext context, WidgetRef ref, ValueChanged<String> onCreate) async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新建会话'),
        content: TextField(
            controller: ctrl,
            autofocus: true,
            decoration: InputDecoration(
                hintText: '会话名称',
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8)))),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('创建')),
        ],
      ),
    );
    if (name != null && name.isNotEmpty && context.mounted) {
      onCreate(name);
    }
  }

  Future<void> _promptRename(BuildContext context, WidgetRef ref,
      ChatSession s, void Function(String sid, String name) onRename) async {
    final ctrl = TextEditingController(text: s.name);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重命名会话'),
        content: TextField(
            controller: ctrl,
            autofocus: true,
            decoration: InputDecoration(
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('保存')),
        ],
      ),
    );
    if (name != null && name.isNotEmpty && context.mounted) {
      onRename(s.id, name);
    }
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref,
      ChatSession s, ValueChanged<String> onDelete) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除会话'),
        content: Text('确定删除会话「${s.name}」?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('删除',
                  style: TextStyle(color: Colors.redAccent))),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      onDelete(s.id);
    }
  }
}

/// 抽屉主题色板：与聊天页统一，两视图共享。
class _Theme {
  final bool isDark;
  const _Theme({required this.isDark});
  Color get accent => const Color(0xFF5B4BD6);
  Color get bg => isDark ? const Color(0xFF151518) : const Color(0xFFFAFAFB);
  Color get card => isDark ? const Color(0xFF212121) : const Color(0xFFF2F2F6);
  Color get cardActive =>
      isDark ? const Color(0xFF2A2A45) : const Color(0xFFECE9FB);
  Color get fg => isDark ? Colors.white : const Color(0xFF1C1C1E);
  Color get sub => isDark ? const Color(0xFF9E9EA4) : const Color(0xFF8A8A8E);
  Color get div => isDark ? const Color(0xFF2A2A2E) : const Color(0xFFE5E5EA);
}

class _NewButton extends StatelessWidget {
  final Color accent;
  final bool isDark;
  final Color fg;
  final VoidCallback onTap;
  final String label;
  const _NewButton(
      {required this.accent,
      required this.isDark,
      required this.fg,
      required this.onTap,
      this.label = '添加'});
  @override
  Widget build(BuildContext context) => Material(
        color: accent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.add_rounded, color: Colors.white, size: 18),
              const SizedBox(width: 2),
              Text(label,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600)),
            ]),
          ),
        ),
      );
}

class _AccountTile extends StatelessWidget {
  final String name, subtitle;
  final bool isCurrent, isDark;
  final Color card, cardActive, fg, sub, accent;
  final VoidCallback onTap, onRename, onEdit;
  final VoidCallback? onDelete;
  const _AccountTile({
    required this.name,
    required this.subtitle,
    required this.isCurrent,
    required this.isDark,
    required this.card,
    required this.cardActive,
    required this.fg,
    required this.sub,
    required this.accent,
    required this.onTap,
    required this.onRename,
    required this.onEdit,
    this.onDelete,
  });
  @override
  Widget build(BuildContext context) {
    final initial =
        name.isNotEmpty ? name.characters.first.toUpperCase() : '?';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      child: Material(
        color: isCurrent ? cardActive : card,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 6, 10),
            child: Row(
              children: [
                if (isCurrent)
                  Container(
                      width: 3,
                      height: 30,
                      decoration: BoxDecoration(
                          color: accent,
                          borderRadius: BorderRadius.circular(2))),
                if (isCurrent)
                  const SizedBox(width: 8)
                else
                  const SizedBox(width: 11),
                Container(
                    width: 38,
                    height: 38,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                        color: accent, borderRadius: BorderRadius.circular(12)),
                    child: Text(initial,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w700))),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: isCurrent
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: fg)),
                      const SizedBox(height: 2),
                      Text(subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11.5, color: sub)),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  icon: Icon(Icons.more_horiz, color: sub, size: 20),
                  padding: EdgeInsets.zero,
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'rename', child: Text('重命名')),
                    const PopupMenuItem(value: 'edit', child: Text('编辑凭据')),
                    if (onDelete != null)
                      const PopupMenuItem(
                          value: 'delete',
                          child: Text('删除',
                              style: TextStyle(color: Colors.redAccent))),
                  ],
                  onSelected: (v) {
                    if (v == 'rename') onRename();
                    if (v == 'edit') onEdit();
                    if (v == 'delete') onDelete?.call();
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SessionTile extends StatelessWidget {
  final ChatSession session;
  final bool isCurrent, isDark;
  final Color card, cardActive, fg, sub, accent;
  final VoidCallback onTap, onRename;
  final VoidCallback? onDelete;
  const _SessionTile({
    required this.session,
    required this.isCurrent,
    required this.isDark,
    required this.card,
    required this.cardActive,
    required this.fg,
    required this.sub,
    required this.accent,
    required this.onTap,
    required this.onRename,
    this.onDelete,
  });
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      child: Material(
        color: isCurrent ? cardActive : card,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 6, 10),
            child: Row(
              children: [
                if (isCurrent)
                  Container(
                      width: 3,
                      height: 30,
                      decoration: BoxDecoration(
                          color: accent,
                          borderRadius: BorderRadius.circular(2))),
                if (isCurrent)
                  const SizedBox(width: 8)
                else
                  const SizedBox(width: 11),
                Container(
                    width: 38,
                    height: 38,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12)),
                    child: Icon(Icons.forum_outlined,
                        color: accent, size: 20)),
                const SizedBox(width: 10),
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(session.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 14.5,
                                fontWeight: isCurrent
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                color: fg)),
                      ),
                      if (isCurrent) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text('当前',
                              style: TextStyle(
                                  fontSize: 10,
                                  color: accent,
                                  fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  icon: Icon(Icons.more_horiz, color: sub, size: 20),
                  padding: EdgeInsets.zero,
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'rename', child: Text('重命名')),
                    if (onDelete != null)
                      const PopupMenuItem(
                          value: 'delete',
                          child: Text('删除',
                              style: TextStyle(color: Colors.redAccent))),
                  ],
                  onSelected: (v) {
                    if (v == 'rename') onRename();
                    if (v == 'delete') onDelete?.call();
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ErrorHint extends StatelessWidget {
  final Color sub;
  final String message;
  const _ErrorHint({required this.sub, required this.message});
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 36, color: sub.withValues(alpha: 0.7)),
              const SizedBox(height: 10),
              Text(message, style: TextStyle(color: sub, fontSize: 13)),
            ],
          ),
        ),
      );
}

class _EmptySessions extends StatelessWidget {
  final Color sub;
  const _EmptySessions({required this.sub});
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.forum_outlined,
                  size: 44, color: sub.withValues(alpha: 0.6)),
              const SizedBox(height: 12),
              Text('暂无会话', style: TextStyle(color: sub, fontSize: 14)),
              const SizedBox(height: 4),
              Text('点击右上角「新建会话」',
                  style: TextStyle(
                      color: sub.withValues(alpha: 0.7), fontSize: 12)),
            ],
          ),
        ),
      );
}

class _Empty extends StatelessWidget {
  final Color sub;
  const _Empty({required this.sub});
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.smart_toy_outlined,
                  size: 44, color: sub.withValues(alpha: 0.6)),
              const SizedBox(height: 12),
              Text('暂无账户', style: TextStyle(color: sub, fontSize: 14)),
              const SizedBox(height: 4),
              Text('点击右上角「添加」',
                  style: TextStyle(color: sub.withValues(alpha: 0.7), fontSize: 12)),
            ],
          ),
        ),
      );
}
