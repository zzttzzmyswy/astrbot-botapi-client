// lib/screens/chat/bubbles/thinking_block.dart
import 'package:flutter/material.dart';

class ThinkingBlock extends StatefulWidget {
  final String text;
  final bool isDark;

  const ThinkingBlock({super.key, required this.text, required this.isDark});

  @override
  State<ThinkingBlock> createState() => _ThinkingBlockState();
}

class _ThinkingBlockState extends State<ThinkingBlock> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final fg =
        widget.isDark ? const Color(0xFF9E9EA4) : const Color(0xFF8A8A8E);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 2),
      child: Container(
        decoration: BoxDecoration(
            color: fg.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8)),
        child: Column(children: [
          InkWell(
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(children: [
                const Icon(Icons.psychology_outlined,
                    size: 14, color: Color(0xFF8A8A8E)),
                const SizedBox(width: 6),
                Expanded(
                    child: Text('思考过程',
                        style: TextStyle(
                            color: fg,
                            fontSize: 12,
                            fontWeight: FontWeight.w500))),
                AnimatedRotation(
                    turns: _open ? 0.5 : 0,
                    duration: const Duration(milliseconds: 150),
                    child: Icon(Icons.expand_more, color: fg, size: 16)),
              ]),
            ),
          ),
          if (_open)
            Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                child: Text(widget.text,
                    style: TextStyle(
                        color: fg,
                        fontSize: 11,
                        height: 1.3,
                        fontFamily: 'monospace'))),
        ]),
      ),
    );
  }
}
