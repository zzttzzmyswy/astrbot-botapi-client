// lib/screens/chat/app_bar.dart
import 'dart:math';
import 'package:flutter/material.dart';
import '../../design/tokens.dart';
import '../../screens/settings_screen.dart';

class ChatAppBar extends StatelessWidget implements PreferredSizeWidget {
  final bool connected;
  final bool isDark;
  final String? error;
  final String accountName;
  final String sessionName;
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
    this.sessionName = '默认会话',
    this.streaming = false,
    this.autoPlay = false,
    this.reconnecting = false,
    required this.onToggleAutoPlay,
  });

  @override
  Size get preferredSize => const Size.fromHeight(60);

  @override
  Widget build(BuildContext context) {
    final c = AppColors.forDark(isDark);
    final statusText = connected
        ? '在线'
        : (reconnecting ? '重连中…' : (error == null ? '未连接' : '离线'));
    final statusColor =
        connected ? c.success : (reconnecting ? c.warning : c.error);

    return AppBar(
      toolbarHeight: 60,
      titleSpacing: 0,
      leading: Builder(
        builder: (ctx) => IconButton(
          icon: const Icon(Icons.menu_rounded),
          color: c.textPrimary,
          onPressed: () => Scaffold.of(ctx).openDrawer(),
          tooltip: '账户与会话',
        ),
      ),
      title: Builder(
        builder: (ctx) => InkWell(
          borderRadius: BorderRadius.circular(AppRadius.md),
          onTap: () => Scaffold.of(ctx).openDrawer(),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
            child: Row(children: [
              _Avatar(
                  name: accountName, statusColor: statusColor, surface: c.surface),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(accountName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 16,
                            height: 1.25,
                            fontWeight: FontWeight.w600,
                            color: c.textPrimary)),
                    const SizedBox(height: 2),
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      // 当前会话标识。Flexible 让超长会话名收缩而非溢出标题栏。
                      Flexible(
                        child: Text(sessionName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 12,
                                height: 1.2,
                                fontWeight: FontWeight.w500,
                                color: c.textSecondary)),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 5),
                        child: Text('·',
                            style: TextStyle(
                                fontSize: 12, color: c.textTertiary)),
                      ),
                      if (streaming) ...[
                        _TypingDots(color: c.primary),
                        const SizedBox(width: 4),
                        Text('正在输入',
                            style: TextStyle(
                                fontSize: 12,
                                height: 1.2,
                                color: c.primary,
                                fontWeight: FontWeight.w500)),
                      ] else
                        Text(statusText,
                            style: TextStyle(
                                fontSize: 12,
                                height: 1.2,
                                color: statusColor,
                                fontWeight: FontWeight.w500)),
                    ]),
                  ],
                ),
              ),
            ]),
          ),
        ),
      ),
      actions: [
        IconButton(
          tooltip: autoPlay ? '语音自动播放：开' : '语音自动播放：关',
          onPressed: onToggleAutoPlay,
          isSelected: autoPlay,
          style: IconButton.styleFrom(
            backgroundColor: autoPlay ? c.primarySoft : Colors.transparent,
          ),
          icon: Icon(
            autoPlay ? Icons.volume_up_rounded : Icons.volume_off_outlined,
            size: 22,
            color: autoPlay ? c.primary : c.textSecondary,
          ),
        ),
        IconButton(
          tooltip: '设置',
          icon: Icon(Icons.tune_rounded, size: 22, color: c.textSecondary),
          onPressed: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const SettingsScreen())),
        ),
        const SizedBox(width: 4),
      ],
    );
  }
}

class _Avatar extends StatelessWidget {
  final String name;
  final Color statusColor;
  final Color surface;
  const _Avatar(
      {required this.name, required this.statusColor, required this.surface});

  @override
  Widget build(BuildContext context) {
    final g = avatarGradientFor(name);
    // 无账户时 accountName 为占位文案，不取首字。
    final initial = (name.trim().isEmpty || name == '未选择账户')
        ? null
        : name.trim().characters.first.toUpperCase();
    return SizedBox(
      width: 38,
      height: 38,
      child: Stack(clipBehavior: Clip.none, children: [
        Container(
          width: 38,
          height: 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: g),
            borderRadius: BorderRadius.circular(12),
          ),
          child: initial == null
              ? const Icon(Icons.smart_toy_rounded,
                  color: Colors.white, size: 20)
              : Text(initial,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700)),
        ),
        Positioned(
          right: -2,
          bottom: -2,
          child: AnimatedContainer(
            duration: AppMotion.normal,
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: statusColor,
              shape: BoxShape.circle,
              border: Border.all(color: surface, width: 2),
            ),
          ),
        ),
      ]),
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
          children: List.generate(3, (i) {
            final phase = (v + i / 3) % 1.0;
            final pulse = sin(phase * pi);
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1.2),
              child: Transform.translate(
                offset: Offset(0, -1.5 * pulse),
                child: Container(
                  width: 4.5,
                  height: 4.5,
                  decoration: BoxDecoration(
                    color: widget.color.withValues(alpha: 0.35 + 0.65 * pulse),
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
