// lib/design/theme.dart
//
// 由设计令牌生成 Material 3 主题。所有系统组件（AppBar / 输入框 / 按钮 /
// 对话框 / 菜单 / SnackBar ...）在此统一定调，页面内不再逐个覆写样式。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'tokens.dart';

ThemeData buildAppTheme(Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  final c = AppColors.forDark(isDark);

  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.light.primary,
    brightness: brightness,
  ).copyWith(
    primary: c.primary,
    onPrimary: c.onPrimary,
    primaryContainer: c.primarySoft,
    onPrimaryContainer: c.primary,
    secondaryContainer: c.primarySoft,
    onSecondaryContainer: c.primary,
    surface: c.surface,
    onSurface: c.textPrimary,
    onSurfaceVariant: c.textSecondary,
    surfaceContainerLowest: c.background,
    surfaceContainerLow: c.surface,
    surfaceContainer: c.surface,
    surfaceContainerHigh: c.surface,
    surfaceContainerHighest: c.surfaceMuted,
    outline: c.border,
    outlineVariant: c.divider,
    error: c.error,
  );

  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    extensions: [c],
  );

  final radius12 = BorderRadius.circular(AppRadius.md);
  final radius14 = BorderRadius.circular(14);

  return base.copyWith(
    scaffoldBackgroundColor: c.background,
    canvasColor: c.surface,
    cardColor: c.surface,
    dividerColor: c.divider,
    splashFactory: InkSparkle.splashFactory,
    textTheme: base.textTheme.apply(
      bodyColor: c.textPrimary,
      displayColor: c.textPrimary,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: c.surface,
      surfaceTintColor: Colors.transparent,
      foregroundColor: c.textPrimary,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
          fontSize: 18, fontWeight: FontWeight.w600, color: c.textPrimary),
      systemOverlayStyle: (isDark
              ? SystemUiOverlayStyle.light
              : SystemUiOverlayStyle.dark)
          .copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness:
            isDark ? Brightness.light : Brightness.dark,
      ),
      shape: Border(bottom: BorderSide(color: c.divider, width: 0.5)),
    ),
    dividerTheme: DividerThemeData(color: c.divider, thickness: 0.5, space: 1),
    iconTheme: IconThemeData(color: c.textSecondary),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.surfaceMuted,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      hintStyle: TextStyle(color: c.textTertiary),
      labelStyle: TextStyle(color: c.textSecondary),
      floatingLabelStyle: TextStyle(color: c.primary),
      prefixIconColor: c.textTertiary,
      suffixIconColor: c.textTertiary,
      border: OutlineInputBorder(
          borderRadius: radius14, borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(
          borderRadius: radius14,
          borderSide: const BorderSide(color: Colors.transparent, width: 1.2)),
      focusedBorder: OutlineInputBorder(
          borderRadius: radius14,
          borderSide: BorderSide(color: c.primary, width: 1.5)),
      errorBorder: OutlineInputBorder(
          borderRadius: radius14,
          borderSide: BorderSide(color: c.error, width: 1.2)),
      focusedErrorBorder: OutlineInputBorder(
          borderRadius: radius14,
          borderSide: BorderSide(color: c.error, width: 1.5)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: c.primary,
        foregroundColor: c.onPrimary,
        disabledBackgroundColor: c.primary.withValues(alpha: 0.45),
        disabledForegroundColor: c.onPrimary.withValues(alpha: 0.8),
        minimumSize: const Size(64, 50),
        shape: RoundedRectangleBorder(borderRadius: radius14),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: c.primary,
        shape: RoundedRectangleBorder(borderRadius: radius12),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: c.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      titleTextStyle: TextStyle(
          fontSize: 18, fontWeight: FontWeight.w600, color: c.textPrimary),
      contentTextStyle:
          TextStyle(fontSize: 14.5, height: 1.5, color: c.textSecondary),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: c.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 8,
      shadowColor: Colors.black.withValues(alpha: isDark ? 0.6 : 0.18),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: c.border, width: 0.5)),
      textStyle: TextStyle(fontSize: 14.5, color: c.textPrimary),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: isDark ? const Color(0xFF2A2A35) : const Color(0xFF26262F),
      contentTextStyle: const TextStyle(color: Colors.white, fontSize: 14),
      shape: RoundedRectangleBorder(borderRadius: radius12),
      insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: c.textSecondary,
      textColor: c.textPrimary,
      subtitleTextStyle: TextStyle(fontSize: 12.5, color: c.textSecondary),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
    ),
    drawerTheme: DrawerThemeData(
      backgroundColor: c.surface,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.horizontal(right: Radius.circular(24))),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: c.primary,
      linearTrackColor: c.primarySoft,
      circularTrackColor: Colors.transparent,
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        visualDensity: VisualDensity.compact,
        side: WidgetStatePropertyAll(BorderSide(color: c.border)),
        backgroundColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? c.primarySoft : Colors.transparent),
        foregroundColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? c.primary : c.textSecondary),
      ),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
          color: isDark ? const Color(0xFF2A2A35) : const Color(0xFF26262F),
          borderRadius: BorderRadius.circular(8)),
      textStyle: const TextStyle(color: Colors.white, fontSize: 12),
    ),
  );
}
