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
import 'alert_syntax.dart';
import 'latex_syntax.dart';
import 'math_builder.dart';

/// 消息 Markdown 渲染缓存（按 主题 + 前景色 + 文本 分键）。
final LruCache<String, Widget> _mdCache = LruCache(maxSize: 32);

/// 共享 markdown 样式表。
md.MarkdownStyleSheet mdStyleSheet(Color fg, bool isDark) {
  return md.MarkdownStyleSheet(
    p: TextStyle(color: fg, fontSize: 16, height: 1.35),
    h1: TextStyle(color: fg, fontSize: 20, fontWeight: FontWeight.bold),
    h2: TextStyle(color: fg, fontSize: 18, fontWeight: FontWeight.bold),
    h3: TextStyle(color: fg, fontSize: 17, fontWeight: FontWeight.bold),
    a: const TextStyle(
        color: Color(0xFF4A8FE7),
        decoration: TextDecoration.underline,
        decorationColor: Color(0xFF4A8FE7)),
    code: TextStyle(
        color: fg,
        fontSize: 14,
        fontFamily: 'monospace',
        backgroundColor:
            isDark ? const Color(0xFF3A3A3C) : const Color(0xFFE8E8EC)),
    codeblockDecoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7),
        borderRadius: BorderRadius.circular(8)),
    blockquoteDecoration: BoxDecoration(
        border: Border(
            left: BorderSide(color: fg.withValues(alpha: 0.35), width: 3))),
    blockquotePadding: const EdgeInsets.only(left: 12),
    tableBorder:
        TableBorder.all(color: fg.withValues(alpha: 0.2), width: 0.5),
    tableHead:
        TextStyle(color: fg, fontWeight: FontWeight.bold, fontSize: 14),
    tableBody: TextStyle(color: fg, fontSize: 14),
    tableCellsPadding:
        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    horizontalRuleDecoration: BoxDecoration(
        border:
            Border(top: BorderSide(color: fg.withValues(alpha: 0.2)))),
    strong:
        TextStyle(color: fg, fontWeight: FontWeight.bold, fontSize: 16),
    em: TextStyle(
        color: fg, fontStyle: FontStyle.italic, fontSize: 16),
    listBullet: TextStyle(color: fg, fontSize: 16),
    listIndent: 16,
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
Widget buildMarkdown(String text, Color fg, bool isDark) {
  if (text.isEmpty) return const SizedBox.shrink();
  final key = '${isDark ? 'd' : 'l'}_${fg.toARGB32()}_$text';
  final cached = _mdCache[key];
  if (cached != null) return cached;

  final built = _hasMarkdown(text)
      ? SelectionArea(child: _markdownBody(text, fg, isDark))
      : SelectableText(text,
          style: TextStyle(color: fg, fontSize: 16, height: 1.35));

  _mdCache[key] = built;
  return built;
}

md.MarkdownBody _markdownBody(String text, Color fg, bool isDark) {
  return md.MarkdownBody(
    data: text,
    selectable: false,
    styleSheet: mdStyleSheet(fg, isDark),
    onTapLink: launchMarkdownUrl,
    extensionSet: mdp.ExtensionSet.gitHubWeb,
    inlineSyntaxes: kLatexInlineSyntaxes,
    blockSyntaxes: [...kAlertBlockSyntaxes, ...kLatexBlockSyntaxes],
    builders: latexBuilders(fg: fg, isDark: isDark),
  );
}

/// 是否值得走 Markdown 解析。纯文本直接用 SelectableText，省一次解析。
///
/// 字符类覆盖 markdown 语法触发字符：`* _ ` ~ # | > [ < > $ \`。
final _mdTrigger = RegExp(r'[*_`~#|>\[\]$\\]');

bool _hasMarkdown(String t) => _mdTrigger.hasMatch(t);
