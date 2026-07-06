// lib/screens/chat/voice_overlay.dart
import 'dart:math';
import 'package:flutter/material.dart';

class VoiceOverlay extends StatefulWidget {
  final double amplitude;
  final bool isCancel;
  final bool isDark;

  const VoiceOverlay({
    super.key,
    required this.amplitude,
    required this.isCancel,
    required this.isDark,
  });

  @override
  State<VoiceOverlay> createState() => _VoiceOverlayState();
}

class _VoiceOverlayState extends State<VoiceOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  final Stopwatch _sw = Stopwatch();

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1500))
      ..repeat();
    _sw.start();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _sw.stop();
    super.dispose();
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final cancel = widget.isCancel;
    final accent = cancel ? Colors.redAccent : const Color(0xFF5B4BD6);
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        final t = _ctrl.value;
        final amp = (widget.amplitude.clamp(0.0, 1.0)) * 0.75 + 0.20;
        return Container(
          height: 60,
          decoration: BoxDecoration(
            color: widget.isDark
                ? const Color(0xFF1C1C1E)
                : const Color(0xFFF7F7F8),
            border: Border(
                top: BorderSide(
                    color: widget.isDark
                        ? const Color(0xFF3A3A3C)
                        : const Color(0xFFE0E0E5),
                    width: 0.5)),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                        colors: [accent, accent.withValues(alpha: 0.65)]),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                          color: accent.withValues(alpha: 0.35),
                          blurRadius: 8,
                          spreadRadius: 0.5)
                    ],
                  ),
                  child: Icon(
                      cancel ? Icons.delete_outline : Icons.mic_rounded,
                      color: Colors.white,
                      size: 18),
                ),
                const SizedBox(width: 12),
                SizedBox(
                    height: 30,
                    child: Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: List.generate(5, (i) {
                          final phase = t * 2 * pi + i * 0.6;
                          final wave = 0.5 + 0.5 * sin(phase);
                          final h =
                              (8 + wave * 20 * amp).clamp(6.0, 28.0);
                          return Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 3),
                            child: Container(
                              width: 5,
                              height: h,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                    begin: Alignment.bottomCenter,
                                    end: Alignment.topCenter,
                                    colors: [
                                      accent.withValues(alpha: 0.5),
                                      accent
                                    ]),
                                borderRadius:
                                    BorderRadius.circular(3),
                              ),
                            ),
                          );
                        }))),
                const SizedBox(width: 12),
                Text(_fmt(_sw.elapsed),
                    style: TextStyle(
                        color: widget.isDark
                            ? Colors.white
                            : const Color(0xFF333333),
                        fontSize: 14,
                        fontWeight: FontWeight.w600)),
                const Spacer(),
                Text(cancel ? '松开取消' : '上划取消',
                    style: TextStyle(
                        color: cancel
                            ? Colors.redAccent
                            : (widget.isDark
                                ? Colors.white54
                                : const Color(0xFF9E9E9E)),
                        fontSize: 12)),
              ]),
            ),
          ),
        );
      },
    );
  }
}
