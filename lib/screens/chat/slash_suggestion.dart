// lib/screens/chat/slash_suggestion.dart
import 'package:flutter/material.dart';

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
    final bg = isDark ? const Color(0xFF2C2C2E) : const Color(0xFFFFFFFF);
    final fg = isDark ? Colors.white : const Color(0xFF1C1C1E);
    final sub = isDark ? const Color(0xFF9E9EA4) : const Color(0xFF8A8A8E);
    final accent = const Color(0xFF5B4BD6);
    final div = isDark ? const Color(0xFF3A3A3C) : const Color(0xFFE5E5EA);
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(left: 8, right: 8, bottom: 4),
        constraints: const BoxConstraints(maxHeight: 220),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: div, width: 0.5),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(
                    alpha: isDark ? 0.4 : 0.08),
                blurRadius: 12,
                offset: const Offset(0, 2)),
          ],
        ),
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
