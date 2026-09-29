// lib/screens/chat/bubbles/message_bubble.dart
//
// 单条消息的外壳：对齐、气泡底（我方主色渐变 / 对方卡片）、分组圆角、
// 组尾时间与发送状态。正文按类型分派给 text / image / voice / file 子组件。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../design/tokens.dart';
import '../../../models/message.dart';
import '../../../providers/chat_provider.dart';
import 'file_bubble.dart';
import 'image_bubble.dart';
import 'text_bubble.dart';
import 'voice_bubble.dart';

class MessageBubble extends ConsumerWidget {
  final LocalMessage m;

  /// 可用最大宽度（屏宽减去左右边距）。
  final double maxWidth;
  final bool isDark;

  /// 与上一条 / 下一条同组（决定圆角、间距与是否显示时间）。
  final bool groupedWithPrev;
  final bool groupedWithNext;

  const MessageBubble({
    super.key,
    required this.m,
    required this.maxWidth,
    required this.isDark,
    this.groupedWithPrev = false,
    this.groupedWithNext = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = AppColors.forDark(isDark);
    final isMe = m.isFromMe;
    final type = m.msgType;
    final text = m.content ?? '';
    final fg = isMe ? c.bubbleMineText : c.bubbleOtherText;
    // 我方气泡收窄，给对方（多为长 Markdown 回复）留足宽度。
    final bw = isMe ? maxWidth * 0.84 : maxWidth;

    bool bare = false; // 图片不套气泡底
    Widget body;
    switch (type) {
      case 'image':
        bare = true;
        body = ImageBubble(m: m, bw: bw, isMe: isMe);
        break;
      case 'voice':
      case 'record':
      case 'audio':
        body = VoiceBubble(m: m, fg: fg, isMe: isMe);
        break;
      case 'file':
        body = FileBubble(m: m, fg: fg, isMe: isMe);
        break;
      default:
        final errored = m.status == MessageStatus.error;
        body = errored
            ? TextBodyError(
                content: text,
                onRetry: () => ref
                    .read(chatProvider.notifier)
                    .retryTextSend(m.createdAt))
            : mdText(text, fg, isDark, mine: isMe);
    }

    const big = Radius.circular(AppRadius.bubble);
    const small = Radius.circular(AppRadius.bubbleTail);
    final radius = isMe
        ? BorderRadius.only(
            topLeft: big,
            bottomLeft: big,
            topRight: groupedWithPrev ? small : big,
            bottomRight: small)
        : BorderRadius.only(
            topRight: big,
            bottomRight: big,
            topLeft: groupedWithPrev ? small : big,
            bottomLeft: small);

    // 仅文本失败态换成错误底色；媒体失败态由各自组件在气泡内提示。
    final errored = m.status == MessageStatus.error &&
        !const {'image', 'voice', 'record', 'audio', 'file'}.contains(type);
    final Widget bubble = bare
        ? body
        : DecoratedBox(
            decoration: BoxDecoration(
              gradient: isMe && !errored
                  ? LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: c.bubbleMineGradient)
                  : null,
              color: isMe
                  ? (errored ? c.error.withValues(alpha: 0.10) : null)
                  : c.bubbleOther,
              borderRadius: radius,
              border: isMe
                  ? (errored
                      ? Border.all(color: c.error.withValues(alpha: 0.35))
                      : null)
                  : Border.all(color: c.bubbleOtherBorder, width: 0.8),
              boxShadow: isMe
                  ? (errored ? null : AppShadows.mine(c.bubbleMineGradient[1]))
                  : AppShadows.bubble(isDark),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: body,
            ),
          );

    final showMeta = !groupedWithNext && m.createdAt > 0;
    return Padding(
      padding: EdgeInsets.only(
          left: AppSpacing.md,
          right: AppSpacing.md,
          bottom: groupedWithNext ? 3 : 12),
      child: Column(
        crossAxisAlignment:
            isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: bw),
            child: bubble,
          ),
          if (showMeta)
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 6, right: 6),
              child: _Meta(m: m, c: c),
            ),
        ],
      ),
    );
  }
}

/// 组尾元信息：时间 + 我方消息的发送状态。
class _Meta extends StatelessWidget {
  final LocalMessage m;
  final AppColors c;
  const _Meta({required this.m, required this.c});

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(fontSize: 11, height: 1.2, color: c.textTertiary);
    Widget? status;
    if (m.isFromMe) {
      switch (m.status) {
        case MessageStatus.pending:
          // 已落库到服务端（有 server_id）的必然已送达，不显示「发送中」。
          status = m.serverId != null
              ? Icon(Icons.done_rounded, size: 13, color: c.textTertiary)
              : Icon(Icons.schedule_rounded, size: 12, color: c.textTertiary);
          break;
        case MessageStatus.uploading:
          status = null;
          break;
        case MessageStatus.sent:
          status = Icon(Icons.done_rounded, size: 13, color: c.textTertiary);
          break;
        case MessageStatus.error:
          status = Text('发送失败', style: style.copyWith(color: c.error));
          break;
      }
    }
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Text(hhmm(m.createdAt), style: style),
      if (status != null) ...[const SizedBox(width: 4), status],
    ]);
  }
}

String hhmm(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toLocal();
  return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}
