// lib/screens/download_manage_screen.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/message.dart';
import '../services/audio_playback_service.dart';
import '../services/cache_service.dart';
import '../services/media_registry.dart';
import '../util/mime.dart';

/// 下载管理页：统一管理 astrbot 发送的图片/文件/音频（本地已下载的缓存）。
/// 数据源 = 消息表中带 localPath 的媒体 + 附件目录中的孤立下载文件。
class DownloadManageScreen extends ConsumerStatefulWidget {
  const DownloadManageScreen({super.key});
  @override
  ConsumerState<DownloadManageScreen> createState() =>
      _DownloadManageScreenState();
}

class _DownloadManageScreenState extends ConsumerState<DownloadManageScreen> {
  final CacheService _cache = CacheService();
  List<DownloadEntry> _entries = [];
  bool _loading = true;
  int _tab = 0; // 0 全部 / 1 图片 / 2 音频 / 3 文件

  static const _tabs = ['全部', '图片', '音频', '文件'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final messages = await _cache.getMessages();
      final dir = await getApplicationDocumentsDirectory();
      final entries = await MediaRegistry.build(
        messages: messages,
        attachmentsDir: Directory('${dir.path}/attachments'),
      );
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  List<DownloadEntry> get _visible {
    if (_tab == 0) return _entries;
    final want = switch (_tab) {
      1 => DownloadCategory.image,
      2 => DownloadCategory.audio,
      _ => DownloadCategory.file,
    };
    return _entries.where((e) => e.category == want).toList();
  }

  int _countOf(DownloadCategory c) =>
      _entries.where((e) => e.category == c).length;

  String _fmtTime(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    final now = DateTime.now();
    final day = DateTime(d.year, d.month, d.day);
    if (now.difference(day).inDays <= 0) {
      final hh = d.hour.toString().padLeft(2, '0');
      final mm = d.minute.toString().padLeft(2, '0');
      return '今天 $hh:$mm';
    }
    return '${d.month}-${d.day.toString().padLeft(2, '0')}';
  }

  String _fmtSize(int bytes) {
    if (bytes >= 1024 * 1024) {
      return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
    }
    if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '$bytes B';
  }

  IconData _iconFor(DownloadCategory c) => switch (c) {
        DownloadCategory.image => Icons.image_rounded,
        DownloadCategory.audio => Icons.mic_rounded,
        DownloadCategory.file => Icons.insert_drive_file_rounded,
      };

  Color _tintFor(DownloadCategory c) => switch (c) {
        DownloadCategory.image => const Color(0xFF1676F2),
        DownloadCategory.audio => const Color(0xFF5B4BD6),
        DownloadCategory.file => const Color(0xFF34A853),
      };

  Future<void> _open(DownloadEntry e) async {
    switch (e.category) {
      case DownloadCategory.image:
        Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => _ImagePreview(path: e.path, name: e.name)));
      case DownloadCategory.audio:
        _play(e);
      case DownloadCategory.file:
        await _share(e);
    }
  }

  void _play(DownloadEntry e) {
    final msg = LocalMessage(
      msgType: 'voice',
      content: e.name,
      localPath: e.path,
      isFromMe: false,
      status: MessageStatus.sent,
      createdAt: e.createdAt,
    );
    ref.read(audioPlaybackProvider.notifier).toggle(msg);
  }

  Future<void> _share(DownloadEntry e) async {
    try {
      await Share.shareXFiles([
        XFile(e.path, name: e.name, mimeType: mimeForExtension(e.path))
      ]);
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('分享失败: $err'),
          backgroundColor: Colors.redAccent));
    }
  }

  Future<void> _delete(DownloadEntry e) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除文件'),
        content: Text('删除本地文件「${e.name}」？\n（聊天里的消息不会删除，可再次点击下载）'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('删除')),
        ],
      ),
    );
    if (confirmed != true) return;
    final f = File(e.path);
    if (await f.exists()) await f.delete();
    await _cache.clearLocalPath(e.path);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final bg = dark ? const Color(0xFF121215) : const Color(0xFFEDEDED);
    final card = dark ? const Color(0xFF1C1C1E) : Colors.white;
    final fg = dark ? Colors.white : const Color(0xFF1A1A24);
    final sub = dark ? const Color(0xFFAEAEB2) : const Color(0xFF8A8A93);

    final totalSize = _entries.fold<int>(0, (acc, e) {
      final f = File(e.path);
      final len = f.existsSync() ? f.lengthSync() : 0;
      return acc + len;
    });

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: dark ? const Color(0xFF1C1C1E) : Colors.white,
        elevation: 0,
        foregroundColor: fg,
        title: const Text('下载管理', style: TextStyle(fontSize: 17)),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: Text(
                '${_entries.length} 项 · ${_fmtSize(totalSize)}',
                style: TextStyle(fontSize: 12, color: sub),
              ),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : RefreshIndicator(
              onRefresh: _load,
              child: Column(children: [
                _TabBar(
                    tabs: _tabs,
                    counts: [
                      _entries.length,
                      _countOf(DownloadCategory.image),
                      _countOf(DownloadCategory.audio),
                      _countOf(DownloadCategory.file),
                    ],
                    selected: _tab,
                    onSelect: (i) => setState(() => _tab = i),
                    fg: fg,
                    sub: sub,
                    card: card),
                Expanded(
                    child: _visible.isEmpty
                        ? _EmptyState(sub: sub)
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(12, 6, 12, 24),
                            itemCount: _visible.length,
                            itemBuilder: (_, i) => _entryTile(
                                _visible[i], fg, sub, card, dark),
                          )),
              ]),
            ),
    );
  }

  Widget _entryTile(DownloadEntry e, Color fg, Color sub, Color card,
          bool dark) =>
      Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: card,
          borderRadius: BorderRadius.circular(14),
        ),
        child: ListTile(
          leading: e.category == DownloadCategory.image &&
                  File(e.path).existsSync()
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.file(File(e.path),
                      width: 44, height: 44, fit: BoxFit.cover),
                )
              : Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: _tintFor(e.category)
                        .withValues(alpha: dark ? 0.28 : 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(_iconFor(e.category),
                      color: _tintFor(e.category), size: 22),
                ),
          title: Text(e.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: fg, fontSize: 14, fontWeight: FontWeight.w500)),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              '${_fmtTime(e.createdAt)} · ${_fmtSize(File(e.path).lengthSync())}',
              style: TextStyle(color: sub, fontSize: 11.5),
            ),
          ),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            _ActionIcon(
                icon: e.category == DownloadCategory.audio
                    ? Icons.play_arrow_rounded
                    : Icons.open_in_new_rounded,
                onTap: () => _open(e)),
            _ActionIcon(icon: Icons.delete_outline_rounded, onTap: () => _delete(e)),
          ]),
        ),
      );
}

class _TabBar extends StatelessWidget {
  final List<String> tabs;
  final List<int> counts;
  final int selected;
  final ValueChanged<int> onSelect;
  final Color fg, sub, card;
  const _TabBar({
    required this.tabs,
    required this.counts,
    required this.selected,
    required this.onSelect,
    required this.fg,
    required this.sub,
    required this.card,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 6),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: card.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(children: [
        for (int i = 0; i < tabs.length; i++)
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onSelect(i),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: selected == i ? const Color(0xFF5B4BD6) : Colors.transparent,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Text(
                  '${tabs[i]} ${counts[i]}',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: selected == i ? Colors.white : sub,
                    fontSize: 12.5,
                    fontWeight: selected == i ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ),
            ),
          ),
      ]),
    );
  }
}

class _ActionIcon extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _ActionIcon({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final sub = dark ? const Color(0xFFAEAEB2) : const Color(0xFF8A8A93);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: sub.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 17, color: sub),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final Color sub;
  const _EmptyState({required this.sub});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.download_for_offline_rounded, size: 56, color: sub.withValues(alpha: 0.5)),
        const SizedBox(height: 12),
        Text('暂无下载内容', style: TextStyle(color: sub, fontSize: 14)),
        const SizedBox(height: 4),
        Text('astrbot 发送的图片、文件、音频会出现在这里',
            style: TextStyle(color: sub.withValues(alpha: 0.7), fontSize: 12)),
      ]),
    );
  }
}

/// 全屏图片预览（与聊天里的全屏预览保持同一交互）。
class _ImagePreview extends StatelessWidget {
  final String path;
  final String name;
  const _ImagePreview({required this.path, required this.name});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: Text(name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 15)),
      ),
      body: GestureDetector(
        onTap: () => Navigator.of(context).pop(),
        child: Center(
          child: InteractiveViewer(
            maxScale: 5.0,
            child: Image.file(File(path)),
          ),
        ),
      ),
    );
  }
}