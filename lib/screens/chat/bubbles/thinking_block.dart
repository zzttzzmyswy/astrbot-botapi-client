import 'package:flutter/material.dart';
import '../../../design/tokens.dart';

/// 思考过程：默认折叠为一枚胶囊，点击展开全文（左侧竖线引出）。
/// [streaming] 时标题显示「正在思考」并带呼吸动画。
class ThinkingBlock extends StatefulWidget {
  final String text;
  final bool isDark;
  final bool streaming;

  const ThinkingBlock({
    super.key,
    required this.text,
    required this.isDark,
    this.streaming = false,
  });

  @override
  State<ThinkingBlock> createState() => _ThinkingBlockState();
}

class _ThinkingBlockState extends State<ThinkingBlock>
    with SingleTickerProviderStateMixin {
  bool _open = false;
  AnimationController? _pulse;

  @override
  void initState() {
    super.initState();
    _syncPulse();
  }

  @override
  void didUpdateWidget(covariant ThinkingBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.streaming != widget.streaming) _syncPulse();
  }

  void _syncPulse() {
    if (widget.streaming) {
      _pulse ??= AnimationController(
          vsync: this, duration: const Duration(milliseconds: 1000));
      _pulse!.repeat(reverse: true);
    } else {
      _pulse?.stop();
    }
  }

  @override
  void dispose() {
    _pulse?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.forDark(widget.isDark);
    final sub = c.textSecondary;
    final title = widget.streaming ? '正在思考' : '思考过程';
    final count = widget.text.characters.length;

    Widget icon = Icon(Icons.auto_awesome_rounded, size: 14, color: c.primary);
    if (widget.streaming && _pulse != null) {
      icon = FadeTransition(
          opacity: Tween(begin: 0.3, end: 1.0).animate(_pulse!), child: icon);
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Material(
            color: c.surfaceMuted.withValues(alpha: widget.isDark ? 0.8 : 1),
            borderRadius: BorderRadius.circular(AppRadius.full),
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadius.full),
              onTap: () => setState(() => _open = !_open),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 6, 8, 6),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  icon,
                  const SizedBox(width: 6),
                  Text(title,
                      style: TextStyle(
                          color: sub,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600)),
                  if (!widget.streaming && count > 0) ...[
                    const SizedBox(width: 6),
                    Text('$count 字',
                        style: TextStyle(color: c.textTertiary, fontSize: 11.5)),
                  ],
                  const SizedBox(width: 2),
                  AnimatedRotation(
                      turns: _open ? 0.5 : 0,
                      duration: AppMotion.fast,
                      child: Icon(Icons.expand_more_rounded,
                          color: c.textTertiary, size: 18)),
                ]),
              ),
            ),
          ),
          AnimatedSize(
            duration: AppMotion.normal,
            curve: AppMotion.curve,
            alignment: Alignment.topLeft,
            child: _open
                ? Container(
                    margin: const EdgeInsets.only(top: 8, left: 10),
                    padding: const EdgeInsets.only(left: 12, right: 8),
                    decoration: BoxDecoration(
                      border: Border(
                          left: BorderSide(color: c.border, width: 2)),
                    ),
                    child: SelectableText(widget.text,
                        style: TextStyle(
                            color: sub, fontSize: 13, height: 1.6)),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}
