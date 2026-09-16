// lib/screens/chat/markdown/latex_syntax.dart
//
// LaTeX 数学定界符的 Markdown 语法扩展。
//
// 支持的定界符：
//   - 行内：$...$  与  \(...\)
//   - 独立块：$$...$$（含跨行）与  \[...\]
//
// 产出元素 tag 分别为 `latex-inline` / `latex-block`，由 LatexInlineBuilder /
// LatexBlockBuilder 渲染成公式 Widget。本文件只做识别与 AST 产出，不依赖 Flutter。
import 'package:markdown/markdown.dart' as md;

/// 行内公式 tag。
const kLatexInlineTag = 'latex-inline';

/// 独立公式块 tag。
const kLatexBlockTag = 'latex-block';

/// `$` 定界符内的内容：首尾不得为空白，故 `价格 $5 和 $6` 这类金额不会被误判。
const _mathBody = r'[^\s$][^$\n]*[^\s$]|[^\s$]';

/// 拼出行内公式正则。`$$..$$` 的分支必须排在 `$..$` 之前。
/// 用占位符替换而非直接拼接，避免为 `$` 和 `(` 反复转义。
String _inlinePattern() => r'\$\$(@)\$\$|\$(@)\$|\\\((@)\\\)'
    .replaceAll('@', _mathBody);

/// `$$...$$` / `\[...\]` 整行（可含首尾空白）。
final _blockFence = RegExp(
  r'^\s*(?:\$\$(.+?)\$\$|\\\[(.+?)\\\])\s*$',
  multiLine: true,
);

/// 纯定界符行：`$$` 或 `\[`，公式内容从后续行收集到收尾定界符为止。
final _openFence = RegExp(r'^\s*(?:\$\$|\\\[)\s*$', multiLine: true);

/// 跨行块的收尾定界符。
final _closeFence = RegExp(r'^\s*(?:\$\$|\\\])\s*$', multiLine: true);

/// `canParse` 用的块起点：整行闭合的公式，或独占一行的开定界符。
/// 必须覆盖后者，否则跨行块会被 `ParagraphSyntax` 先行吞掉。
final _blockStart = RegExp(
  r'^\s*(?:\$\$.*\$\$|\\\[.*\\\]|\$\$|\\\[)\s*$',
  multiLine: true,
);

/// 判断 [index] 之前是否存在未闭合的反引号（行内代码）。
/// 命中即认为当前位置处于代码段内，公式语法让位。
bool _insideCodeSpan(String source, int index) {
  var ticks = 0;
  for (var i = 0; i < index; i++) {
    if (source.codeUnitAt(i) == 0x60) ticks++;
  }
  return ticks.isOdd;
}

/// 把公式文本包进 `p` 元素。
///
/// flutter_markdown 的块/行内判定依赖它自己的 `_kBlockTags` 白名单，顶层未知
/// tag 会在构建时抛 `_TypeError`。包一层 `p` 后，`p` 负责块级归属，内层
/// `latex-block` 由 builder 渲染成一个独立 Widget，且不产生多余文本。
md.Element _blockElement(String latex) =>
    md.Element('p', [md.Element.text(kLatexBlockTag, latex)]);

/// 行内公式语法：`$...$` 与 `\(...\)`。
class LatexInlineSyntax extends md.InlineSyntax {
  LatexInlineSyntax() : super(_inlinePattern());

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    if (_insideCodeSpan(parser.source, parser.pos)) return false;
    final latex = match[1] ?? match[2] ?? match[3] ?? '';
    if (latex.trim().isEmpty) return false;
    parser.addNode(md.Element.text(kLatexInlineTag, latex));
    return true;
  }
}

/// 独立公式块语法：整行 `$$...$$`、`\[...\]`，以及定界符独占一行的跨行块。
class LatexBlockSyntax extends md.BlockSyntax {
  const LatexBlockSyntax();

  /// 同时覆盖"整行闭合"与"定界符独占一行、内容延伸到收尾定界符"两种起点。
  @override
  RegExp get pattern => _blockStart;

  @override
  md.Node? parse(md.BlockParser parser) {
    final line = parser.current.content;

    final inline = _blockFence.firstMatch(line);
    if (inline != null) {
      final latex = (inline[1] ?? inline[2] ?? '').trim();
      parser.advance();
      if (latex.isEmpty) return null;
      return _blockElement(latex);
    }

    if (!_openFence.hasMatch(line)) return null;

    // 定界符独占一行：持续收集直到收尾定界符或文档结束。
    final collected = <String>[];
    parser.advance();
    var closed = false;
    while (!parser.isDone) {
      final cur = parser.current.content;
      parser.advance();
      if (_closeFence.hasMatch(cur)) {
        closed = true;
        break;
      }
      collected.add(cur);
    }
    if (!closed) return null;

    final latex = collected.join('\n').trim();
    if (latex.isEmpty) return null;
    return _blockElement(latex);
  }
}

/// 供 `md.Document(inlineSyntaxes:)` 使用的语法列表。
List<md.InlineSyntax> get kLatexInlineSyntaxes => [LatexInlineSyntax()];

/// 供 `md.Document(blockSyntaxes:)` 使用的语法列表。
List<md.BlockSyntax> get kLatexBlockSyntaxes => const [LatexBlockSyntax()];
