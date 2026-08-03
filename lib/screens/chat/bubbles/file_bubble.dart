// lib/screens/chat/bubbles/file_bubble.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../../models/message.dart';
import '../../../providers/chat_provider.dart';

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
        (widget.m.createdAt as int),
        (widget.m.msgType as String),
        (widget.m.localPath as String?),
        (widget.m.content as String?));
  }

  Future<void> _open() async {
    final name = (widget.m.content as String?) ?? 'file';
    setState(() => _downloading = true);
    try {
      File? src;
      final lp = (widget.m.localPath as String?) ?? '';
      if (lp.isNotEmpty && File(lp).existsSync()) {
        src = File(lp);
      }
      if (src == null || !await src.exists()) {
        // 本地无缓存 → 按 URL 下载
        final url = (widget.m.attachmentId as String?) ?? '';
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
          [XFile(dest.path, name: name, mimeType: _mimeForName(name))]);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('打开失败: $e'),
              backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  static String _mimeForName(String name) {
    final ext =
        name.contains('.') ? name.split('.').last.toLowerCase() : '';
    switch (ext) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      case 'pdf':
        return 'application/pdf';
      case 'txt':
        return 'text/plain';
      case 'mp4':
        return 'video/mp4';
      case 'mp3':
        return 'audio/mpeg';
      case 'wav':
        return 'audio/wav';
      case 'doc':
        return 'application/msword';
      case 'docx':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      case 'xls':
        return 'application/vnd.ms-excel';
      case 'xlsx':
        return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      case 'zip':
        return 'application/zip';
      default:
        return 'application/octet-stream';
    }
  }

  @override
  Widget build(BuildContext context) {
    final fg = widget.fg;
    final name = (widget.m.content as String?) ?? '文件';
    final uploading =
        (widget.m.status as MessageStatus?) == MessageStatus.uploading;
    final errored =
        (widget.m.status as MessageStatus?) == MessageStatus.error;
    final prog = (widget.m.uploadProgress as double?) ?? 0;
    final accent = const Color(0xFF5B4BD6);
    final onBubble = widget.isMe ? Colors.white : accent;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: uploading ? null : (errored ? _retry : _open),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 220),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                          color: errored
                              ? Colors.redAccent.withValues(alpha: 0.15)
                              : onBubble.withValues(
                                  alpha: widget.isMe ? 0.25 : 0.12),
                          borderRadius: BorderRadius.circular(8)),
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
                              : Icon(
                                  errored
                                      ? Icons.refresh_rounded
                                      : Icons.description_rounded,
                                  color: errored
                                      ? Colors.redAccent
                                      : onBubble,
                                  size: 18)),
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
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500),
                              overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 1),
                          Text(
                              uploading
                                  ? '上传中 ${(prog * 100).round()}%'
                                  : (errored
                                      ? '发送失败,点击重试'
                                      : (_downloading
                                          ? '下载中…'
                                          : '点击打开')),
                              style: TextStyle(
                                  color: errored
                                      ? Colors.redAccent
                                      : fg.withValues(alpha: 0.55),
                                  fontSize: 11)),
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
                        AlwaysStoppedAnimation<Color>(accent),
                  ),
                ),
              ],
            ]),
      ),
    );
  }
}
