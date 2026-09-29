// lib/screens/settings_screen.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import '../design/tokens.dart';
import '../main.dart';
import '../providers/chat_provider.dart';
import '../providers/config_provider.dart';
import '../services/config_service.dart';
import '../services/cache_service.dart';
import '../services/update_service.dart';
import '../providers/platform_providers.dart';
import '../services/device_oem_service.dart';
import '../util/oem_whitelist.dart';
import '../widgets/oem_whitelist_dialog.dart';
import 'download_manage_screen.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});
  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late ConfigService _config;
  String _cacheSize = '计算中...';
  String _currentVersion = '';
  OemWhitelistGuide? _oemGuide;

  @override
  void initState() {
    super.initState();
    _config = ref.read(configServiceProvider);
    _calcCacheSize();
    UpdateService().currentVersion().then((v) {
      if (mounted) setState(() => _currentVersion = v);
    });
    _loadOemGuide();
  }

  Future<void> _loadOemGuide() async {
    final info = await const DeviceOemService().getInfo();
    if (!mounted) return;
    final guide = whitelistGuideFor(info);
    if (guide.needsGuide) setState(() => _oemGuide = guide);
  }

  void _showOemGuide() {
    final guide = _oemGuide;
    if (guide == null || !guide.needsGuide) return;
    showDialog<void>(
        context: context, builder: (_) => OemWhitelistDialog(guide: guide));
  }

  Future<void> _calcCacheSize() async {
    final dir = await getApplicationDocumentsDirectory();
    final cacheDir = Directory('${dir.path}/attachments');
    int total = 0;
    if (await cacheDir.exists()) {
      await for (final e in cacheDir.list()) {
        if (e is File) total += await e.length();
      }
    }
    if (mounted) {
      setState(() {
        _cacheSize = total > 1024 * 1024
            ? '${(total / 1024 / 1024).toStringAsFixed(1)} MB'
            : '${(total / 1024).toStringAsFixed(0)} KB';
      });
    }
  }

  Future<void> _clearCache() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清理缓存'),
        content: Text('附件缓存 $_cacheSize。清理会同时删除本地消息记录，'
            '服务器上保留的历史会在重连后重新同步。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('清理')),
        ],
      ),
    );
    if (confirmed == true) {
      final dir = await getApplicationDocumentsDirectory();
      final cacheDir = Directory('${dir.path}/attachments');
      if (await cacheDir.exists()) await cacheDir.delete(recursive: true);
      final cacheService = CacheService();
      await cacheService.clearAll();
      // 库已清空，但聊天页内存里的消息列表仍是旧的（分页 offset 随之错位、
      // 旧行的 localPath 指向已删文件）。重连一次：从空库重载并按服务端历史补齐。
      ref.read(chatProvider.notifier).connect();
      if (mounted) {
        setState(() => _cacheSize = '0 KB');
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('缓存已清理')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
            16, 8, 16, 32 + MediaQuery.paddingOf(context).bottom),
        children: [
          _Section(title: '外观', children: [
            Consumer(builder: (context, ref, _) {
              final currentMode = ref.watch(themeModeProvider);
              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      _IconTile(icon: Icons.palette_outlined, color: c.primary),
                      const SizedBox(width: 14),
                      Text('主题模式',
                          style: TextStyle(
                              fontSize: 15.5,
                              fontWeight: FontWeight.w500,
                              color: c.textPrimary)),
                    ]),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: SegmentedButton<ThemeMode>(
                        showSelectedIcon: false,
                        segments: const [
                          ButtonSegment(
                              value: ThemeMode.system,
                              label: Text('跟随系统')),
                          ButtonSegment(
                              value: ThemeMode.light,
                              label: Text('白天')),
                          ButtonSegment(
                              value: ThemeMode.dark,
                              label: Text('夜间')),
                        ],
                        selected: {currentMode},
                        onSelectionChanged: (v) async {
                          final mode = v.first;
                          await _config.setThemeMode(mode);
                          ref.read(themeModeProvider.notifier).state = mode;
                        },
                      ),
                    ),
                  ],
                ),
              );
            }),
          ]),
          if (_oemGuide != null && _oemGuide!.needsGuide)
            _Section(title: '后台运行', children: [
              _Tile(
                icon: Icons.bolt_rounded,
                color: c.warning,
                title: '后台运行设置',
                subtitle: _oemGuide!.reason,
                onTap: _showOemGuide,
              ),
            ]),
          _Section(title: '存储', children: [
            _Tile(
              icon: Icons.download_for_offline_outlined,
              color: const Color(0xFF16A37F),
              title: '下载管理',
              subtitle: '管理 AstrBot 发送的图片、文件、音频',
              onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const DownloadManageScreen())),
            ),
            _Tile(
              icon: Icons.cleaning_services_outlined,
              color: const Color(0xFFE58A12),
              title: '清理缓存',
              subtitle: '附件缓存与本地消息记录',
              trailingText: _cacheSize,
              onTap: _clearCache,
            ),
          ]),
          _Section(title: '关于', children: [
            _Tile(
              icon: Icons.info_outline_rounded,
              color: c.primary,
              title: 'Bot助手',
              subtitle: _currentVersion.isEmpty
                  ? '检查更新'
                  : '版本 v$_currentVersion · 点击检查更新',
              onTap: () => showDialog<void>(
                  context: context, builder: (_) => const _UpdateDialog()),
            ),
          ]),
        ],
      ),
    );
  }
}

/// 分组卡片：小标题 + 圆角容器，内部条目间以细线分隔。
class _Section extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _Section({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final items = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) {
        items.add(Divider(height: 1, indent: 62, color: c.divider));
      }
      items.add(children[i]);
    }
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 6, bottom: 8),
            child: Text(title,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: c.textSecondary)),
          ),
          Material(
            color: c.surface,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.lg),
                side: BorderSide(color: c.border, width: 0.5)),
            clipBehavior: Clip.antiAlias,
            child: Column(children: items),
          ),
        ],
      ),
    );
  }
}

class _IconTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  const _IconTile({required this.icon, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.13),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, size: 18, color: color),
      );
}

class _Tile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String? subtitle;
  final String? trailingText;
  final VoidCallback onTap;
  const _Tile({
    required this.icon,
    required this.color,
    required this.title,
    this.subtitle,
    this.trailingText,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 13, 10, 13),
        child: Row(children: [
          _IconTile(icon: icon, color: color),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title,
                    style: TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w500,
                        color: c.textPrimary)),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(subtitle!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12.5, height: 1.35, color: c.textSecondary)),
                ],
              ],
            ),
          ),
          if (trailingText != null)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Text(trailingText!,
                  style: TextStyle(fontSize: 13, color: c.textTertiary)),
            ),
          Icon(Icons.chevron_right_rounded, size: 22, color: c.textTertiary),
        ]),
      ),
    );
  }
}

/// 检查更新对话框（沿用既有实现）。
class _UpdateDialog extends ConsumerStatefulWidget {
  const _UpdateDialog();
  @override
  ConsumerState<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends ConsumerState<_UpdateDialog> {
  final UpdateService _svc = UpdateService();
  _S _s = _S.checking;
  UpdateCheck? _check;
  double _progress = 0;

  @override
  void initState() {
    super.initState();
    _doCheck();
  }

  Future<void> _doCheck() async {
    setState(() => _s = _S.checking);
    final c = await _svc.check();
    if (!mounted) return;
    _check = c;
    setState(() {
      if (c.error != null) {
        _s = _S.error;
      } else if (c.hasUpdate) {
        _s = _S.available;
      } else {
        _s = _S.latest;
      }
    });
  }

  Future<void> _downloadAndInstall() async {
    final info = _check?.latest;
    if (info == null) return;
    final applier = ref.read(updateApplierProvider);
    setState(() {
      _s = _S.downloading;
      _progress = 0;
    });
    try {
      await applier.apply(info, onProgress: (p) {
        if (mounted) setState(() => _progress = p);
      });
      if (!mounted) return;
      setState(() => _s = _S.installing);
    } catch (e) {
      if (mounted) {
        _check = UpdateCheck(
            currentVersion: _check?.currentVersion ?? '',
            error: '更新失败: $e');
        setState(() => _s = _S.error);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = _check?.latest;
    final title = switch (_s) {
      _S.checking => '检查更新',
      _S.available => '发现新版本 ${info?.tag ?? ''}',
      _S.latest => '已是最新版本',
      _S.error => '检查更新',
      _S.downloading => '正在下载',
      _S.installing => '正在安装',
    };
    final actions = <Widget>[
      if (_s == _S.error)
        TextButton(onPressed: _doCheck, child: const Text('重试')),
      if (_s == _S.available) ...[
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('以后再说')),
        FilledButton(
            onPressed: _downloadAndInstall, child: Text(ref.watch(updateApplierProvider).actionLabel)),
      ],
      if (_s == _S.latest || _s == _S.error)
        TextButton(
            onPressed: () => Navigator.pop(context), child: const Text('关闭')),
    ];
    return AlertDialog(
      title: Text(title),
      content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320), child: _content(info)),
      actions: actions,
    );
  }

  Widget _content(UpdateInfo? info) {
    switch (_s) {
      case _S.checking:
        return const Row(children: [
          SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2)),
          SizedBox(width: 16),
          Text('正在检查最新版本...'),
        ]);
      case _S.available:
        final notes = (info?.notes.trim().isNotEmpty == true)
            ? info!.notes.trim()
            : '修复与改进。';
        return SingleChildScrollView(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
              if (info!.sizeLabel.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text('大小:${info.sizeLabel}  当前:v${_check!.currentVersion}',
                      style: TextStyle(
                          fontSize: 12, color: AppColors.of(context).textTertiary)),
                ),
              Text(notes, style: const TextStyle(fontSize: 13, height: 1.4)),
            ]));
      case _S.latest:
        return Text('当前已是最新版本 v${_check?.currentVersion ?? ""}。');
      case _S.error:
        return Text(_check?.error ?? '检查失败,请稍后重试。');
      case _S.downloading:
        final pct = (_progress * 100).round();
        return Column(mainAxisSize: MainAxisSize.min, children: [
          LinearProgressIndicator(value: _progress > 0 ? _progress : null),
          const SizedBox(height: 10),
          Text('$pct%',
              style: TextStyle(
                  fontSize: 12, color: AppColors.of(context).textTertiary)),
        ]);
      case _S.installing:
        return const Column(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2)),
          SizedBox(height: 12),
          Text('下载完成,请在系统弹出的安装界面确认安装。',
              style: TextStyle(fontSize: 13, height: 1.4)),
        ]);
    }
  }
}

enum _S { checking, available, latest, error, downloading, installing }
