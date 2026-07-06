// lib/screens/chat/bubbles/tool_status.dart
import 'package:flutter/material.dart';
import '../../../design/tokens.dart';

class ToolStatus extends StatelessWidget {
  final String text;
  const ToolStatus({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.light; // tool blue is same in both modes
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 2),
      child: Container(
        decoration: BoxDecoration(
            color: colors.toolBg.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(AppRadius.sm)),
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Text(text,
            style: TextStyle(
                color: colors.toolText,
                fontSize: 12,
                fontFamily: 'monospace')),
      ),
    );
  }
}
