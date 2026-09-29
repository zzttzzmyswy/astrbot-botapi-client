import 'package:flutter/material.dart';
import '../../../design/tokens.dart';

/// 工具调用提示：左对齐的等宽小卡片，与对方气泡同列。
class ToolStatus extends StatelessWidget {
  final String text;
  const ToolStatus({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    // 服务端文案常带「🔨」前缀，图标已表达语义，去掉避免重复。
    final label = text.replaceFirst(RegExp(r'^\s*🔨\s*'), '');
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.xl3, 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.fromLTRB(8, 6, 12, 6),
          decoration: BoxDecoration(
            color: c.tool.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: c.tool.withValues(alpha: 0.18), width: 0.8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 20,
                height: 20,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: c.tool.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(Icons.build_rounded, size: 12, color: c.tool),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.only(top: 1.5),
                  child: Text(label,
                      style: TextStyle(
                          color: c.tool,
                          fontSize: 12.5,
                          height: 1.4,
                          fontFamily: 'monospace')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
