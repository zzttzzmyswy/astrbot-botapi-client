// lib/screens/chat/markdown/markdown_view.dart
//
// 聊天消息的 Markdown 渲染入口。终态气泡与流式气泡共用这一份实现。
//
// 相对 GFM 的增量：
//   - LaTeX 数学公式（见 latex_syntax.dart / math_builder.dart）
//   - alert 块（`> [!NOTE]`）、脚注、标题锚点（gitHubWeb 扩展集）
//
// 缓存说明：这里**同步**构建 widget tree。早先的实现走 `Future.microtask` 异步
// 补建，命中缓存时又直接 return 而不 setState，导致命中旧 key 时界面停留在
// 上一次的内容上（陈旧渲染）。同步构建消除该路径，也顺带去掉了"首帧纯文本"
// 的闪烁。
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart' as md;
import 'package:markdown/markdown.dart' as mdp;
import 'package:url_launcher/url_launcher.dart';

import '../../../util/lru_cache.dart';
import '../../../design/tokens.dart';
import 'alert_syntax.dart';
import 'code_block.dart';
import 'latex_syntax.dart';
import 'math_builder.dart';

/// 消息 Markdown 渲染缓存（按 主题 + 前景色 + 文本 分键）。
final LruCache<String, Widget> _mdCache = LruCache(maxSize: 32);

/// 共享 markdown 样式表。[mine] 为我方（主色渐变）气泡：代码底、链接、引用线
/// 都改用前景色的半透明变体，否则浅色代码底上的白字会不可读。
md.MarkdownStyleSheet mdStyleSheet(Color fg, bool isDark, {bool mine = false}) {
  final c = AppColors.forDark(isDark);
  final inlineCodeBg =
      mine ? Colors.white.withValues(alpha: 0.18) : c.surfaceMuted;
  final link = mine ? fg : c.link;
  final accent = mine ? fg.withValues(alpha: 0.6) : c.primary;
  final body = TextStyle(color: fg, fontSize: 15.5, height: 1.55);
  return md.MarkdownStyleSheet(
    p: body,
    pPadding: EdgeInsets.zero,
    blockSpacing: 10,
    h1: TextStyle(
        color: fg, fontSize: 21, height: 1.35, fontWeight: FontWeight.w700),
    h2: TextStyle(
        color: fg, fontSize: 19, height: 1.35, fontWeight: FontWeight.w700),
    h3: TextStyle(
        color: fg, fontSize: 17, height: 1.4, fontWeight: FontWeight.w700),
    h4: TextStyle(
        color: fg, fontSize: 16, height: 1.4, fontWeight: FontWeight.w600),
    h5: TextStyle(
        color: fg, fontSize: 15.5, height: 1.4, fontWeight: FontWeight.w600),
    h6: TextStyle(
        color: fg.withValues(alpha: 0.75),
        fontSize: 15,
        height: 1.4,
        fontWeight: FontWeight.w600),
    a: TextStyle(
        color: link,
        fontWeight: FontWeight.w500,
        decoration: TextDecoration.underline,
        decorationColor: link.withValues(alpha: 0.5)),
    code: TextStyle(
        color: fg,
        fontSize: 13.5,
        fontFamily: 'monospace',
        backgroundColor: inlineCodeBg),
    // 代码块由 CodeBlockBuilder 自绘（圆角底 + 语言标签 + 复制），这里置空，
    // 避免 flutter_markdown 再套一层装饰。
    codeblockDecoration: const BoxDecoration(),
    codeblockPadding: EdgeInsets.zero,
    blockquoteDecoration: BoxDecoration(
      color: mine
          ? Colors.white.withValues(alpha: 0.10)
          : c.primary.withValues(alpha: isDark ? 0.10 : 0.06),
      border: Border(left: BorderSide(color: accent, width: 3)),
    ),
    blockquotePadding: const EdgeInsets.fromLTRB(12, 8, 10, 8),
    blockquote: body.copyWith(color: fg.withValues(alpha: 0.9)),
    tableBorder: TableBorder.all(
        color: mine ? fg.withValues(alpha: 0.25) : c.border, width: 0.8),
    tableHead:
        TextStyle(color: fg, fontWeight: FontWeight.w600, fontSize: 14),
    tableHeadAlign: TextAlign.left,
    tableBody: TextStyle(color: fg, fontSize: 14, height: 1.4),
    tableCellsDecoration: BoxDecoration(
        color: mine ? Colors.white.withValues(alpha: 0.06) : c.codeBg),
    tableCellsPadding:
        const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    horizontalRuleDecoration: BoxDecoration(
        border: Border(
            top: BorderSide(
                color: mine ? fg.withValues(alpha: 0.3) : c.border,
                width: 1))),
    strong: TextStyle(color: fg, fontWeight: FontWeight.w700),
    em: TextStyle(color: fg, fontStyle: FontStyle.italic),
    del: TextStyle(color: fg, decoration: TextDecoration.lineThrough),
    listBullet: TextStyle(color: accent, fontSize: 15.5, height: 1.55),
    listIndent: 20,
    checkbox: TextStyle(color: accent, fontSize: 17),
  );
}

/// 链接点击：仅放行 http/https，交给系统默认浏览器打开。
void launchMarkdownUrl(String text, String? href, String title) {
  final url = href ?? text;
  if (url.isEmpty) return;
  final uri = Uri.tryParse(url);
  if (uri == null) return;
  if (uri.scheme != 'http' && uri.scheme != 'https') return;
  launchUrl(uri, mode: LaunchMode.externalApplication);
}

/// 把消息文本渲染成可选中、带公式支持的 Markdown widget。
Widget buildMarkdown(String text, Color fg, bool isDark, {bool mine = false}) {
  if (text.isEmpty) return const SizedBox.shrink();
  final key = '${isDark ? 'd' : 'l'}${mine ? 'm' : 'o'}_${fg.toARGB32()}_$text';
  final cached = _mdCache[key];
  if (cached != null) return cached;

  final built = _hasMarkdown(text)
      ? SelectionArea(child: _markdownBody(text, fg, isDark, mine))
      : SelectableText(text,
          style: TextStyle(color: fg, fontSize: 15.5, height: 1.55));

  _mdCache[key] = built;
  return built;
}

md.MarkdownBody _markdownBody(String text, Color fg, bool isDark, bool mine) {
  return md.MarkdownBody(
    data: text,
    selectable: false,
    styleSheet: mdStyleSheet(fg, isDark, mine: mine),
    onTapLink: launchMarkdownUrl,
    extensionSet: mdp.ExtensionSet.gitHubWeb,
    inlineSyntaxes: kLatexInlineSyntaxes,
    blockSyntaxes: [...kAlertBlockSyntaxes, ...kLatexBlockSyntaxes],
    builders: {
      ...latexBuilders(fg: fg, isDark: isDark),
      'pre': CodeBlockBuilder(fg: fg, isDark: isDark, mine: mine),
    },
  );
}

/// 是否值得走 Markdown 解析。纯文本直接用 SelectableText，省一次解析。
///
/// 字符类覆盖 markdown 语法触发字符：`* _ ` ~ # | > [ < > $ \`。
final _mdTrigger = RegExp(r'[*_`~#|>\[\]$\\]');

bool _hasMarkdown(String t) => _mdTrigger.hasMatch(t);
