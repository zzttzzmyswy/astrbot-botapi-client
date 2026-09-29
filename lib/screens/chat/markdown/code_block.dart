// lib/screens/chat/markdown/code_block.dart
//
// 代码块渲染：圆角底 + 顶部语言标签与「复制」按钮 + 横向滚动的等宽正文。
//
// 为什么自绘：flutter_markdown 默认把 `code` 样式（含 backgroundColor）逐行
// 套在代码块文字上，行尾长短不一时呈现锯齿状的色块；且没有复制入口。注册
// `pre` builder 后，builder 的返回值整体替换默认子节点，这里拿 element 的纯文本
// 自行排版。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart' as md;
import 'package:markdown/markdown.dart' as mdp;

import '../../../design/tokens.dart';

class CodeBlockBuilder extends md.MarkdownElementBuilder {
  final Color fg;
  final bool isDark;
  final bool mine;

  CodeBlockBuilder({required this.fg, required this.isDark, this.mine = false});

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    mdp.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    var code = element.textContent;
    if (code.endsWith('\n')) code = code.substring(0, code.length - 1);
    String? lang;
    final children = element.children;
    if (children != null && children.isNotEmpty) {
      final first = children.first;
      if (first is mdp.Element) {
        final cls = first.attributes['class'] ?? '';
        if (cls.startsWith('language-')) lang = cls.substring(9);
      }
    }
    return CodeBlockView(
        code: code, language: lang, fg: fg, isDark: isDark, mine: mine);
  }
}

class CodeBlockView extends StatefulWidget {
  final String code;
  final String? language;
  final Color fg;
  final bool isDark;
  final bool mine;

  const CodeBlockView({
    super.key,
    required this.code,
    required this.language,
    required this.fg,
    required this.isDark,
    this.mine = false,
  });

  @override
  State<CodeBlockView> createState() => _CodeBlockViewState();
}

class _CodeBlockViewState extends State<CodeBlockView> {
  bool _copied = false;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.code));
    if (!mounted) return;
    setState(() => _copied = true);
    Future.delayed(const Duration(milliseconds: 1600), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.forDark(widget.isDark);
    final bg = widget.mine ? Colors.white.withValues(alpha: 0.14) : c.codeBg;
    final border = widget.mine
        ? Colors.white.withValues(alpha: 0.18)
        : c.bubbleOtherBorder;
    final sub = widget.fg.withValues(alpha: 0.55);
    final lang = (widget.language ?? '').trim();

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: border, width: 0.8),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 4, 0),
            child: Row(children: [
              Expanded(
                child: Text(lang.isEmpty ? 'code' : lang,
                    style: TextStyle(
                        color: sub,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.3)),
              ),
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: _copy,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  child: AnimatedSwitcher(
                    duration: AppMotion.fast,
                    child: Row(
                      key: ValueKey(_copied),
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                            _copied
                                ? Icons.check_rounded
                                : Icons.content_copy_rounded,
                            size: 14,
                            color: _copied && !widget.mine ? c.success : sub),
                        const SizedBox(width: 4),
                        Text(_copied ? '已复制' : '复制',
                            style: TextStyle(
                                color: _copied && !widget.mine
                                    ? c.success
                                    : sub,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w500)),
                      ],
                    ),
                  ),
                ),
              ),
            ]),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(12, 2, 12, 12),
            child: Text(
              widget.code,
              softWrap: false,
              style: TextStyle(
                color: widget.fg,
                fontSize: 13,
                height: 1.5,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
