import 'package:flutter/material.dart';
import '../../design/tokens.dart';

/// 由拖动手势在「轨道」坐标系中的位置换算滚动比例。
///
/// [trackY] 手指在轨道内的 y；[grabOffset] 按下时手指距滑块顶部的距离（保持
/// 抓取点不跳）；返回 0..1。纯函数，便于单测。
double thumbFraction({
  required double trackY,
  required double grabOffset,
  required double trackHeight,
  required double thumbHeight,
}) {
  final range = trackHeight - thumbHeight;
  if (range <= 0) return 0;
  return ((trackY - grabOffset) / range).clamp(0.0, 1.0);
}

class ScrollThumbOverlay extends StatefulWidget {
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
  State<ScrollThumbOverlay> createState() => _ScrollThumbOverlayState();
}

class _ScrollThumbOverlayState extends State<ScrollThumbOverlay> {
  final GlobalKey _trackKey = GlobalKey();
  double _grab = 0;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.forDark(widget.isDark);
    return LayoutBuilder(key: _trackKey, builder: (ctx, box) {
      final trackHeight = box.maxHeight;
      final thumbHeight = (trackHeight * 0.18).clamp(44.0, 110.0);
      final clampedFrac = widget.fraction.clamp(0.0, 1.0);
      final thumbTop = (clampedFrac * (trackHeight - thumbHeight))
          .clamp(0.0, (trackHeight - thumbHeight).clamp(0.0, double.infinity));
      final dragging = widget.showDate;

      void update(Offset global) {
        // 早先实现用 thumb 自身的 localPosition 除以轨道高度，手指一动滑块就
        // 跳回顶部附近。这里统一换算到轨道坐标系，并扣除按下时的抓取偏移。
        final rb = _trackKey.currentContext?.findRenderObject() as RenderBox?;
        if (rb == null) return;
        final y = rb.globalToLocal(global).dy;
        widget.onDrag?.call(thumbFraction(
            trackY: y,
            grabOffset: _grab,
            trackHeight: trackHeight,
            thumbHeight: thumbHeight));
      }

      return Stack(fit: StackFit.expand, children: [
        if (widget.showDate && widget.dateLabel != null)
          Positioned(
            right: 40,
            top: (thumbTop + thumbHeight / 2 - 18)
                .clamp(0.0, (trackHeight - 36).clamp(0.0, double.infinity)),
            child: Container(
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: c.border, width: 0.5),
                boxShadow: AppShadows.card(widget.isDark),
              ),
              child: Text(
                widget.dateLabel!,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: c.textPrimary,
                ),
              ),
            ),
          ),
        Positioned(
          right: 2,
          top: thumbTop,
          width: 28,
          height: thumbHeight,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onVerticalDragStart: (d) => _grab = d.localPosition.dy,
            onVerticalDragUpdate: (d) => update(d.globalPosition),
            onVerticalDragEnd: (_) => widget.onDragEnd?.call(),
            onVerticalDragCancel: () => widget.onDragEnd?.call(),
            child: Center(
              child: AnimatedContainer(
                duration: AppMotion.fast,
                width: dragging ? 6 : 4,
                height: thumbHeight * 0.7,
                decoration: BoxDecoration(
                  color: dragging
                      ? c.primary
                      : c.textTertiary.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          ),
        ),
      ]);
    });
  }
}
