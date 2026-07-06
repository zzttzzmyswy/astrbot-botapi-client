// lib/screens/chat/bubbles/voice_bubble.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../models/message.dart';
import '../../../providers/chat_provider.dart';
import '../../../services/audio_playback_service.dart';

class VoiceBubble extends ConsumerStatefulWidget {
  final LocalMessage m;
  final Color fg;
  final bool isMe;
  const VoiceBubble(
      {required this.m, required this.fg, required this.isMe, super.key});
  @override
  ConsumerState<VoiceBubble> createState() => _VoiceBubbleState();
}

class _VoiceBubbleState extends ConsumerState<VoiceBubble> {
  String get _key => messageKey(widget.m);

  @override
  Widget build(BuildContext context) {
    final fg = widget.fg;
    final accent = const Color(0xFF5B4BD6);
    final onBubble = widget.isMe ? Colors.white : accent;
    final m = widget.m;
    final pb = ref.watch(audioPlaybackProvider);
    final player = ref.read(audioPlaybackProvider.notifier);

    if (m.status == MessageStatus.uploading) {
      final prog = m.uploadProgress ?? 0;
      return Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
              color: onBubble.withValues(
                  alpha: widget.isMe ? 0.25 : 0.12),
              borderRadius: BorderRadius.circular(8)),
          child: SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                value: prog > 0 ? prog : null,
                strokeWidth: 2,
                valueColor:
                    AlwaysStoppedAnimation<Color>(onBubble),
              )),
        ),
        const SizedBox(width: 10),
        Text('语音上传中 ${(prog * 100).round()}%',
            style: TextStyle(
                color: fg,
                fontSize: 13,
                fontWeight: FontWeight.w500)),
      ]);
    }

    if (m.status == MessageStatus.error) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => ref.read(chatProvider.notifier).retryMediaSend(
            m.createdAt, m.msgType, m.localPath, m.content),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
                color: Colors.redAccent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8)),
            child: const Icon(Icons.refresh_rounded,
                color: Colors.redAccent, size: 18),
          ),
          const SizedBox(width: 10),
          Text('发送失败,点击重试',
              style: TextStyle(
                  color: Colors.redAccent,
                  fontSize: 13,
                  fontWeight: FontWeight.w500)),
        ]),
      );
    }

    final loading = pb.isLoading(_key);
    final playing = pb.isPlaying(_key);
    final active = pb.currentKey == _key;
    final max = active
        ? pb.duration.inMilliseconds.toDouble().clamp(1.0, double.infinity)
        : 1.0;
    final val = active
        ? pb.position.inMilliseconds.toDouble().clamp(0.0, max)
        : 0.0;

    String timeText(Duration d) {
      final s = d.inSeconds.abs();
      return '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';
    }

    return Row(mainAxisSize: MainAxisSize.min, children: [
      if (loading)
        const SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2))
      else
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => player.toggle(m),
          child: Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: active
                  ? onBubble
                  : onBubble.withValues(
                      alpha: widget.isMe ? 0.25 : 0.14),
            ),
            child: Icon(
                playing
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded,
                color: active
                    ? (widget.isMe ? accent : Colors.white)
                    : onBubble,
                size: 18),
          ),
        ),
      const SizedBox(width: 8),
      SizedBox(
        width: 76,
        child: SliderTheme(
          data: SliderThemeData(
            trackHeight: 3,
            thumbShape:
                const RoundSliderThumbShape(enabledThumbRadius: 5),
            overlayShape:
                const RoundSliderOverlayShape(overlayRadius: 12),
            activeTrackColor: onBubble,
            inactiveTrackColor: fg.withValues(alpha: 0.3),
            thumbColor: onBubble,
          ),
          child: Slider(
            value: val,
            min: 0,
            max: max,
            onChanged: active
                ? (v) => player.seek(Duration(milliseconds: v.round()))
                : null,
            onChangeEnd: active
                ? (v) => player.seek(Duration(milliseconds: v.round()))
                : null,
          ),
        ),
      ),
      const SizedBox(width: 4),
      SizedBox(
          width: 38,
          child: Text(
              timeText(
                  active ? pb.position : Duration.zero),
              style: TextStyle(
                  color: fg.withValues(alpha: 0.8),
                  fontSize: 11))),
      if (active) ...[
        const SizedBox(width: 2),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => player.stop(),
          child: Icon(Icons.stop_rounded,
              color: fg.withValues(alpha: 0.8), size: 20),
        ),
      ],
    ]);
  }
}
