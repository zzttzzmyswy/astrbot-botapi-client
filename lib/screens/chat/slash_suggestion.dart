// lib/screens/chat/slash_suggestion.dart
import 'package:flutter/material.dart';
import '../../design/tokens.dart';

/// 内置斜杠命令(名称 + 说明)。
class SlashCommand {
  final String cmd;
  final String desc;
  const SlashCommand(this.cmd, this.desc);
}

class SlashSuggestionPanel extends StatelessWidget {
  final List<SlashCommand> matches;
  final bool isDark;
  final ValueChanged<String> onPick;

  const SlashSuggestionPanel({
    super.key,
    required this.matches,
    required this.isDark,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.forDark(isDark);
    final bg = c.surface;
    final fg = c.textPrimary;
    final sub = c.textSecondary;
    final accent = c.primary;
    final div = c.border;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(left: 10, right: 10, bottom: 6),
        constraints: const BoxConstraints(maxHeight: 220),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: div, width: 0.5),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(
                    alpha: isDark ? 0.4 : 0.08),
                blurRadius: 12,
                offset: const Offset(0, 2)),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: ListView.separated(
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(vertical: 4),
          itemCount: matches.length,
          separatorBuilder: (_, __) =>
              Divider(height: 1, thickness: 0.5, color: div, indent: 50),
          itemBuilder: (_, i) {
            final c = matches[i];
            return InkWell(
              onTap: () => onPick(c.cmd),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(children: [
                  Container(
                    width: 28,
                    height: 28,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8)),
                    child: Icon(Icons.terminal_rounded,
                        size: 16, color: accent),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                        Text(c.cmd,
                            style: TextStyle(
                                color: fg,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                fontFamily: 'monospace')),
                        const SizedBox(height: 1),
                        Text(c.desc,
                            style: TextStyle(color: sub, fontSize: 12)),
                      ])),
                ]),
              ),
            );
          },
        ),
      ),
    );
  }
}
