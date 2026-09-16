// lib/screens/chat/bubbles/text_bubble.dart
//
// 气泡正文的 Markdown 渲染。实现已收敛到 lib/screens/chat/markdown/：
// 终态气泡与流式气泡共用同一份样式、扩展集与公式 builder。
import 'package:flutter/material.dart';

import '../markdown/markdown_view.dart';

export '../markdown/markdown_view.dart'
    show mdStyleSheet, launchMarkdownUrl, buildMarkdown;

/// 气泡正文：纯文本走 SelectableText，含格式时走 Markdown（含公式）。
Widget mdText(String text, Color fg, bool isDark) =>
    buildMarkdown(text, fg, isDark);

/// 文本气泡发送失败态:点击重发。通过 callback 解耦。
class TextBodyError extends StatelessWidget {
  final String content;
  final VoidCallback onRetry;
  const TextBodyError(
      {super.key, required this.content, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onRetry,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.error_outline_rounded,
            color: Colors.redAccent, size: 16),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            content,
            style: const TextStyle(
                color: Colors.redAccent,
                fontSize: 15,
                height: 1.35,
                decoration: TextDecoration.lineThrough),
          ),
        ),
        const SizedBox(width: 6),
        const Icon(Icons.refresh_rounded,
            color: Colors.redAccent, size: 16),
      ]),
    );
  }
}
