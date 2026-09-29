import 'package:flutter/material.dart';
import '../../../design/tokens.dart';
import '../markdown/markdown_view.dart';

/// 流式回复气泡：与对方终态气泡同一外观，底部带一个呼吸光标示意仍在输出。
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
    final c = AppColors.forDark(isDark);
    return Padding(
      padding: const EdgeInsets.only(
          left: AppSpacing.md, right: AppSpacing.md, bottom: 12),
      child: Align(
        alignment: Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: bw),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: c.bubbleOther,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(AppRadius.bubble),
                topRight: Radius.circular(AppRadius.bubble),
                bottomLeft: Radius.circular(AppRadius.bubbleTail),
                bottomRight: Radius.circular(AppRadius.bubble),
              ),
              border: Border.all(color: c.bubbleOtherBorder, width: 0.8),
              boxShadow: AppShadows.bubble(isDark),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (text.isNotEmpty)
                    buildMarkdown(text, c.bubbleOtherText, isDark),
                  Padding(
                    padding: EdgeInsets.only(top: text.isEmpty ? 0 : 6),
                    child: _PulseDot(color: c.primary),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PulseDot extends StatefulWidget {
  final Color color;
  const _PulseDot({required this.color});
  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 900))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: Tween(begin: 0.25, end: 1.0).animate(_c),
        child: Container(
          width: 8,
          height: 8,
          decoration:
              BoxDecoration(color: widget.color, shape: BoxShape.circle),
        ),
      );
}
