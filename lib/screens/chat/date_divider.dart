import 'package:flutter/material.dart';
import '../../design/tokens.dart';

/// 日期分隔：居中小字 + 两侧渐隐细线。
class DateDivider extends StatelessWidget {
  final String label;
  final bool isDark;

  const DateDivider({super.key, required this.label, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.forDark(isDark);
    Widget line(bool leftSide) => Expanded(
          child: Container(
            height: 0.8,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: leftSide
                    ? [c.border.withValues(alpha: 0), c.border]
                    : [c.border, c.border.withValues(alpha: 0)],
              ),
            ),
          ),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(40, 8, 40, 16),
      child: Row(children: [
        line(true),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(label,
              style: TextStyle(
                  fontSize: 12,
                  color: c.textTertiary,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.4)),
        ),
        line(false),
      ]),
    );
  }
}
