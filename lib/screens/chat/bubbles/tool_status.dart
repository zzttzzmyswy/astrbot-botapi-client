// lib/screens/chat/bubbles/tool_status.dart
import 'package:flutter/material.dart';

class ToolStatus extends StatelessWidget {
  final String text;
  const ToolStatus({super.key, required this.text});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 2),
        child: Container(
          decoration: BoxDecoration(
              color: const Color(0xFF007AFF).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8)),
          padding: const EdgeInsets.all(8),
          child: Text(text,
              style: const TextStyle(
                  color: Color(0xFF007AFF),
                  fontSize: 12,
                  fontFamily: 'monospace')),
        ),
      );
}
