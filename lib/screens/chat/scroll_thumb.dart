// lib/screens/chat/scroll_thumb.dart
import 'package:flutter/material.dart';

class ScrollThumbOverlay extends StatelessWidget {
  final double fraction;
  final bool isDark;
  final String? dateLabel;
  final bool showDate;
  final void Function(double frac)? onDrag;
  final VoidCallback? onDragEnd;

  const ScrollThumbOverlay({
    super.key,
    required this.fraction,
    required this.isDark,
    required this.dateLabel,
    required this.showDate,
    this.onDrag,
    this.onDragEnd,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (ctx, c) {
      final trackHeight = c.maxHeight;
      final thumbHeight = (trackHeight * 0.22).clamp(42.0, 130.0);
      final clampedFrac = fraction.clamp(0.0, 1.0);
      final thumbTop = (clampedFrac * (trackHeight - thumbHeight))
          .clamp(0.0, (trackHeight - thumbHeight).clamp(1.0, double.infinity));
      final thumbColor =
          isDark ? const Color(0xFFB0B0B5) : const Color(0xFF8A8A8E);

      return Stack(fit: StackFit.expand, children: [
        if (showDate && dateLabel != null)
          Center(
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF2A2A2E) : Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.18),
                      blurRadius: 10,
                      offset: const Offset(0, 2)),
                ],
              ),
              child: Text(
                dateLabel!,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : const Color(0xFF1C1C1E),
                ),
              ),
            ),
          ),
        Positioned(
          right: 3,
          top: thumbTop,
          width: 26,
          height: thumbHeight,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onVerticalDragUpdate: (d) {
              final h = trackHeight <= 0 ? 1.0 : trackHeight;
              final frac = (d.localPosition.dy / h).clamp(0.0, 1.0);
              onDrag?.call(frac);
            },
            onVerticalDragEnd: (_) => onDragEnd?.call(),
            child: Center(
              child: Container(
                width: 4,
                height: thumbHeight * 0.6,
                decoration: BoxDecoration(
                  color: thumbColor.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
        ),
      ]);
    });
  }
}
