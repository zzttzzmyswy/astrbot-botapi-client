// lib/screens/chat/app_bar.dart
import 'dart:math';
import 'package:flutter/material.dart';
import '../../screens/settings_screen.dart';

const Color _accent = Color(0xFF5B4BD6);

class ChatAppBar extends StatelessWidget implements PreferredSizeWidget {
  final bool connected;
  final bool isDark;
  final String? error;
  final String accountName;
  final bool streaming;
  final bool autoPlay;
  final bool reconnecting;
  final VoidCallback onToggleAutoPlay;

  const ChatAppBar({
    super.key,
    required this.connected,
    required this.isDark,
    this.error,
    required this.accountName,
    this.streaming = false,
    this.autoPlay = false,
    this.reconnecting = false,
    required this.onToggleAutoPlay,
  });

  @override
  Size get preferredSize => const Size.fromHeight(44);

  @override
  Widget build(BuildContext context) {
    final bg = isDark ? const Color(0xFF1C1C1E) : const Color(0xFFF7F7F8);
    final txt = isDark ? Colors.white : Colors.black;
    final statusText = connected
        ? '在线'
        : (reconnecting ? '重连中…' : (error ?? '未连接'));
    final statusColor = connected
        ? const Color(0xFF34C759)
        : (reconnecting ? const Color(0xFFFF9500) : const Color(0xFFFF6B6B));
    return AppBar(
      backgroundColor: bg,
      elevation: 0,
      titleSpacing: 0,
      leading: Builder(
        builder: (c) => IconButton(
          icon: const Icon(Icons.menu_rounded, size: 22),
          onPressed: () => Scaffold.of(c).openDrawer(),
          tooltip: '账户',
        ),
      ),
      title: Padding(
        padding: const EdgeInsets.only(left: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(accountName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: txt)),
            if (streaming)
              Row(mainAxisSize: MainAxisSize.min, children: [
                _TypingDots(color: _accent),
                const SizedBox(width: 6),
                Text('正在输入...',
                    style: TextStyle(fontSize: 11, color: _accent)),
              ])
            else
              Text(statusText,
                  style: TextStyle(fontSize: 11, color: statusColor)),
          ],
        ),
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onToggleAutoPlay,
            child: Tooltip(
              message: autoPlay ? '自动播放:开' : '自动播放:关',
              child: Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: autoPlay
                      ? _accent
                      : _accent.withValues(
                          alpha: isDark ? 0.22 : 0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  autoPlay
                      ? Icons.volume_up_rounded
                      : Icons.volume_off_rounded,
                  size: 20,
                  color: autoPlay ? Colors.white : _accent,
                ),
              ),
            ),
          ),
        ),
        IconButton(
          icon: Icon(Icons.more_vert, size: 20, color: txt),
          onPressed: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const SettingsScreen())),
        ),
      ],
    );
  }
}

class _TypingDots extends StatefulWidget {
  final Color color;
  const _TypingDots({required this.color});
  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  @override
  void initState() {
    super.initState();
    _c = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        final v = _c.value;
        return Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: List.generate(3, (i) {
            final phase = (v + i / 3) % 1.0;
            final pulse = sin(phase * pi);
            final opacity = 0.25 + 0.75 * pulse;
            final scale = 0.7 + 0.3 * pulse;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1.4),
              child: Transform.scale(
                scale: scale,
                child: Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: widget.color.withValues(alpha: opacity),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}
