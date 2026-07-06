# Flutter UI 重构 + 桌面支持移除 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 移除 Linux/Windows 桌面支持，将聊天 UI 拆分为独立气泡组件，基于设计令牌系统 + flutter_animate 实现精致视觉效果。

**Architecture:** 两阶段交付。v1.4.0 纯删除+结构分拆（功能不变），v1.4.1 注入设计令牌和动画系统（视觉升级）。保留所有网络/缓存/状态管理代码不变。

**Tech Stack:** Flutter 3.38, Dart 3.2+, Riverpod, dio, sqflite, flutter_animate 4.5, MarkdownBody

**Spec:** `docs/superpowers/specs/2026-06-30-flutter-ui-redesign-design.md`

---

## Part A: v1.4.0 — 桌面移除 + UI 结构拆分

### Task A1: 删除桌面平台目录和脚本

- [ ] **Step 1: 删除**

```bash
rm -rf linux/ windows/ scripts/
rm -f .github/workflows/build-windows.yml
```

- [ ] **Step 2: 提交**

```bash
git add -A && git commit -m "chore: remove linux/windows desktop support"
```

### Task A2: 删除桌面平台抽象实现文件

- [ ] **Step 1: 删除**

```bash
rm lib/services/platform/impl/keep_alive_desktop.dart
rm lib/services/platform/impl/permission_desktop.dart
rm lib/services/platform/impl/update_desktop.dart
```

- [ ] **Step 2: 提交**

```bash
git add -A && git commit -m "chore: remove desktop platform abstraction impls"
```

### Task A3: 简化 platform_providers.dart

**File:** `lib/providers/platform_providers.dart`

- [ ] **Step 1: 去桌面分支**

删除 `import 'dart:io' show Platform;` 和三行 `desktop` import。三个 Provider 直接返回 `MobileKeepAlive()` / `MobilePermission()` / `MobileUpdateApplier()`。

- [ ] **Step 2: 验证编译**

```bash
cd /home/zzt/workspace/astrbot-app && flutter analyze lib/providers/platform_providers.dart
```

Expected: No issues found.

- [ ] **Step 3: 提交**

```bash
git add -A && git commit -m "refactor: simplify platform providers to mobile-only"
```

### Task A4: 简化 main.dart

**File:** `lib/main.dart`

- [ ] **Step 1: 去桌面分支**

移除 `import 'dart:io' show Platform;` 和 `import 'package:sqflite_common_ffi/sqflite_ffi.dart';`。删除 `if (Platform.isWindows || Platform.isLinux)` FFI 初始化块。`WithForegroundTask(child: app)` 无条件包裹（去 `Platform.isAndroid` 判断）。

- [ ] **Step 2: 验证编译**

```bash
flutter analyze lib/main.dart
```

Expected: No issues found.

- [ ] **Step 3: 提交**

```bash
git add -A && git commit -m "refactor: remove desktop FFI and platform branches from main"
```

### Task A5: 清理 pubspec.yaml

**File:** `pubspec.yaml`

- [ ] **Step 1: 编辑依赖**

删除 `flutter_chat_ui`、`flutter_chat_core`、`sqflite_common_ffi`。新增 `flutter_animate: ^4.5.0`。

- [ ] **Step 2: 重装验证**

```bash
flutter pub get && flutter analyze lib/
```

Expected: No issues found. Confirm no `flutter_chat_ui`/`flutter_chat_core`/`sqflite_common_ffi` import in `lib/` or `test/`.

- [ ] **Step 3: 提交**

```bash
git add pubspec.yaml pubspec.lock && git commit -m "chore: replace flutter_chat_ui with flutter_animate"
```

### Task A6: 创建聊天 UI 目录结构

- [ ] **Step 1: 创建目录**

```bash
mkdir -p lib/screens/chat/bubbles
```

### Task A7: 提取 ChatAppBar

**File:** `lib/screens/chat/app_bar.dart`

- [ ] **Step 1: 写入**

从 chat_screen.dart 提取 `_Bar` + `_TypingDots`，重命名为 `ChatAppBar`。接口: `connected, isDark, error, accountName, streaming, autoPlay, reconnecting, onToggleAutoPlay`。导入 `settings_screen.dart`。

- [ ] **Step 2: 验证**

```bash
flutter analyze lib/screens/chat/app_bar.dart
```

- [ ] **Step 3: 提交**

```bash
git add lib/screens/chat/app_bar.dart && git commit -m "refactor: extract ChatAppBar from chat_screen"
```

### Task A8: 提取 ChatInputBar + SlashSuggestionPanel

**Files:** `lib/screens/chat/input_bar.dart`, `lib/screens/chat/slash_suggestion.dart`

- [ ] **Step 1: 分离 SlashCommand + SlashSuggestionPanel**

写入 `lib/screens/chat/slash_suggestion.dart`：`SlashCommand` 类 + `SlashSuggestionPanel` widget。从 chat_screen.dart 提取 `_SlashSuggestion` 并重命名。

- [ ] **Step 2: 提取 ChatInputBar**

写入 `lib/screens/chat/input_bar.dart`：提取 `_InputBar` 重命名为 `ChatInputBar`。接口: `send, showAttachment, controller, focusNode, isDark, hasText, onVoiceStart, onVoiceMove, onVoiceEnd, slashMatches, onPickSlash`。import `slash_suggestion.dart`。

- [ ] **Step 3: 验证**

```bash
flutter analyze lib/screens/chat/input_bar.dart lib/screens/chat/slash_suggestion.dart
```

- [ ] **Step 4: 提交**

```bash
git add lib/screens/chat/input_bar.dart lib/screens/chat/slash_suggestion.dart && git commit -m "refactor: extract ChatInputBar and SlashSuggestionPanel"
```

### Task A9: 提取 DateDivider 和 ScrollThumbOverlay

**Files:** `lib/screens/chat/date_divider.dart`, `lib/screens/chat/scroll_thumb.dart`

- [ ] **Step 1: 提取 DateDivider**

从 chat_screen.dart 提取 `_DateDivider`，重命名为 `DateDivider(label, isDark)`。纯 StatelessWidget。

- [ ] **Step 2: 提取 ScrollThumbOverlay**

从 chat_screen.dart 提取 `_ScrollThumbOverlay`，重命名。接口: `fraction, isDark, dateLabel, showDate, onDrag, onDragEnd`。

- [ ] **Step 3: 验证**

```bash
flutter analyze lib/screens/chat/date_divider.dart lib/screens/chat/scroll_thumb.dart
```

- [ ] **Step 4: 提交**

```bash
git add lib/screens/chat/date_divider.dart lib/screens/chat/scroll_thumb.dart && git commit -m "refactor: extract DateDivider and ScrollThumbOverlay"
```

### Task A10: 提取 VoiceOverlay

**File:** `lib/screens/chat/voice_overlay.dart`

- [ ] **Step 1: 提取**

从 chat_screen.dart 提取 `_VoiceOverlay` + `_VoiceOverlayState`，重命名为 `VoiceOverlay`。接口: `amplitude, isCancel, isDark`。

- [ ] **Step 2: 验证**

```bash
flutter analyze lib/screens/chat/voice_overlay.dart
```

- [ ] **Step 3: 提交**

```bash
git add lib/screens/chat/voice_overlay.dart && git commit -m "refactor: extract VoiceOverlay"
```

### Task A11: 提取 bubbles/text_bubble.dart

**File:** `lib/screens/chat/bubbles/text_bubble.dart`

- [ ] **Step 1: 提取共享工具函数**

提取 `mdStyleSheet()`、`launchMarkdownUrl()`、`mdText()`、`_MarkdownContent` 到 text_bubble.dart。从 chat_screen.dart 的 `_Bubble._mdText`、`_MarkdownContent`、`_mdStyleSheet` 中提取。

`TextBodyError` 改为 `StatelessWidget`，接受 `onRetry` callback 而非直接依赖 `chatProvider`。

- [ ] **Step 2: 验证**

```bash
flutter analyze lib/screens/chat/bubbles/text_bubble.dart
```

- [ ] **Step 3: 提交**

```bash
git add lib/screens/chat/bubbles/text_bubble.dart && git commit -m "refactor: extract text bubble and markdown helpers"
```

### Task A12: 提取 image/voice/file 气泡

**Files:** `lib/screens/chat/bubbles/image_bubble.dart`, `lib/screens/chat/bubbles/voice_bubble.dart`, `lib/screens/chat/bubbles/file_bubble.dart`

- [ ] **Step 1: ImageBubble**

从 chat_screen.dart 提取 `_ImageBubble` + `_ImageBubbleState` + `_FullScreenImage` + `_UploadBadge`。`_UploadBadge` 作为私有 widget。重命名为 `ImageBubble`。接口: `m (LocalMessage), bw, isMe, isDark`。

- [ ] **Step 2: VoiceBubble**

从 chat_screen.dart 提取 `_VoiceBubble` + `_VoiceBubbleState`。重命名为 `VoiceBubble`。依赖 `audioPlaybackProvider` (保留 ConsumerStatefulWidget)。

- [ ] **Step 3: FileBubble**

从 chat_screen.dart 提取 `_FileBubble` + `_FileBubbleState` + `_mimeForName`。重命名为 `FileBubble`。

- [ ] **Step 4: 验证**

```bash
flutter analyze lib/screens/chat/bubbles/
```

- [ ] **Step 5: 提交**

```bash
git add lib/screens/chat/bubbles/ && git commit -m "refactor: extract image, voice, file bubbles"
```

### Task A13: 提取 streaming/thinking/tool_status 组件

**Files:** `lib/screens/chat/bubbles/streaming_bubble.dart`, `lib/screens/chat/bubbles/thinking_block.dart`, `lib/screens/chat/bubbles/tool_status.dart`

- [ ] **Step 1: StreamingBubble**

提取 `_Streaming` → `StreamingBubble(text, bw, isDark)`。纯 StatelessWidget，保持 MarkdownBody 渲染。

- [ ] **Step 2: ThinkingBlock**

提取 `_ThinkingBlock` + `_ThinkingBlockState` → `ThinkingBlock(text, isDark)`。保留折叠交互、`AnimatedRotation`。

- [ ] **Step 3: ToolStatus**

提取 `_ToolStatus` → `ToolStatus(text)`。纯 StatelessWidget。

- [ ] **Step 4: 验证**

```bash
flutter analyze lib/screens/chat/bubbles/
```

- [ ] **Step 5: 提交**

```bash
git add lib/screens/chat/bubbles/ && git commit -m "refactor: extract streaming, thinking, tool_status bubbles"
```

### Task A14: 重写 chat_screen.dart 使用提取的组件

**File:** `lib/screens/chat_screen.dart`

- [ ] **Step 1: 重写**

将 chat_screen.dart 重写为使用所有新提取的组件。关键变化:
- import 所有 `chat/` 子组件
- `_state`、`_scrollCtrl`、`_inputCtrl`、`_focusNode` 等状态保留在 `_ChatScreenState`
- AppBar → `ChatAppBar(...)`
- InputBar → `ChatInputBar(...)`
- VoiceOverlay → `VoiceOverlay(...)`
- `_item()` 方法中: 用 `TextBodyError(onRetry: () => ref.read(chatProvider.notifier).retryTextSend(...))` 替代原实现
- 日期分隔 → `DateDivider(...)`
- 滚动指示器 → `ScrollThumbOverlay(...)`
- 气泡构建 → 使用 `bubbles/` 下的组件

- [ ] **Step 2: 编译验证**

```bash
flutter analyze lib/ && echo "OK"
```

Expected: No issues found.

- [ ] **Step 3: 运行现有测试**

```bash
flutter test
```

Expected: All existing tests pass (功能无变化, 仅结构重组).

- [ ] **Step 4: 提交**

```bash
git add -A && git commit -m "refactor: rewrite chat_screen to use extracted bubble components"
```

### Task A15: 版本号 1.4.0+30

- [ ] **Step 1: 更新 pubspec.yaml**

`version: 1.3.7+29` → `version: 1.4.0+30`

- [ ] **Step 2: 全量测试**

```bash
flutter test && flutter analyze lib/ test/
```

- [ ] **Step 3: 提交**

```bash
git add pubspec.yaml && git commit -m "chore: bump version to 1.4.0+30"
```

---

## Part B: v1.4.1 — 设计令牌 + 视觉升级

### Task B1: 创建设计令牌系统

**File:** `lib/design/tokens.dart`

- [ ] **Step 1: 写入**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
  final Color border;
  final Color divider;
  final Color dimmed;

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
    required this.border,
    required this.divider,
    required this.dimmed,
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
    border: Color(0xFFE5E5EA),
    divider: Color(0xFFE0E0E5),
    dimmed: Color(0xFF9E9E9E),
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
    border: Color(0xFF3A3A3C),
    divider: Color(0xFF3A3A3C),
    dimmed: Color(0xFF6D6D72),
  );
}

class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xl2 = 24;
  static const double xl3 = 32;
}

class AppRadius {
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double full = 999;
}

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

class AppText {
  static const body = TextStyle(fontSize: 16, height: 1.35);
  static const caption =
      TextStyle(fontSize: 12, height: 1.2);
  static const captionMono = TextStyle(
      fontSize: 11, height: 1.3, fontFamily: 'monospace');
  static const title =
      TextStyle(fontSize: 15, fontWeight: FontWeight.w600);
  static TextStyle time(TextStyle base) =>
      base.copyWith(fontSize: 10, height: 1.2);
}

final designTokensProvider = Provider<AppColors>((ref) {
  // We use the theme context brightness via a manual provider or
  // simply pass colors from each widget's build context.
  // For widgets that can't easily get context, fall back:
  return AppColors.light;
});
```

- [ ] **Step 2: 验证**

```bash
flutter analyze lib/design/tokens.dart
```

- [ ] **Step 3: 提交**

```bash
git add lib/design/ && git commit -m "feat: add design token system (colors, spacing, radii, shadows)"
```

### Task B2: 使用设计令牌重写 ChatAppBar

**File:** `lib/screens/chat/app_bar.dart`

- [ ] **Step 1: 替换硬编码颜色**

将所有硬编码颜色替换为 `isDark ? AppColors.dark.xxx : AppColors.light.xxx`。间距用 `AppSpacing` 常量。打字动画点颜色保持不变（accent 色）。

- [ ] **Step 2: 验证 + 提交**

```bash
flutter analyze lib/screens/chat/app_bar.dart && git add -A && git commit -m "refactor: apply design tokens to ChatAppBar"
```

### Task B3: 使用设计令牌 + 动画重写 bubbles

**Files:** 所有 `lib/screens/chat/bubbles/*.dart`

- [ ] **Step 1: TextBubble**

颜色、间距、圆角、阴影全部引用 tokens。`mdStyleSheet` 改用 token 颜色。发送失败态保持红色特殊处理。

- [ ] **Step 2: ImageBubble**

圆角 `AppRadius.md`，上传遮罩用 token 的 `primary.withValues(alpha: ...)`。

- [ ] **Step 3: VoiceBubble**

播放按钮颜色用 token primary。进度条颜色统一。

- [ ] **Step 4: FileBubble**

文件卡片用 token `border` + `surfaceCard`。

- [ ] **Step 5: StreamingBubble / ThinkingBlock / ToolStatus**

全部引用 tokens。

- [ ] **Step 6: 验证 + 提交**

```bash
flutter analyze lib/screens/chat/bubbles/ && git add -A && git commit -m "refactor: apply design tokens to all chat bubbles"
```

### Task B4: 添加动画系统

**Files:** `lib/screens/chat/chat_screen.dart` (或新文件 `lib/screens/chat/chat_list.dart`)

- [ ] **Step 1: 消息入场动画**

在 chat_screen 的消息构建中，非历史加载的新消息尾部追加时添加 `.animate().fadeIn(duration: 300.ms).slideY(begin: 0.12)`。使用 flag 区分历史加载 vs 新消息。

- [ ] **Step 2: 输入栏发送按钮 AnimatedSwitcher**

`ChatInputBar` 中麦克风↔发送按钮切换使用 `AnimatedSwitcher(duration: 200.ms, switchInCurve: Curves.easeOutBack)`。

- [ ] **Step 3: BouncingScrollPhysics**

`CustomScrollView` 的 `physics` 改为 `const BouncingScrollPhysics()`。

- [ ] **Step 4: AnimatedScale 按压反馈**

在 `ChatInputBar` 的发送按钮上加入 `AnimatedScale(scale: _pressed ? 0.97 : 1.0, duration: 100.ms)`。需要用 `StatefulWidget` 包装或使用 `_TapScale` helper。

- [ ] **Step 5: 验证 + 提交**

```bash
flutter analyze lib/screens/chat/ && git add -A && git commit -m "feat: add message entry animations and scroll physics"
```

### Task B5: Impeller 显式启用

**File:** `android/app/src/main/AndroidManifest.xml`

- [ ] **Step 1: 添加 meta-data**

在 `<activity>` 前添加:
```xml
<meta-data android:name="io.flutter.embedding.android.EnableImpeller"
           android:value="true" />
```

- [ ] **Step 2: 提交**

```bash
git add android/ && git commit -m "feat: enable Impeller rendering engine explicitly"
```

### Task B6: 版本号 1.4.1+31

- [ ] **Step 1: 更新**

`version: 1.4.0+30` → `version: 1.4.1+31`

- [ ] **Step 2: 全量测试**

```bash
flutter test && flutter analyze lib/ test/
```

- [ ] **Step 3: 提交**

```bash
git add pubspec.yaml && git commit -m "chore: bump version to 1.4.1+31"
```

---

## 自审清单

1. **Spec coverage**: 每个 spec 需求都有对应 Task — 桌面删除 (A1-A5), 聊天 UI 拆分 (A6-A14), 设计令牌 (B1), 动画 (B4), Impeller (B5), 测试在各任务中内联验证
2. **No placeholders**: 所有步骤有具体命令/路径，无 TBD/TODO
3. **Type consistency**: 组件接口名称在 A7-A13 定义，A14 使用一致
