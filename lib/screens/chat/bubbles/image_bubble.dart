// lib/screens/chat/bubbles/image_bubble.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../design/tokens.dart';
import '../../../models/message.dart';
import '../../../providers/chat_provider.dart';

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
    final lp = widget.m.localPath ?? '';
    if (lp.isNotEmpty) {
      _downloaded = lp;
    }
  }

  @override
  void didUpdateWidget(covariant ImageBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 对方图片由 ChatNotifier 收到事件后自动下载，完成时只更新 localPath；
    // 旧实现额外要求 _loading（仅「点击下载」路径为 true），自动下载完成后
    // 气泡仍停在占位图，需要用户再点一次。localPath 一到就切换。
    if (_downloaded == null && !widget.isMe) {
      final lp = widget.m.localPath ?? '';
      if (lp.isNotEmpty && lp != oldWidget.m.localPath) {
        setState(() {
          _downloaded = lp;
          _loading = false;
        });
      }
    }
  }

  Future<void> _tryDownload() async {
    if (_downloaded != null || _loading) return;
    setState(() => _loading = true);
    final url = widget.m.attachmentId ?? '';
    if (url.isEmpty) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final path =
        await ref.read(chatProvider.notifier).downloadMedia(url);
    if (path != null && mounted) {
      setState(() {
        _downloaded = path;
        _loading = false;
      });
    } else if (mounted) {
      setState(() => _loading = false);
    }
  }

  void _openFullScreen() {
    if (_downloaded == null) {
      _tryDownload();
      return;
    }
    Navigator.of(context).push(PageRouteBuilder(
      opaque: false,
      barrierColor: Colors.black87,
      barrierDismissible: true,
      pageBuilder: (_, __, ___) => _FullScreenImage(
          path: _downloaded!, heroTag: 'img_${widget.m.createdAt}_${_downloaded!}'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final w = (widget.bw * 0.72).clamp(140.0, 240.0);
    final uploading =
        widget.m.status == MessageStatus.uploading;
    final prog = widget.m.uploadProgress ?? 0;
    final radius = BorderRadius.circular(AppRadius.lg);
    if (_downloaded != null) {
      return GestureDetector(
        onTap: uploading ? null : _openFullScreen,
        child: Hero(
          tag: 'img_${widget.m.createdAt}_${_downloaded!}',
          child: Container(
            decoration: BoxDecoration(
              borderRadius: radius,
              border: Border.all(color: c.bubbleOtherBorder, width: 0.8),
            ),
            child: ClipRRect(
              borderRadius: radius,
              child: Stack(children: [
                ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: w * 1.4),
                  child: Image.file(File(_downloaded!),
                      width: w,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _placeholder(
                          c, w, Icon(Icons.broken_image_outlined,
                              size: 36, color: c.textTertiary))),
                ),
                if (uploading)
                  Positioned.fill(
                      child: Container(
                          color: Colors.black.withValues(alpha: 0.45),
                          child: Center(child: UploadBadge(progress: prog)))),
              ]),
            ),
          ),
        ),
      );
    }
    final errored =
        widget.m.status == MessageStatus.error;
    Widget inner;
    if (errored) {
      inner = GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => ref.read(chatProvider.notifier).retryMediaSend(
              widget.m.createdAt, 'image', widget.m.localPath, widget.m.content),
          child: Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.refresh_rounded, color: c.error, size: 28),
            const SizedBox(height: 6),
            Text('发送失败，点击重试',
                style: TextStyle(color: c.error, fontSize: 12.5)),
          ])));
    } else if (uploading) {
      inner = Center(
          child: DecoratedBox(
              decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(AppRadius.md)),
              child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: UploadBadge(progress: prog))));
    } else if (_loading) {
      inner = Center(
          child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(c.primary))));
    } else {
      inner = GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _tryDownload,
          child: Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.image_outlined, size: 36, color: c.textTertiary),
            const SizedBox(height: 6),
            Text('点击加载图片',
                style: TextStyle(color: c.textSecondary, fontSize: 12.5)),
          ])));
    }
    return _placeholder(c, w, inner);
  }

  Widget _placeholder(AppColors c, double w, Widget child) => Container(
        width: w,
        height: w * 0.66,
        decoration: BoxDecoration(
          color: c.surfaceMuted,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: c.bubbleOtherBorder, width: 0.8),
        ),
        child: child,
      );
}

class _FullScreenImage extends StatelessWidget {
  final String path;
  final String heroTag;
  const _FullScreenImage({required this.path, required this.heroTag});
  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.transparent,
        body: GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: Center(
            child: InteractiveViewer(
              maxScale: 5.0,
              child: Hero(tag: heroTag, child: Image.file(File(path))),
            ),
          ),
        ),
      );
}
