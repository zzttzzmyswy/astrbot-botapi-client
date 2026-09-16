# AstrBot App 完整 Markdown 与数学公式渲染 — 设计

日期：2026-09-16
问题：MYS-1119

## 背景

App 的消息气泡当前由 `lib/screens/chat/bubbles/text_bubble.dart` 渲染，走
`flutter_markdown` 0.7.7 的 `MarkdownBody`，解析器扩展集使用
`ExtensionSet.gitHubFlavored`。流式气泡
（`lib/screens/chat/bubbles/streaming_bubble.dart`）另起一份 `MarkdownBody`，
样式表复用但扩展集、链接回调各写一遍。

现状盘点（对照 GFM 完整能力）：

| 能力 | 现状 |
| --- | --- |
| 标题 / 强调 / 删除线 / 围栏代码 / 表格 / 任务列表 / 链接 / 图片 / 自动链接 | 已有（gitHubFlavored） |
| Alert 块（`> [!NOTE]` 等） | 缺（gitHubFlavored 不含 `AlertBlockSyntax`） |
| 脚注、标题锚点 | 缺（`gitHubWeb` 才含） |
| LaTeX 数学公式（`$…$` `$$…$$` `\(…\)` `\[…\]`） | 完全没有，原样显示成文本 |

模型（LLM）输出的数学公式是高频场景，这是本次要补的核心缺口。

## 目标

1. 数学公式渲染：行内与独立公式块，四种定界符都能识别，解析失败不崩、降级显示原文。
2. Markdown 能力补全到 GFM 完整集（含 alert 块、脚注）。
3. 流式气泡与终态气泡渲染行为**完全一致**——同一份代码路径，杜绝两处漂移。
4. 顺带修掉渲染缓存的一个真实 bug（见下）。

非目标（YAGNI）：代码高亮（`highlight`/`flutter_highlight` 会显著增大体积且与
现有单色代码块样式不一致）、HTML 富文本渲染、Mermaid/图表、公式的交互式缩放。

## 关键决策

### 决策 1：数学渲染选 `flutter_math_fork`

纯 Dart + Flutter 的 TeX 渲染，不依赖 WebView，离线可用、无网络往返，支持行内
（`MathStyle.text`）与独立（`MathStyle.display`）两种排版模式。

对比过的方案：

- `flutter_tex`：内部是 WebView + KaTeX，首次渲染慢、需联网加载资源，对聊天流
  式气泡不可接受。
- `katex_flutter`：SDK 约束 `<3.0.0`，与本项目 `>=3.2.0` 不兼容。
- `gpt_markdown` / `markdown_widget`：自带整套渲染器，会把现有 `flutter_markdown`
  整条渲染路径换掉，改动面远大于需求；且 `gpt_markdown` 要求 Flutter >= 3.32。

代价：引入传递依赖 `flutter_svg` / `vector_graphics` / `provider` / `tuple`，
APK 体积增加。这是纯 Dart 渲染的必然成本，可接受。

### 决策 2：用 `ExtensionSet` + `MarkdownElementBuilder` 扩展，不换渲染器

`MarkdownBody` 已暴露 `extensionSet`（透传给 `md.Document`）、`inlineSyntaxes` /
`blockSyntaxes` 与 `builders`（tag → `MarkdownElementBuilder`）。自定义语法产出
已知 tag，builder 把 tag 渲染成 `Math` Widget。改动集中在"加两个语法类 + 一个
builder + 一个扩展集常量"，不动既有渲染骨架。

实现时踩到两个 `flutter_markdown` 的硬约束，必须记下来：

1. **顶层自定义块 tag 会崩**。flutter_markdown 的块/行内判定依赖它自己的私有
   白名单 `_kBlockTags`，`latex-block` 不在其中，顶层出现时
   `_addParentInlineIfNeeded` 会对 null 断言抛 `_TypeError`。解法：块公式包一层
   `p`（`Element('p', [Element.text('latex-block', tex)])`），由 `p` 承担块级
   归属，内层 tag 的 builder 返回的 Widget 会被当成该块的唯一内容。
2. **行内 builder 必须返回 `Text.rich`，不能直接返回 `WidgetSpan`**。
   `_InlineElement.children` 是 `List<Widget>`，而 `_getInlineSpanFromText` 只认
   `Text` / `Text.rich` / `RichText`：直接把 `WidgetSpan` 当 Widget 返回会在
   `Text.textSpan` 的类型转换处抛错。包成 `Text.rich(TextSpan(children:[...]))`
   后，WidgetSpan 才被正确并入整段文本的排版。

### 决策 3：数学语法类实现

两个 `InlineSyntax` 覆盖四种定界符：

- `LatexInlineSyntax`：匹配 `$…$` 与 `\(…\)`
- `LatexBlockSyntax`：匹配整行的 `$$…$$` 与 `\[…\]`（含跨行）

两者都产出 `md.Element.text(tag, latex)`，tag 分别为 `latex-inline` / `latex-block`。

转义与边界规则（必须有测试锁定）：

- `\$` 不触发；`$` 前的反斜杠计数为奇数即视为转义。
- `$5 和 $6` 这类金额不误判：行内定界符内首尾不允许是空白，且内容非空。
- 未闭合的 `$` 不匹配（流式输出中公式打到一半时保持纯文本，闭合后自动成公式）。
- 反引号代码段内的 `$` 不参与匹配。围栏代码块由 `FencedCodeBlockSyntax` 整体
  消费，天然安全；**行内代码**（`` `$x$` ``）不行——自定义 InlineSyntax 排在
  `CodeSyntax` 之前，且 `matchAsPrefix` 从反引号处必然失败。因此在 `onMatch`
  里做一次代码段护栏：统计 `parser.source` 中 match 起点之前的反引号个数，
  奇数即判定处于未闭合代码段内，语法让位。测试覆盖 `` `$x$` `` 与围栏两种。

### 决策 4：单一渲染入口，消重

`text_bubble.dart` 输出一个 `buildMarkdown(text, fg, isDark)`，终态气泡与流式气泡
都调它。`mdStyleSheet`、`launchMarkdownUrl`、扩展集、builders 全部收敛到这一处，
`streaming_bubble.dart` 只保留气泡装饰。

### 决策 5：修缓存 key bug 与首帧降级

现有 `_MarkdownContent` 用 `LruCache<String, Widget>`，key 是
`'${isDark ? 'd' : 'l'}_${text}'`。两个问题：

1. **未命中时首帧渲染 `Text` 纯文本**，靠 `Future.microtask` + `setState` 二次
   渲染成 markdown。流式场景下每次文本变化都可能闪一帧纯文本。
2. **命中时 `_build()` 直接 return**，但 `setState` 从未被调用——如果此时
   `_built` 还是旧值，就会继续显示上一次的内容。实际路径里 `didUpdateWidget`
   命中旧缓存后不 `setState`，widget 停留在旧 tree 上，直到某次未命中才刷新。
   这是真实的陈旧渲染 bug。

修法：**同步构建**。`ms.Document.parseLines` + `MarkdownBody` 的构造本身足够快
（消息量级文本 < 数毫秒），无需异步。命中缓存直接用，未命中同步构建并写入缓存，
删除 microtask 与首帧 `Text` 降级分支。

缓存容量维持 32 条不变。

## 结构

新增 `lib/screens/chat/markdown/` 目录：

```
markdown/
  latex_syntax.dart     # LatexInlineSyntax / LatexBlockSyntax
  math_builder.dart     # LatexInlineBuilder / LatexBlockBuilder -> Math.tex(...)
  alert_syntax.dart     # SafeAlertBlockSyntax（修 div 崩溃）
  markdown_view.dart    # buildMarkdown / mdStyleSheet / launchMarkdownUrl / 缓存
```

- `latex_syntax.dart`：纯解析逻辑，无 Flutter 依赖（只依赖 `markdown` 包），
  可脱离 widget 单测。
- `math_builder.dart`：负责把 LaTeX 字符串变成 `Math` Widget，含解析失败降级。
- `markdown_view.dart`：对外唯一入口。

`text_bubble.dart` 保留 `mdText`（兼容既有调用点）与 `TextBodyError`，实现改为
委托 `buildMarkdown` 并 re-export 共享符号。`streaming_bubble.dart` 改为直接调
`buildMarkdown`。

### alert 块：修掉一个现有崩溃

`gitHubFlavored` 不含 `AlertBlockSyntax`，而 `gitHubWeb` 含。但 markdown 包自带的
`AlertBlockSyntax` 产出 `<div>`，`div` 同样不在 flutter_markdown 的块标签白名单
里，实测会崩在 `_addParentInlineIfNeeded`（`Null check operator used on a null
value`）——模型输出 `> [!NOTE]` 时整个气泡渲染失败。

`SafeAlertBlockSyntax` 继承它、复用全部解析逻辑，只把根元素重建成 `section`
（白名单内）。代价是必须 `import 'package:markdown/src/...'` 内部路径，已用
`// ignore_for_file: implementation_imports` 显式标注并有测试兜底。

## 数据流

```
文本 → MarkdownBody(data, extensionSet: gitHubWeb, inlineSyntaxes, blockSyntaxes,
                    builders)
     → md.Document.parseLines
     → 命中 LatexInlineSyntax/LatexBlockSyntax 时产出 <latex-inline>/<latex-block>
     → LatexInlineBuilder / LatexBlockBuilder 把 latex 文本交给
       Math.tex(..., mathStyle: text|display)
     → Math 内部 TexParser 解析成 SyntaxTree 并绘制（用随包字体，无网络）
```

解析失败（LaTeX 语法错误）时 `Math.tex` 的 `onErrorFallback` 生效，降级显示
原文加一个细边框，不抛异常、不空白。

## 错误处理

| 情况 | 行为 |
| --- | --- |
| LaTeX 语法错误 | 显示原文，外框淡红描边，不崩溃 |
| 公式未闭合（流式中） | 按纯文本显示，闭合后下一次渲染成公式 |
| 数学语法解析抛异常 | `LatexElementBuilder` 内 try/catch 兜底为纯文本 |
| 空表达式（`$$$$`） | 不产出元素，原样文本 |

## 测试策略

新增 `test/markdown_latex_syntax_test.dart`（纯解析，16 例，无 widget）：

1. `$E=mc^2$` → 产出 `latex-inline` 元素，内容 `E=mc^2`
2. `$$a^2+b^2=c^2$$` → 产出 `latex-block`
3. `\(x\)` / `\[x\]` → 同上两种
4. `\$100` 不触发；`价格 $5 和 $6` 不触发
5. 未闭合 `$x` 不触发，文本原样保留
6. 反引号内 `` `$x$` `` 不触发
7. 公式与普通文本混排时其余文本元素完整

新增 `test/markdown_view_test.dart`（widget，17 例）：

8. `buildMarkdown(r'$x^2$', ...)` 能构建成功，widget tree 中存在 `Math`
9. 独立公式块 `$$\int_0^1 x dx$$` 渲染成功不抛异常
10. 非法公式 `$\frac{1}{$` 渲染成功且降级为原文
11. 同一文本重复构建命中缓存（返回同一 Widget 实例）
12. 明暗两种主题下 key 不串（不同实例），且文本变化后不吃旧缓存
13. `StreamingBubble` 与气泡正文渲染同一文本时行为一致
14. 表格 / 任务列表 / alert 块各一例（覆盖完整 Markdown 能力，其中 alert 用例
    即上面那个 `div` 崩溃的回归测试）

这些测试跑在 `flutter test` 下，无需真机。

## 验收

- `flutter analyze`：新增文件零告警（全仓 info 数由基线 63 降至 50，剩余均为既有）
- `flutter test` 全绿：基线 194 项 → 227 项（+33）
- 版本号 1.9.0+41 → 1.10.0+42
- 产出 PR
