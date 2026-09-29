// lib/screens/chat/input_bar.dart
import 'dart:math';
import 'package:flutter/material.dart';
import '../../design/tokens.dart';
import 'slash_suggestion.dart';

class ChatInputBar extends StatelessWidget {
  final VoidCallback send;
  final VoidCallback showAttachment;
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool isDark;
  final bool hasText;
  final bool attachOpen;
  final VoidCallback onVoiceStart;
  final void Function(double dy) onVoiceMove;
  final VoidCallback onVoiceEnd;
  final VoidCallback? onVoiceCancel;
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
    this.attachOpen = false,
    required this.onVoiceStart,
    required this.onVoiceMove,
    required this.onVoiceEnd,
    this.onVoiceCancel,
    this.slashMatches = const [],
    required this.onPickSlash,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.forDark(isDark);
    final pad = MediaQuery.of(context).padding;
    final keyVisible = MediaQuery.of(context).viewInsets.bottom > 0;

    return Column(mainAxisSize: MainAxisSize.min, children: [
      if (slashMatches.isNotEmpty)
        SlashSuggestionPanel(
            matches: slashMatches, isDark: isDark, onPick: onPickSlash),
      Container(
        padding: EdgeInsets.only(
            left: 8,
            right: 8,
            top: 8,
            bottom: (keyVisible ? 8 : 8 + pad.bottom)),
        decoration: BoxDecoration(
            color: c.surface,
            border: Border(top: BorderSide(color: c.divider, width: 0.5))),
        child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _RoundButton(
                tooltip: attachOpen ? '收起' : '附件',
                onTap: showAttachment,
                bg: attachOpen ? c.primarySoft : c.surfaceMuted,
                child: AnimatedRotation(
                  turns: attachOpen ? 0.125 : 0,
                  duration: AppMotion.normal,
                  curve: AppMotion.curve,
                  child: Icon(Icons.add_rounded,
                      color: attachOpen ? c.primary : c.textSecondary,
                      size: 26),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                  child: Container(
                constraints: const BoxConstraints(minHeight: 44, maxHeight: 140),
                decoration: BoxDecoration(
                  color: c.surfaceMuted,
                  borderRadius: BorderRadius.circular(22),
                ),
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  maxLines: null,
                  textCapitalization: TextCapitalization.sentences,
                  cursorColor: c.primary,
                  style: TextStyle(
                      color: c.textPrimary, fontSize: 16, height: 1.35),
                  decoration: InputDecoration(
                    hintText: '发消息，或输入 / 使用指令',
                    hintStyle: TextStyle(color: c.textTertiary, fontSize: 15.5),
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    isCollapsed: true,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                  ),
                ),
              )),
              const SizedBox(width: 8),
              AnimatedSwitcher(
                duration: AppMotion.normal,
                switchInCurve: Curves.easeOutBack,
                transitionBuilder: (child, animation) =>
                    ScaleTransition(scale: animation, child: child),
                child: hasText
                    ? _RoundButton(
                        key: const ValueKey('send'),
                        tooltip: '发送',
                        onTap: send,
                        gradient: c.bubbleMineGradient,
                        shadow: AppShadows.mine(c.bubbleMineGradient[1]),
                        child: const Icon(Icons.arrow_upward_rounded,
                            color: Colors.white, size: 22),
                      )
                    : GestureDetector(
                        key: const ValueKey('mic'),
                        onLongPressStart: (_) => onVoiceStart(),
                        onLongPressMoveUpdate: (d) =>
                            onVoiceMove(d.localPosition.dy),
                        onLongPressEnd: (_) => onVoiceEnd(),
                        onLongPressCancel: onVoiceCancel,
                        child: Tooltip(
                          message: '按住说话',
                          child: Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                                shape: BoxShape.circle, color: c.surfaceMuted),
                            child: Icon(Icons.mic_none_rounded,
                                color: c.textSecondary, size: 24),
                          ),
                        ),
                      ),
              ),
            ]),
      ),
    ]);
  }
}

class _RoundButton extends StatelessWidget {
  final VoidCallback onTap;
  final Widget child;
  final String tooltip;
  final Color? bg;
  final List<Color>? gradient;
  final List<BoxShadow>? shadow;

  const _RoundButton({
    super.key,
    required this.onTap,
    required this.child,
    required this.tooltip,
    this.bg,
    this.gradient,
    this.shadow,
  });

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: gradient == null ? bg : null,
            gradient: gradient == null
                ? null
                : LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: gradient!,
                    transform: const GradientRotation(pi / 8)),
            boxShadow: shadow,
          ),
          child: Material(
            type: MaterialType.transparency,
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              child: SizedBox(width: 44, height: 44, child: Center(child: child)),
            ),
          ),
        ),
      );
}
