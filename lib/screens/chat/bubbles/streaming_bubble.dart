// lib/screens/chat/bubbles/streaming_bubble.dart
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart' as md;
import '../../../design/tokens.dart';
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
    final colors = isDark ? AppColors.dark : AppColors.light;
    return Padding(
      padding: EdgeInsets.only(
          left: AppSpacing.md,
          right: AppSpacing.md,
          bottom: AppSpacing.xs - 1),
      child: Align(
        alignment: Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: bw),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colors.streamingBg,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(AppRadius.lg),
                topRight: Radius.circular(AppRadius.lg),
                bottomLeft: Radius.circular(2),
                bottomRight: Radius.circular(AppRadius.lg),
              ),
              boxShadow: AppShadows.bubble(isDark),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md, vertical: AppSpacing.sm),
              child: text.isEmpty
                  ? const SizedBox.shrink()
                  : md.MarkdownBody(
                      data: text,
                      selectable: false,
                      styleSheet:
                          mdStyleSheet(colors.streamingText, isDark),
                      onTapLink: launchMarkdownUrl,
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
