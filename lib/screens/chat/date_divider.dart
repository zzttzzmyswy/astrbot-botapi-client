// lib/screens/chat/date_divider.dart
import 'package:flutter/material.dart';

class DateDivider extends StatelessWidget {
  final String label;
  final bool isDark;

  const DateDivider({super.key, required this.label, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final fg = isDark ? const Color(0xFF8E8E93) : const Color(0xFF8A8A8E);
    final bg = isDark ? const Color(0xFF2A2A2E) : const Color(0xFFE8E8EC);
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 10),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration:
            BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
        child: Text(label,
            style: TextStyle(
                fontSize: 11, color: fg, fontWeight: FontWeight.w500)),
      ),
    );
  }
}
