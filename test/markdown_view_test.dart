// test/markdown_view_test.dart
//
// 渲染层 widget 测试：公式 Widget 是否真的出现在 widget tree 里、
// 非法公式是否降级、明暗主题是否互不串味、流式气泡与终态气泡是否一致。
import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart' as fmath;
import 'package:flutter_test/flutter_test.dart';
import 'package:markdown/markdown.dart' as mdp;

import 'package:astrbot_app/screens/chat/bubbles/streaming_bubble.dart';
import 'package:astrbot_app/screens/chat/markdown/alert_syntax.dart';
import 'package:astrbot_app/screens/chat/markdown/latex_syntax.dart';
import 'package:astrbot_app/screens/chat/markdown/markdown_view.dart';

Future<void> _pump(WidgetTester t, String text,
    {bool isDark = false, double width = 320}) async {
  await t.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(width: width, child: buildMarkdown(text, Colors.black, isDark)),
      ),
    ),
  ));
  await t.pumpAndSettle();
}

/// 页面上全部可见文本。Markdown 正文走 `Text.rich`，其内容在 TextSpan 里而非
/// `Text.data`，因此统一从 RichText 取 plain text。
String _visibleText(WidgetTester t) => t
    .widgetList<RichText>(find.byType(RichText))
    .map((w) => w.text.toPlainText())
    .join('|');

void main() {
  group('公式渲染', () {
    testWidgets('行内公式渲染出 Math widget', (t) async {
      await _pump(t, r'质能方程 $E=mc^2$ 成立');
      expect(find.byType(fmath.Math), findsOneWidget);
    });

    testWidgets('独立公式块渲染出 Math widget', (t) async {
      await _pump(t, r'$$\int_0^1 x\,dx = \frac{1}{2}$$');
      expect(find.byType(fmath.Math), findsOneWidget);
    });

    testWidgets('跨行独立公式块渲染出单个 Math widget', (t) async {
      await _pump(t, r'$$' '\n' r'a^2 + b^2 = c^2' '\n' r'$$');
      expect(find.byType(fmath.Math), findsOneWidget);
    });

    testWidgets('一段文本里多个公式各渲染一个 Math widget', (t) async {
      await _pump(t, r'$a$ 与 $b$ 以及 $$\sum_{i=1}^n i$$');
      expect(find.byType(fmath.Math), findsNWidgets(3));
    });
  });

  group('降级不崩', () {
    testWidgets('非法 LaTeX 渲染成功且不抛异常', (t) async {
      await _pump(t, r'$\frac{1}{$');
      expect(t.takeException(), isNull);
      expect(find.byType(fmath.Math), findsOneWidget);
    });

    testWidgets('非法公式仍能看到原始表达式片段', (t) async {
      await _pump(t, r'结果 $\begin{unknown}$ 结束');
      final texts = _visibleText(t);
      expect(texts.contains('结果') && texts.contains('结束'), isTrue);
      expect(texts.contains(r'\begin{unknown}'), isTrue);
    });

    testWidgets('未闭合公式按纯文本显示', (t) async {
      await _pump(t, r'计算 $x^2 还没写完');
      expect(find.byType(fmath.Math), findsNothing);
    });

    testWidgets('金额不被当成公式', (t) async {
      await _pump(t, r'价格 $5 和 $6 元');
      expect(find.byType(fmath.Math), findsNothing);
    });

    testWidgets('空内容不渲染任何东西', (t) async {
      await _pump(t, '');
      expect(find.byType(fmath.Math), findsNothing);
      expect(t.takeException(), isNull);
    });
  });

  group('完整 Markdown 能力', () {
    testWidgets('表格渲染', (t) async {
      await _pump(t, '| a | b |\n| --- | --- |\n| 1 | 2 |');
      expect(find.byType(Table), findsOneWidget);
    });

    testWidgets('任务列表渲染出勾选框', (t) async {
      await _pump(t, '- [x] 已完成\n- [ ] 未完成');
      expect(find.byIcon(Icons.check_box), findsOneWidget);
      expect(find.byIcon(Icons.check_box_outline_blank), findsOneWidget);
    });

    testWidgets('alert 块渲染出内容', (t) async {
      await _pump(t, '> [!NOTE]\n> 这是提示');
      expect(t.takeException(), isNull);
      expect(_visibleText(t).contains('这是提示'), isTrue);
    });

    test('alert 解析为 blockquote（自带左侧竖线样式），且吃掉 [!NOTE] 标记', () {
      // 真机截图发现：若产出 section 且无样式，alert 会退化成一段平铺文字，
      // 标题 "Note" 看起来像正文。锁死 blockquote，保证视觉上是独立 callout。
      final doc = mdp.Document(
        extensionSet: mdp.ExtensionSet.gitHubWeb,
        inlineSyntaxes: kLatexInlineSyntaxes,
        blockSyntaxes: [...kAlertBlockSyntaxes, ...kLatexBlockSyntaxes],
      );
      final nodes = doc.parse('> [!NOTE]\n> 这是提示');
      expect(nodes, hasLength(1));
      final el = nodes.single as mdp.Element;
      expect(el.tag, 'blockquote');
      expect(el.textContent.contains('这是提示'), isTrue);
      expect(el.textContent.contains('[!NOTE]'), isFalse);
    });
  });

  group('主题与缓存', () {
    testWidgets('明暗主题下都能构建且公式存在', (t) async {
      await _pump(t, r'$x^2$');
      expect(find.byType(fmath.Math), findsOneWidget);
      await _pump(t, r'$x^2$', isDark: true);
      expect(find.byType(fmath.Math), findsOneWidget);
    });

    testWidgets('同一文本重复构建命中缓存', (t) async {
      final a = buildMarkdown(r'缓存命中 $x$', Colors.black, false);
      final b = buildMarkdown(r'缓存命中 $x$', Colors.black, false);
      expect(identical(a, b), isTrue);
    });

    testWidgets('明暗主题缓存不互相污染', (t) async {
      final light = buildMarkdown(r'主题 $x$', Colors.black, false);
      final dark = buildMarkdown(r'主题 $x$', Colors.white, true);
      expect(identical(light, dark), isFalse);
    });

    testWidgets('文本变化后渲染新内容而非旧缓存', (t) async {
      await _pump(t, r'第一版 $a$');
      expect(_visibleText(t).contains('第一版'), isTrue);
      await _pump(t, r'第二版 $b$');
      final texts = _visibleText(t);
      expect(texts.contains('第二版'), isTrue);
      expect(texts.contains('第一版'), isFalse);
    });
  });

  group('流式与终态一致', () {
    testWidgets('StreamingBubble 与正文渲染都能出公式', (t) async {
      await t.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 320,
              child: StreamingBubble(
                text: r'流式 $E=mc^2$ 内容',
                bw: 280,
                isDark: false,
              ),
            ),
          ),
        ),
      ));
      await t.pumpAndSettle();
      expect(find.byType(fmath.Math), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  });
}
