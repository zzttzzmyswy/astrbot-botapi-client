// lib/screens/chat/bubbles/streaming_bubble.dart
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart' as md;
import 'text_bubble.dart';

class StreamingBubble extends StatelessWidget {
  final String text;
  final double bw;
  final bool isDark;

  const StreamingBubble({
    super.key,
    required this.text,
    required this.bw,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final bg = isDark ? const Color(0xFF212121) : const Color(0xFFE8E8EC);
    final fg = isDark ? Colors.white : Colors.black;
    return Padding(
      padding: const EdgeInsets.only(left: 12, right: 12, bottom: 3),
      child: Align(
        alignment: Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: bw),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: bg,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
                bottomLeft: Radius.circular(2),
                bottomRight: Radius.circular(16),
              ),
            ),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: text.isEmpty
                  ? const SizedBox.shrink()
                  : md.MarkdownBody(
                      data: text,
                      selectable: false,
                      styleSheet: mdStyleSheet(fg, isDark),
                      onTapLink: launchMarkdownUrl,
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
