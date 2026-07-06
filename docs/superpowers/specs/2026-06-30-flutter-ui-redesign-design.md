# Flutter UI 重构 + 桌面支持移除 设计文档

**日期**: 2026-06-30  
**目标**: 移除 Linux/Windows 桌面支持, 仅保留 Android;基于 Flutter 自定义 UI 重构聊天界面, 全面提升精致度和动画流畅度.

---

## 一、动机

1. 桌面用户为零, 维护 Linux/Windows 构建、CI、平台抽象无价值.
2. 当前聊天 UI 依赖 `flutter_chat_ui` 通用包, 气泡样式、动画、微交互受限于该包的 Theme 接口——只能改颜色/字体/圆角, 改不了气泡形状、入场动画、按压反馈.
3. Flutter 的 `CustomPainter` + Impeller + `flutter_animate` 组合可以实现与 Telegram/微信同级的精致度, 但需要扔掉通用包, 自己画.

---

## 二、方案概述

- **保留** (~65% 代码): 网络层 (dio/WebSocket/SSE)、缓存 (sqflite)、状态管理 (Riverpod)、音频、工具函数
- **删除** (~15% 代码): 桌面平台目录、桌面 CI、平台抽象桌面实现
- **重写** (~20% 代码): 聊天 UI 子系统 (气泡/列表/动画/输入)

---

## 三、删除：桌面支持

### 3.1 目录删除

| 路径 | 说明 |
|---|---|
| `linux/` | Linux 桌面嵌入层 |
| `windows/` | Windows 桌面嵌入层 |
| `.github/workflows/build-windows.yml` | Windows CI |
| `scripts/build-appimage.sh` | AppImage 打包脚本 |
| `lib/services/platform/impl/keep_alive_desktop.dart` | 桌面保活 (no-op) |
| `lib/services/platform/impl/permission_desktop.dart` | 桌面权限 (永远 granted) |
| `lib/services/platform/impl/update_desktop.dart` | 桌面更新 (打开浏览器) |

### 3.2 代码简化

**`lib/main.dart`**
- 删除 `import 'dart:io' show Platform;`
- 删除 `import 'package:sqflite_common_ffi/sqflite_ffi.dart';`
- 删除 `sqfliteFfiInit()` / `databaseFactory = databaseFactoryFfi` 分支
- `WithForegroundTask` 去条件判断, 始终包裹 `app` (Android-only 必然)

**`lib/providers/platform_providers.dart`**
- 删除桌面实现类 import
- 三个 Provider 直接返回 `MobileKeepAlive()` / `MobilePermission()` / `MobileUpdateApplier()`, 去 `Platform.isAndroid` 判断

**`pubspec.yaml`**
- 移除 `flutter_chat_ui`, `flutter_chat_core`, `sqflite_common_ffi`
- 新增 `flutter_animate: ^4.5.0`

---

## 四、新增：设计令牌系统

单文件 `lib/design/tokens.dart`, 全应用统一的视觉基础.

### 4.1 颜色

```dart
// Semantic tokens, 暗/亮完整定义
class AppColors {
  final Color surface, surfaceCard, primary, onPrimary,
      textPrimary, textSecondary, bubbleMine, bubbleOther,
      error, success, border;
  // light 与 dark 各一套实例
  static const light = AppColors(...);
  static const dark = AppColors(...);
}
```

### 4.2 间距 (4px 网格)

| Token | px |
|---|---|
| xs | 4 |
| sm | 8 |
| md | 12 |
| lg | 16 |
| xl | 20 |
| 2xl | 24 |
| 3xl | 32 |

### 4.3 圆角

| Token | px |
|---|---|
| sm | 8 |
| md | 12 |
| lg | 16 |
| xl | 20 |
| full | 999 |

### 4.4 阴影

- `cardShadow`: 0,2 12px blur, black 8% opacity
- `bubbleShadow`: 0,1 4px blur, black 4% opacity
- `fabShadow`: 0,4 12px blur, black 15% opacity

### 4.5 字体

- `body`: 16px, height 1.35
- `caption`: 12px, height 1.2
- `captionMono`: 11px monospace, height 1.3
- `title`: 15px, weight 600

### 4.6 DesignTokens Provider

```dart
final designTokensProvider = Provider<AppColors>((ref) {
  final brightness = ref.watch(platformBrightnessProvider);
  return brightness == Brightness.dark ? AppColors.dark : AppColors.light;
});
```

---

## 五、聊天 UI 拆分

原 `lib/screens/chat_screen.dart` (~1724 行) 拆为:

```
lib/screens/chat/
├── chat_screen.dart        # Scaffold + 滚动编排 + keyboard/状态监听 (~250 行)
├── chat_list.dart           # CustomScrollView slivers + 懒加载 + 历史加载 (~120 行)
├── app_bar.dart             # 状态栏 (连接/打字动画/设置) (~80 行)
├── input_bar.dart           # 输入栏 + 附件切换 + 语音按钮 (~100 行)
├── voice_overlay.dart       # 录音覆盖层 (~80 行)
├── slash_suggestion.dart    # 斜杠命令候选 (~50 行)
├── scroll_thumb.dart        # 滚动指示器 + 日期悬浮 (~100 行)
├── date_divider.dart        # 日期分隔线 (~30 行)
├── bubbles/
│   ├── text_bubble.dart     # 文字 + markdown 渲染 (~100 行)
│   ├── image_bubble.dart    # 图片 + 全屏查看 (~120 行)
│   ├── voice_bubble.dart    # 语音播放条 (~110 行)
│   ├── file_bubble.dart     # 文件卡片 (~100 行)
│   ├── streaming_bubble.dart # 流式 markdown + 光标 (~60 行)
│   ├── thinking_block.dart  # 思考折叠块 (~50 行)
│   └── tool_status.dart     # 工具调用状态 (~30 行)
```

### 5.1 chat_screen.dart

职责精简为:
- `Scaffold` 结构 (AppBar + body + InputBar)
- 键盘弹起检测 → 自动滚底
- `StreamingActive` 翻转检测 → 列表重建
- 连接状态/账户名/错误监听 `ref.listen(chatProvider, ...)`
- 附件面板 `AnimatedSize` + pin-bottom-on-resize
- 滚动去抖 + 历史加载触发

### 5.2 chat_list.dart

自身管理:
- `CustomScrollView` + `SliverList.builder` (保留)
- `ScrollController` + 置顶检测 → 触发 `loadMoreHistory`
- FAB "回到底部" 按钮
- 消息入场动画: `flutter_animate` 的 `Animate().fadeIn().slideY(entity)`
- 日期分隔、思考块作为内联项而非独立气泡

### 5.3 气泡基类

所有气泡共享:
- `RepaintBoundary` 包裹
- `maxWidth: bw * 0.85` 约束
- 颜色取 `designTokensProvider` (我发:紫色/对方:灰色)
- 圆角: 我 `(tl,tr,bl: lg, br: sm)`, 对方 `(tl,tr,br: lg, bl: sm)`
- 时间戳: 气泡右下 10px 灰色小字

---

## 六、动画体系

### 6.1 消息入场

每条新消息 (非历史加载) 尾部追加时:

```dart
bubble.animate()
  .fadeIn(duration: 300.ms, curve: Curves.easeOut)
  .slideY(begin: 0.12, end: 0, duration: 350.ms, curve: Curves.easeOutCubic)
```

### 6.2 按压反馈

所有交互元素 (发送按钮, 文件卡片, 语音气泡) 用 `GestureDetector` + `AnimatedScale`:

```dart
// onTapDown → scale 0.97, onTapUp/onTapCancel → scale 1.0
AnimatedScale(scale: _pressed ? 0.97 : 1.0, duration: 100.ms, child: ...)
```

### 6.3 发送按钮形态切换

输入栏文本空→非空时, 麦克风图标→发送按钮, 使用 `AnimatedSwitcher` + `ScaleTransition`:

```dart
AnimatedSwitcher(
  duration: 200.ms,
  switchInCurve: Curves.easeOutBack,
  child: hasText ? sendButton : micButton,
)
```

### 6.4 滚动物理

Android 上显式使用 `BouncingScrollPhysics` (替代 `ClampingScrollPhysics`), 高刷屏下弹性滚动手感:

```dart
physics: const BouncingScrollPhysics(),
```

### 6.5 Impeller 渲染

Flutter 3.38 默认启用. 在 `AndroidManifest.xml` 显式声明:

```xml
<meta-data android:name="io.flutter.embedding.android.EnableImpeller"
           android:value="true" />
```

---

## 七、测试计划

| 类别 | 内容 |
|---|---|
| 设计令牌 | `tokens_test.dart` — 暗/亮颜色完整性, 间距值一致性 |
| 文字气泡 | `text_bubble_test.dart` — 纯文本 + markdown 渲染, 暗/亮适配 |
| 图片气泡 | `image_bubble_test.dart` — localPath/下载中/上传中/失败四种状态 |
| 语音气泡 | `voice_bubble_test.dart` — 播放/暂停/加载/上传中 |
| 文件气泡 | `file_bubble_test.dart` — 上传进度/点击打开/失败重试 |
| 流式气泡 | `streaming_bubble_test.dart` — markdown 实时渲染, 光标闪烁 |
| 聊天列表 | `chat_list_test.dart` — 空列表/消息追加/历史加载/滚动行为 |
| 平台清理 | 现有测试全部通过, 无桌面 import 残留 |

---

## 八、版本规划

- **v1.4.0**: 移除桌面支持 + UI 架构拆分 (结构变更, 功能不变)
- **v1.4.1**: 设计令牌 + 气泡自绘 + 动画系统 (视觉升级)

两个版本分开发布, 降低风险: 1.4.0 纯清理, 回归范围小; 1.4.1 上视觉效果, 可单独回退.

---

## 九、风险与缓解

| 风险 | 缓解 |
|---|---|
| 自绘气泡功能回归 | v1.4.0 分拆结构时保留原 UI, v1.4.1 逐气泡替换 |
| 动画性能退化 | 每个气泡 `RepaintBoundary` + `flutter_animate` 只作用于增量 |
| Markdown 渲染一致性 | 复用现有 `MarkdownBody` + `_mdStyleSheet`, 不换渲染引擎 |
| 删除桌面后无法复活 | git history 保留所有桌面代码, tag v1.3.7 可随时 checkout |
