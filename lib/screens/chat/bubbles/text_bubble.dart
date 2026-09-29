// lib/screens/chat/bubbles/text_bubble.dart
//
// 气泡正文的 Markdown 渲染。实现已收敛到 lib/screens/chat/markdown/：
// 终态气泡与流式气泡共用同一份样式、扩展集与公式 builder。
import 'package:flutter/material.dart';

import '../../../design/tokens.dart';
import '../markdown/markdown_view.dart';

export '../markdown/markdown_view.dart'
    show mdStyleSheet, launchMarkdownUrl, buildMarkdown;

/// 气泡正文：纯文本走 SelectableText，含格式时走 Markdown（含公式）。
Widget mdText(String text, Color fg, bool isDark, {bool mine = false}) =>
    buildMarkdown(text, fg, isDark, mine: mine);

/// 文本气泡发送失败态:点击重发。通过 callback 解耦。
class TextBodyError extends StatelessWidget {
  final String content;
  final VoidCallback onRetry;
  const TextBodyError(
      {super.key, required this.content, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onRetry,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(content,
              style: TextStyle(
                  color: c.textPrimary, fontSize: 15.5, height: 1.55)),
          const SizedBox(height: 6),
          Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.refresh_rounded, color: c.error, size: 15),
            const SizedBox(width: 4),
            Text('发送失败，点击重试',
                style: TextStyle(
                    color: c.error,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600)),
          ]),
        ],
      ),
    );
  }
}
