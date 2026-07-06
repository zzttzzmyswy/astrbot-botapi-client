// lib/screens/chat/input_bar.dart
import 'package:flutter/material.dart';
import 'slash_suggestion.dart';

const Color _accent = Color(0xFF5B4BD6);

class ChatInputBar extends StatelessWidget {
  final VoidCallback send;
  final VoidCallback showAttachment;
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool isDark;
  final bool hasText;
  final VoidCallback onVoiceStart;
  final void Function(double dy) onVoiceMove;
  final VoidCallback onVoiceEnd;
  final List<SlashCommand> slashMatches;
  final ValueChanged<String> onPickSlash;

  const ChatInputBar({
    super.key,
    required this.send,
    required this.showAttachment,
    required this.controller,
    required this.focusNode,
    required this.isDark,
    required this.hasText,
    required this.onVoiceStart,
    required this.onVoiceMove,
    required this.onVoiceEnd,
    this.slashMatches = const [],
    required this.onPickSlash,
  });

  @override
  Widget build(BuildContext context) {
    final bg = isDark ? const Color(0xFF1C1C1E) : const Color(0xFFF7F7F8);
    final fieldBg = isDark ? const Color(0xFF3A3A3C) : const Color(0xFFFFFFFF);
    final txt = isDark ? Colors.white : Colors.black;
    final hint = isDark ? const Color(0xFF6D6D72) : const Color(0xFFC4C4C6);
    final pad = MediaQuery.of(context).padding;
    final keyVisible = MediaQuery.of(context).viewInsets.bottom > 0;

    return Column(mainAxisSize: MainAxisSize.min, children: [
      if (slashMatches.isNotEmpty)
        SlashSuggestionPanel(
            matches: slashMatches, isDark: isDark, onPick: onPickSlash),
      Container(
        padding: EdgeInsets.only(
            left: 6,
            right: 6,
            top: 6,
            bottom: (keyVisible ? 6 : 6 + pad.bottom)),
        decoration: BoxDecoration(
            color: bg,
            border: Border(
                top: BorderSide(
                    color: isDark
                        ? const Color(0xFF3A3A3C)
                        : const Color(0xFFE5E5EA),
                    width: 0.5))),
        child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              GestureDetector(
                  onTap: showAttachment,
                  child: SizedBox(
                      width: 44,
                      height: 44,
                      child: Center(
                          child: Icon(Icons.attach_file_rounded,
                              color: _accent, size: 24)))),
              Expanded(
                  child: Container(
                constraints: const BoxConstraints(maxHeight: 120),
                decoration: BoxDecoration(
                    color: fieldBg,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                        color: isDark
                            ? const Color(0xFF545458)
                            : const Color(0xFFE0E0E5),
                        width: 1)),
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  maxLines: null,
                  textCapitalization: TextCapitalization.sentences,
                  style: TextStyle(color: txt, fontSize: 16),
                  decoration: InputDecoration(
                    hintText: '消息',
                    hintStyle: TextStyle(color: hint, fontSize: 16),
                    border: InputBorder.none,
                    isCollapsed: true,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                  ),
                ),
              )),
              const SizedBox(width: 6),
              hasText
                  ? GestureDetector(
                      onTap: send,
                      child: Container(
                        width: 42,
                        height: 42,
                        decoration: const BoxDecoration(
                            shape: BoxShape.circle, color: Color(0xFF5B4BD6)),
                        child: const Icon(Icons.send_rounded,
                            color: Colors.white, size: 22),
                      ),
                    )
                  : GestureDetector(
                      onLongPressStart: (_) => onVoiceStart(),
                      onLongPressMoveUpdate: (d) =>
                          onVoiceMove(d.localPosition.dy),
                      onLongPressEnd: (_) => onVoiceEnd(),
                      child: Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _accent.withValues(
                                alpha: isDark ? 0.22 : 0.12)),
                        child: Icon(Icons.mic_none_rounded,
                            color: _accent, size: 22),
                      ),
                    ),
            ]),
      ),
    ]);
  }
}
