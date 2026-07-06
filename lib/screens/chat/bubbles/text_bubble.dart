// lib/screens/chat/bubbles/text_bubble.dart
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart' as md;
import 'package:url_launcher/url_launcher.dart';
import '../../../util/lru_cache.dart';

/// 共享 markdown 样式表
md.MarkdownStyleSheet mdStyleSheet(Color fg, bool isDark) {
  return md.MarkdownStyleSheet(
    p: TextStyle(color: fg, fontSize: 16, height: 1.35),
    h1: TextStyle(color: fg, fontSize: 20, fontWeight: FontWeight.bold),
    h2: TextStyle(color: fg, fontSize: 18, fontWeight: FontWeight.bold),
    h3: TextStyle(color: fg, fontSize: 17, fontWeight: FontWeight.bold),
    a: TextStyle(
        color: const Color(0xFF4A8FE7),
        decoration: TextDecoration.underline,
        decorationColor: const Color(0xFF4A8FE7)),
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

Widget mdText(String text, Color fg, bool isDark) {
  if (text.isEmpty) return const SizedBox.shrink();
  if (!_hasMarkdown(text)) {
    return SelectableText(text,
        style: TextStyle(color: fg, fontSize: 16, height: 1.35));
  }
  return SelectionArea(
      child: _MarkdownContent(text: text, fg: fg, isDark: isDark));
}

bool _hasMarkdown(String t) {
  for (int i = 0; i < t.length; i++) {
    final c = t.codeUnitAt(i);
    if (c == 0x2A ||
        c == 0x5F ||
        c == 0x60 ||
        c == 0x7E ||
        c == 0x23 ||
        c == 0x7C ||
        c == 0x3E ||
        c == 0x5B) return true;
  }
  return false;
}

class _MarkdownContent extends StatefulWidget {
  final String text;
  final Color fg;
  final bool isDark;
  const _MarkdownContent(
      {required this.text, required this.fg, required this.isDark});
  @override
  State<_MarkdownContent> createState() => _MarkdownContentState();
}

class _MarkdownContentState extends State<_MarkdownContent> {
  static final LruCache<String, Widget> _cache = LruCache(maxSize: 32);
  Widget? _built;

  @override
  void initState() {
    super.initState();
    _build();
  }

  @override
  void didUpdateWidget(covariant _MarkdownContent old) {
    super.didUpdateWidget(old);
    if (widget.text != old.text || widget.isDark != old.isDark) _build();
  }

  void _build() {
    final key = '${widget.isDark ? 'd' : 'l'}_${widget.text}';
    final cached = _cache[key];
    if (cached != null) {
      _built = cached;
      return;
    }
    Future.microtask(() {
      if (!mounted) return;
      final w = md.MarkdownBody(
        data: widget.text,
        selectable: false,
        styleSheet: mdStyleSheet(widget.fg, widget.isDark),
        onTapLink: launchMarkdownUrl,
      );
      _cache[key] = w;
      if (mounted) setState(() => _built = w);
    });
  }

  @override
  Widget build(BuildContext context) =>
      _built ??
      Text(widget.text,
          style:
              TextStyle(color: widget.fg, fontSize: 16, height: 1.35));
}

/// 文本气泡发送失败态:点击重发。通过 callback 解耦。
class TextBodyError extends StatelessWidget {
  final String content;
  final VoidCallback onRetry;
  const TextBodyError(
      {super.key, required this.content, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onRetry,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.error_outline_rounded,
            color: Colors.redAccent, size: 16),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            content,
            style: const TextStyle(
                color: Colors.redAccent,
                fontSize: 15,
                height: 1.35,
                decoration: TextDecoration.lineThrough),
          ),
        ),
        const SizedBox(width: 6),
        const Icon(Icons.refresh_rounded,
            color: Colors.redAccent, size: 16),
      ]),
    );
  }
}
