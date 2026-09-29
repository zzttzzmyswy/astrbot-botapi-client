// lib/design/tokens.dart
//
// 设计令牌系统：全应用统一的视觉基础。
// 语义化命名，与具体 UI 解耦。暗/亮模式各一套完整定义，经 ThemeExtension
// 挂到 ThemeData 上，组件内统一用 `AppColors.of(context)` 取色，禁止散落硬编码。

import 'package:flutter/material.dart';

// ====== 颜色 ======

@immutable
class AppColors extends ThemeExtension<AppColors> {
  /// 页面底色（聊天区背景）。
  final Color background;

  /// 一级容器（顶栏、输入栏、卡片、抽屉）。
  final Color surface;

  /// 次级容器（输入框底、分组卡片内的块、chip）。
  final Color surfaceMuted;

  /// 品牌主色。
  final Color primary;
  final Color onPrimary;

  /// 主色的柔和底（选中态、tonal 按钮、图标底块）。
  final Color primarySoft;

  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;

  /// 我方气泡渐变（左上 → 右下）。
  final List<Color> bubbleMineGradient;
  final Color bubbleMineText;
  final Color bubbleOther;
  final Color bubbleOtherBorder;
  final Color bubbleOtherText;

  final Color error;
  final Color success;
  final Color warning;

  /// 工具调用提示色。
  final Color tool;

  final Color border;
  final Color divider;

  /// 代码块底色（对方气泡内）。
  final Color codeBg;

  /// 链接色（对方气泡内）。
  final Color link;

  const AppColors({
    required this.background,
    required this.surface,
    required this.surfaceMuted,
    required this.primary,
    required this.onPrimary,
    required this.primarySoft,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.bubbleMineGradient,
    required this.bubbleMineText,
    required this.bubbleOther,
    required this.bubbleOtherBorder,
    required this.bubbleOtherText,
    required this.error,
    required this.success,
    required this.warning,
    required this.tool,
    required this.border,
    required this.divider,
    required this.codeBg,
    required this.link,
  });

  static const light = AppColors(
    background: Color(0xFFF4F4F8),
    surface: Color(0xFFFFFFFF),
    surfaceMuted: Color(0xFFEDEDF3),
    primary: Color(0xFF5B4BD6),
    onPrimary: Colors.white,
    primarySoft: Color(0xFFECE9FC),
    textPrimary: Color(0xFF1B1B25),
    textSecondary: Color(0xFF6B6B7E),
    textTertiary: Color(0xFFA3A3B3),
    bubbleMineGradient: [Color(0xFF7466F2), Color(0xFF5646D4)],
    bubbleMineText: Colors.white,
    bubbleOther: Color(0xFFFFFFFF),
    bubbleOtherBorder: Color(0xFFE7E7EF),
    bubbleOtherText: Color(0xFF1B1B25),
    error: Color(0xFFE5484D),
    success: Color(0xFF1FA463),
    warning: Color(0xFFE08A00),
    tool: Color(0xFF0E8C80),
    border: Color(0xFFE4E4EC),
    divider: Color(0xFFEBEBF1),
    codeBg: Color(0xFFF3F3F8),
    link: Color(0xFF4F46E5),
  );

  static const dark = AppColors(
    background: Color(0xFF0E0E13),
    surface: Color(0xFF17171E),
    surfaceMuted: Color(0xFF22222B),
    primary: Color(0xFF8B7DFF),
    onPrimary: Colors.white,
    primarySoft: Color(0xFF2A2548),
    textPrimary: Color(0xFFECECF3),
    textSecondary: Color(0xFF9A9AAE),
    textTertiary: Color(0xFF65657A),
    bubbleMineGradient: [Color(0xFF7061EE), Color(0xFF5646D4)],
    bubbleMineText: Colors.white,
    bubbleOther: Color(0xFF1C1C25),
    bubbleOtherBorder: Color(0xFF282833),
    bubbleOtherText: Color(0xFFECECF3),
    error: Color(0xFFFF6369),
    success: Color(0xFF3DD68C),
    warning: Color(0xFFF5A524),
    tool: Color(0xFF3CCFBF),
    border: Color(0xFF2B2B36),
    divider: Color(0xFF24242D),
    codeBg: Color(0xFF121218),
    link: Color(0xFFA99FFF),
  );

  /// 从当前主题获取颜色集（主题未挂扩展时按亮度回退）。
  static AppColors of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<AppColors>() ??
        (theme.brightness == Brightness.dark ? dark : light);
  }

  /// 按亮度直接取（无 BuildContext 的纯函数场景）。
  static AppColors forDark(bool isDark) => isDark ? dark : light;

  @override
  AppColors copyWith() => this;

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppColors(
      background: l(background, other.background),
      surface: l(surface, other.surface),
      surfaceMuted: l(surfaceMuted, other.surfaceMuted),
      primary: l(primary, other.primary),
      onPrimary: l(onPrimary, other.onPrimary),
      primarySoft: l(primarySoft, other.primarySoft),
      textPrimary: l(textPrimary, other.textPrimary),
      textSecondary: l(textSecondary, other.textSecondary),
      textTertiary: l(textTertiary, other.textTertiary),
      bubbleMineGradient: [
        l(bubbleMineGradient[0], other.bubbleMineGradient[0]),
        l(bubbleMineGradient[1], other.bubbleMineGradient[1]),
      ],
      bubbleMineText: l(bubbleMineText, other.bubbleMineText),
      bubbleOther: l(bubbleOther, other.bubbleOther),
      bubbleOtherBorder: l(bubbleOtherBorder, other.bubbleOtherBorder),
      bubbleOtherText: l(bubbleOtherText, other.bubbleOtherText),
      error: l(error, other.error),
      success: l(success, other.success),
      warning: l(warning, other.warning),
      tool: l(tool, other.tool),
      border: l(border, other.border),
      divider: l(divider, other.divider),
      codeBg: l(codeBg, other.codeBg),
      link: l(link, other.link),
    );
  }
}

/// 头像配色：按名称哈希稳定取色，账户多时一眼可分。
const List<List<Color>> kAvatarGradients = [
  [Color(0xFF7466F2), Color(0xFF5646D4)],
  [Color(0xFF3B82F6), Color(0xFF2563EB)],
  [Color(0xFF14B8A6), Color(0xFF0D9488)],
  [Color(0xFFF59E0B), Color(0xFFEA7C0C)],
  [Color(0xFFEC4899), Color(0xFFD9336F)],
  [Color(0xFF8B5CF6), Color(0xFF6D28D9)],
];

List<Color> avatarGradientFor(String seed) {
  var h = 0;
  for (final c in seed.codeUnits) {
    h = (h * 31 + c) & 0x7fffffff;
  }
  return kAvatarGradients[h % kAvatarGradients.length];
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
  static const double bubble = 20;
  static const double bubbleTail = 6;
  static const double full = 999;
}

// ====== 阴影 ======

class AppShadows {
  static List<BoxShadow> card(bool isDark) => [
        BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.30 : 0.06),
            blurRadius: 16,
            offset: const Offset(0, 4)),
      ];

  static List<BoxShadow> bubble(bool isDark) => isDark
      ? const []
      : [
          BoxShadow(
              color: const Color(0xFF1B1B25).withValues(alpha: 0.04),
              blurRadius: 6,
              offset: const Offset(0, 1)),
        ];

  static List<BoxShadow> mine(Color c) => [
        BoxShadow(
            color: c.withValues(alpha: 0.22),
            blurRadius: 10,
            offset: const Offset(0, 3)),
      ];

  static List<BoxShadow> fab(bool isDark) => [
        BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.12),
            blurRadius: 14,
            offset: const Offset(0, 4)),
      ];
}

// ====== 字体 ======

class AppText {
  static const body = TextStyle(fontSize: 15.5, height: 1.5);
  static const caption = TextStyle(fontSize: 12, height: 1.3);
  static const captionMono =
      TextStyle(fontSize: 12, height: 1.45, fontFamily: 'monospace');
  static const title = TextStyle(fontSize: 16, fontWeight: FontWeight.w600);
  static TextStyle time(TextStyle base) =>
      base.copyWith(fontSize: 11, height: 1.2);
}

// ====== 动效 ======

class AppMotion {
  static const fast = Duration(milliseconds: 150);
  static const normal = Duration(milliseconds: 220);
  static const curve = Curves.easeOutCubic;
}
