// lib/screens/chat/bubbles/thinking_block.dart
import 'package:flutter/material.dart';
import '../../../design/tokens.dart';

class ThinkingBlock extends StatefulWidget {
  final String text;
  final bool isDark;

  const ThinkingBlock({super.key, required this.text, required this.isDark});

  @override
  State<ThinkingBlock> createState() => _ThinkingBlockState();
}

class _ThinkingBlockState extends State<ThinkingBlock> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final colors = widget.isDark ? AppColors.dark : AppColors.light;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 2),
      child: Container(
        decoration: BoxDecoration(
            color: colors.thinkingText.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(AppRadius.sm)),
        child: Column(children: [
          InkWell(
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: Row(children: [
                Icon(Icons.psychology_outlined,
                    size: 14, color: colors.thinkingText),
                const SizedBox(width: 6),
                Expanded(
                    child: Text('思考过程',
                        style: TextStyle(
                            color: colors.thinkingText,
                            fontSize: 12,
                            fontWeight: FontWeight.w500))),
                AnimatedRotation(
                    turns: _open ? 0.5 : 0,
                    duration: const Duration(milliseconds: 150),
                    child: Icon(Icons.expand_more,
                        color: colors.thinkingText, size: 16)),
              ]),
            ),
          ),
          if (_open)
            Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(
                    AppSpacing.sm, 0, AppSpacing.sm, AppSpacing.sm),
                child: Text(widget.text,
                    style: TextStyle(
                        color: colors.thinkingText,
                        fontSize: 11,
                        height: 1.3,
                        fontFamily: 'monospace'))),
        ]),
      ),
    );
  }
}
