// lib/screens/chat/bubbles/file_bubble.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../../design/tokens.dart';
import '../../../models/message.dart';
import '../../../providers/chat_provider.dart';
import '../../../util/mime.dart';

class FileBubble extends ConsumerStatefulWidget {
  final LocalMessage m;
  final Color fg;
  final bool isMe;
  const FileBubble(
      {required this.m, required this.fg, required this.isMe, super.key});
  @override
  ConsumerState<FileBubble> createState() => _FileBubbleState();
}

class _FileBubbleState extends ConsumerState<FileBubble> {
  bool _downloading = false;

  void _retry() {
    ref.read(chatProvider.notifier).retryMediaSend(
        widget.m.createdAt,
        widget.m.msgType,
        widget.m.localPath,
        widget.m.content);
  }

  Future<void> _open() async {
    final name = widget.m.content ?? 'file';
    setState(() => _downloading = true);
    try {
      File? src;
      final lp = widget.m.localPath ?? '';
      if (lp.isNotEmpty && File(lp).existsSync()) {
        src = File(lp);
      }
      if (src == null || !await src.exists()) {
        // 本地无缓存 → 按 URL 下载
        final url = widget.m.attachmentId ?? '';
        if (url.isNotEmpty) {
          final path =
              await ref.read(chatProvider.notifier).downloadMedia(url);
          if (path != null) {
            src = File(path);
          }
        }
        if (src == null || !await src.exists()) {
          throw Exception('文件下载失败');
        }
      }
      final safe = name.replaceAll(RegExp(r'[/\\]'), '_');
      final tmp = await getTemporaryDirectory();
      final dest = File('${tmp.path}/astrbot_$safe');
      await dest.writeAsBytes(await src.readAsBytes());
      Share.shareXFiles(
          [XFile(dest.path, name: name, mimeType: mimeForExtension(name))]);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('打开失败: $e'),
              backgroundColor: AppColors.of(context).error),
        );
      }
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fg = widget.fg;
    final name = widget.m.content ?? '文件';
    final uploading =
        widget.m.status == MessageStatus.uploading;
    final errored =
        widget.m.status == MessageStatus.error;
    final prog = widget.m.uploadProgress ?? 0;
    final c = AppColors.of(context);
    final accent = c.primary;
    final onBubble = widget.isMe ? Colors.white : accent;
    final ext = name.contains('.')
        ? name.split('.').last.toUpperCase()
        : '';

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: uploading ? null : (errored ? _retry : _open),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 240),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                          color: errored
                              ? c.error.withValues(alpha: 0.15)
                              : onBubble.withValues(
                                  alpha: widget.isMe ? 0.25 : 0.12),
                          borderRadius: BorderRadius.circular(12)),
                      child: uploading
                          ? SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  value: prog > 0 ? prog : null,
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                      onBubble)))
                          : (_downloading
                              ? SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                          onBubble.withValues(alpha: 0.8))))
                              : (errored || ext.isEmpty || ext.length > 4
                                  ? Icon(
                                      errored
                                          ? Icons.refresh_rounded
                                          : Icons.description_rounded,
                                      color: errored ? c.error : onBubble,
                                      size: 20)
                                  : Text(ext,
                                      style: TextStyle(
                                          color: onBubble,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 0.3)))),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                        child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                          Text(name,
                              style: TextStyle(
                                  color: fg,
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w600),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 2),
                          Text(
                              uploading
                                  ? '上传中 ${(prog * 100).round()}%'
                                  : (errored
                                      ? '发送失败，点击重试'
                                      : (_downloading
                                          ? '下载中…'
                                          : '点击打开 / 分享')),
                              style: TextStyle(
                                  color: errored
                                      ? c.error
                                      : fg.withValues(alpha: 0.6),
                                  fontSize: 12)),
                        ])),
                    if (!uploading)
                      Icon(Icons.chevron_right_rounded,
                          color: fg.withValues(alpha: 0.4), size: 18),
                  ]),
              if (uploading) ...[
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: prog > 0 ? prog : null,
                    minHeight: 3,
                    backgroundColor: fg.withValues(alpha: 0.2),
                    valueColor:
                        AlwaysStoppedAnimation<Color>(onBubble),
                  ),
                ),
              ],
            ]),
      ),
    );
  }
}
