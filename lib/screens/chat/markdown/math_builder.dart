// lib/screens/chat/markdown/math_builder.dart
//
// 把 LaTeX 元素渲染成公式 Widget（flutter_math_fork）。
//
// 行内公式嵌进文本行（WidgetSpan），独立公式块独占一块可横向滚动的区域。
// 解析失败一律降级为原文 + 淡边框，不抛异常、不留空白。
import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart' as fmath;
import 'package:flutter_markdown/flutter_markdown.dart' as md;
import 'package:markdown/markdown.dart' as mdp;

import 'latex_syntax.dart';

/// 行内公式：垂直居中对齐嵌入文本行。
///
/// 必须包成 `Text.rich`：flutter_markdown 会把 builder 返回的 widget 通过
/// `Text.textSpan` 拆成 InlineSpan 参与整段文本的排版，直接把 `WidgetSpan`
/// 当 Widget 返回会在运行时抛类型转换错误。
class LatexInlineBuilder extends md.MarkdownElementBuilder {
  final Color fg;
  final bool isDark;

  LatexInlineBuilder({required this.fg, required this.isDark});

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    mdp.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final latex = element.textContent;
    if (latex.trim().isEmpty) return null;

    final size = parentStyle?.fontSize ?? preferredStyle?.fontSize ?? 16;
    return Text.rich(
      TextSpan(children: [
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: _math(latex, fg: fg, isDark: isDark, fontSize: size),
        ),
      ]),
    );
  }
}

/// 独立公式块：水平居中，独占一行。
class LatexBlockBuilder extends md.MarkdownElementBuilder {
  final Color fg;
  final bool isDark;

  LatexBlockBuilder({required this.fg, required this.isDark});

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    mdp.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final latex = element.textContent;
    if (latex.trim().isEmpty) return null;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Center(
        child: _math(latex,
            fg: fg, isDark: isDark, fontSize: 17, display: true),
      ),
    );
  }
}

Widget _math(
  String latex, {
  required Color fg,
  required bool isDark,
  required double fontSize,
  bool display = false,
}) {
  final style = TextStyle(color: fg, fontSize: fontSize);
  return fmath.Math.tex(
    latex,
    mathStyle:
        display ? fmath.MathStyle.display : fmath.MathStyle.text,
    textStyle: style,
    onErrorFallback: (err) => _fallback(latex, fg, isDark, fontSize),
  );
}

/// 公式解析失败时的降级：显示原始 LaTeX，淡色描边示意此处渲染失败。
Widget _fallback(String latex, Color fg, bool isDark, double fontSize) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
    decoration: BoxDecoration(
      border: Border.all(
        color: fg.withValues(alpha: isDark ? 0.28 : 0.22),
        width: 0.5,
      ),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text(
      latex,
      style: TextStyle(
        color: fg,
        fontSize: fontSize,
        fontFamily: 'monospace',
      ),
    ),
  );
}

/// tag → builder 映射，交给 `MarkdownBody.builders`。
Map<String, md.MarkdownElementBuilder> latexBuilders({
  required Color fg,
  required bool isDark,
}) =>
    {
      kLatexInlineTag: LatexInlineBuilder(fg: fg, isDark: isDark),
      kLatexBlockTag: LatexBlockBuilder(fg: fg, isDark: isDark),
    };
