// lib/screens/chat/bubbles/image_bubble.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../models/message.dart';
import '../../../providers/chat_provider.dart';

/// 上传进度圆形指示器
class UploadBadge extends StatelessWidget {
  final double progress;
  const UploadBadge({super.key, required this.progress});

  @override
  Widget build(BuildContext context) {
    final pct = (progress.clamp(0.0, 1.0) * 100).round();
    return Column(mainAxisSize: MainAxisSize.min, children: [
      SizedBox(
          width: 30,
          height: 30,
          child: CircularProgressIndicator(
            value: progress > 0 ? progress : null,
            strokeWidth: 3,
            valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
            backgroundColor: Colors.white.withValues(alpha: 0.25),
          )),
      const SizedBox(height: 4),
      Text('$pct%',
          style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w600)),
    ]);
  }
}

class ImageBubble extends ConsumerStatefulWidget {
  final LocalMessage m;
  final double bw;
  final bool isMe;
  const ImageBubble(
      {required this.m, required this.bw, required this.isMe, super.key});
  @override
  ConsumerState<ImageBubble> createState() => _ImageBubbleState();
}

class _ImageBubbleState extends ConsumerState<ImageBubble> {
  String? _downloaded;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    final lp = (widget.m.localPath as String?) ?? '';
    if (lp.isNotEmpty) {
      _downloaded = lp;
    } else if (!widget.isMe) {
      _loading = true;
    }
  }

  @override
  void didUpdateWidget(covariant ImageBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_downloaded == null && !widget.isMe) {
      final lp = (widget.m.localPath as String?) ?? '';
      if (lp.isNotEmpty &&
          lp != (oldWidget.m.localPath as String?) &&
          _loading) {
        setState(() {
          _downloaded = lp;
          _loading = false;
        });
      }
    }
  }

  void _openFullScreen() {
    if (_downloaded == null) return;
    Navigator.of(context).push(PageRouteBuilder(
      opaque: false,
      barrierColor: Colors.black87,
      barrierDismissible: true,
      pageBuilder: (_, __, ___) => _FullScreenImage(path: _downloaded!),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final w = (widget.bw * 0.6).clamp(120.0, 200.0);
    final uploading =
        (widget.m.status as MessageStatus?) == MessageStatus.uploading;
    final prog = (widget.m.uploadProgress as double?) ?? 0;
    if (_downloaded != null) {
      return GestureDetector(
        onTap: uploading ? null : _openFullScreen,
        child: Stack(children: [
          ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.file(File(_downloaded!),
                  width: w, fit: BoxFit.cover)),
          if (uploading)
            Positioned.fill(
                child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                        color: Colors.black.withValues(alpha: 0.45),
                        child:
                            Center(child: UploadBadge(progress: prog))))),
        ]),
      );
    }
    final errored =
        (widget.m.status as MessageStatus?) == MessageStatus.error;
    final placeholderColor =
        widget.isMe ? Colors.white54 : const Color(0xFF5B4BD6);
    return SizedBox(
      width: w,
      height: w * 0.6,
      child: errored
          ? GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => ref.read(chatProvider.notifier).retryMediaSend(
                  widget.m.createdAt,
                  'image',
                  widget.m.localPath,
                  widget.m.content),
              child: Center(
                  child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                    const Icon(Icons.refresh_rounded,
                        color: Colors.redAccent, size: 30),
                    const SizedBox(height: 6),
                    Text('发送失败,点击重试',
                        style: TextStyle(
                            color: Colors.redAccent.shade100,
                            fontSize: 12)),
                  ])))
          : (uploading
              ? Center(child: UploadBadge(progress: prog))
              : (_loading
                  ? Center(
                      child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                  placeholderColor))))
                  : Icon(Icons.image,
                      size: 48, color: placeholderColor))),
    );
  }
}

class _FullScreenImage extends StatelessWidget {
  final String path;
  const _FullScreenImage({required this.path});
  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.transparent,
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
