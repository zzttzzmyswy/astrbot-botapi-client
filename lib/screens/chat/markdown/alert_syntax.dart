// lib/screens/chat/markdown/alert_syntax.dart
//
// GitHub Alert 块（`> [!NOTE]` 等）的修正版语法。
//
// markdown 包自带的 AlertBlockSyntax 产出 `<div>`，而 flutter_markdown 的
// 块标签白名单里没有 `div`，会在 `_addParentInlineIfNeeded` 里对 null 断言崩掉
// 整个气泡。这里复用它的解析逻辑，只把根元素换成白名单内的 `section`。
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
    return md.Element('section', node.children)
      ..attributes.addAll(node.attributes)
      ..generatedId = node.generatedId
      ..footnoteLabel = node.footnoteLabel;
  }
}

/// 供 `md.Document(blockSyntaxes:)` 使用的 alert 语法。
List<md.BlockSyntax> get kAlertBlockSyntaxes => const [SafeAlertBlockSyntax()];
