// lib/design/tokens.dart
//
// 设计令牌系统：全应用统一的视觉基础。
// 语义化命名，与具体 UI 解耦。暗/亮模式各一套完整定义。

import 'package:flutter/material.dart';

// ====== 颜色 ======

class AppColors {
  final Color surface;
  final Color surfaceCard;
  final Color primary;
  final Color onPrimary;
  final Color textPrimary;
  final Color textSecondary;
  final Color bubbleMine;
  final Color bubbleOther;
  final Color bubbleMineText;
  final Color bubbleOtherText;
  final Color error;
  final Color success;
  final Color warning;
  final Color border;
  final Color divider;
  final Color dimmed;
  final Color toolBg;
  final Color toolText;
  final Color thinkingText;
  final Color streamingBg;
  final Color streamingText;

  const AppColors({
    required this.surface,
    required this.surfaceCard,
    required this.primary,
    required this.onPrimary,
    required this.textPrimary,
    required this.textSecondary,
    required this.bubbleMine,
    required this.bubbleOther,
    required this.bubbleMineText,
    required this.bubbleOtherText,
    required this.error,
    required this.success,
    required this.warning,
    required this.border,
    required this.divider,
    required this.dimmed,
    required this.toolBg,
    required this.toolText,
    required this.thinkingText,
    required this.streamingBg,
    required this.streamingText,
  });

  static const light = AppColors(
    surface: Color(0xFFFAFAFB),
    surfaceCard: Colors.white,
    primary: Color(0xFF5B4BD6),
    onPrimary: Colors.white,
    textPrimary: Color(0xFF1C1C1E),
    textSecondary: Color(0xFF8A8A8E),
    bubbleMine: Color(0xFF5B4BD6),
    bubbleOther: Color(0xFFE8E8EC),
    bubbleMineText: Colors.white,
    bubbleOtherText: Colors.black,
    error: Color(0xFFFF3B30),
    success: Color(0xFF34C759),
    warning: Color(0xFFFF9500),
    border: Color(0xFFE5E5EA),
    divider: Color(0xFFE0E0E5),
    dimmed: Color(0xFF9E9E9E),
    toolBg: Color(0xFF007AFF),
    toolText: Color(0xFF007AFF),
    thinkingText: Color(0xFF8A8A8E),
    streamingBg: Color(0xFFE8E8EC),
    streamingText: Colors.black,
  );

  static const dark = AppColors(
    surface: Color(0xFF0F0F0F),
    surfaceCard: Color(0xFF1A1A1D),
    primary: Color(0xFF7661D8),
    onPrimary: Colors.white,
    textPrimary: Colors.white,
    textSecondary: Color(0xFF8E8E93),
    bubbleMine: Color(0xFF7661D8),
    bubbleOther: Color(0xFF212121),
    bubbleMineText: Colors.white,
    bubbleOtherText: Colors.white,
    error: Color(0xFFFF6B6B),
    success: Color(0xFF34C759),
    warning: Color(0xFFFF9500),
    border: Color(0xFF3A3A3C),
    divider: Color(0xFF3A3A3C),
    dimmed: Color(0xFF6D6D72),
    toolBg: Color(0xFF007AFF),
    toolText: Color(0xFF007AFF),
    thinkingText: Color(0xFF9E9EA4),
    streamingBg: Color(0xFF212121),
    streamingText: Colors.white,
  );

  /// 从当前主题亮度获取颜色集
  static AppColors of(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark ? dark : light;
  }
}

// ====== 间距 (4px 网格) ======

class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xl2 = 24;
  static const double xl3 = 32;
}

// ====== 圆角 ======

class AppRadius {
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double full = 999;
}

// ====== 阴影 ======

class AppShadows {
  static List<BoxShadow> card(bool isDark) => [
        BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.08),
            blurRadius: 12,
            offset: const Offset(0, 2)),
      ];

  static List<BoxShadow> bubble(bool isDark) => [
        BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
            blurRadius: 4,
            offset: const Offset(0, 1)),
      ];

  static List<BoxShadow> fab(bool isDark) => [
        BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.15),
            blurRadius: 12,
            offset: const Offset(0, 4)),
      ];
}

// ====== 字体 ======

class AppText {
  static const body = TextStyle(fontSize: 16, height: 1.35);
  static const caption = TextStyle(fontSize: 12, height: 1.2);
  static const captionMono =
      TextStyle(fontSize: 11, height: 1.3, fontFamily: 'monospace');
  static const title =
      TextStyle(fontSize: 15, fontWeight: FontWeight.w600);
  static TextStyle time(TextStyle base) =>
      base.copyWith(fontSize: 10, height: 1.2);
}
