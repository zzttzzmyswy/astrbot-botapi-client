// lib/screens/chat/markdown/alert_syntax.dart
//
// GitHub Alert 块（`> [!NOTE]` 等）的修正版语法。
//
// markdown 包自带的 AlertBlockSyntax 产出 `<div>`，而 flutter_markdown 的
// 块标签白名单里没有 `div`，会在 `_addParentInlineIfNeeded` 里对 null 断言崩掉
// 整个气泡。这里复用它的解析逻辑（含 `[!TYPE]` 标题的映射与子块解析），只把根
// 元素换成块白名单内的 `blockquote`。
//
// 为什么是 `blockquote` 而不是 `section`：两者都在白名单内，但 flutter_markdown
// 的块级元素一旦注册 builder，builder 的返回值会**整体替换**已构建好的子节点
// （builder 拿不到 children），`section` 又没有自带样式，真机上渲染出来就是一段
// 没有边框、标题像正文的平铺文字。`blockquote` 自带左侧竖线样式，能让 alert 在
// 视觉上与其后的正文区分开。
//
// 依赖 `package:markdown/src/...` 属于包的内部路径：`AlertBlockSyntax` 与
// `alertPattern` 都没有从 markdown.dart 导出，要复用它的解析逻辑只能走内部导入。
// 风险由 test/markdown_view_test.dart 的 alert 用例兜底。
// ignore_for_file: implementation_imports
import 'package:markdown/markdown.dart' as md;
import 'package:markdown/src/block_syntaxes/alert_block_syntax.dart';
import 'package:markdown/src/patterns.dart';

class SafeAlertBlockSyntax extends AlertBlockSyntax {
  const SafeAlertBlockSyntax();

  @override
  RegExp get pattern => alertPattern;

  @override
  bool canParse(md.BlockParser parser) =>
      alertPattern.hasMatch(parser.current.content);

  @override
  md.Node parse(md.BlockParser parser) {
    final node = super.parse(parser);
    if (node is! md.Element) return node;
    return md.Element('blockquote', node.children);
  }
}

/// 供 `md.Document(blockSyntaxes:)` 使用的 alert 语法。
List<md.BlockSyntax> get kAlertBlockSyntaxes => const [SafeAlertBlockSyntax()];
