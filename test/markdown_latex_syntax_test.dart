// test/markdown_latex_syntax_test.dart
//
// LaTeX 数学定界符的解析单测。
//
// 测试策略：直接构造 `md.Document`（与生产渲染路径同一个扩展集 + 同一个自定义
// 语法列表），检查 parse 出来的 AST 节点 tag 与内容。不涉及 widget 层，
// 因此能精确锁定"什么文本会被识别成公式"这一层语义。
import 'package:flutter_test/flutter_test.dart';
import 'package:markdown/markdown.dart' as md;

import 'package:astrbot_app/screens/chat/markdown/latex_syntax.dart';

/// 与生产路径一致的解析器：GFM + 数学语法。
md.Document _doc() => md.Document(
      extensionSet: md.ExtensionSet.gitHubWeb,
      inlineSyntaxes: kLatexInlineSyntaxes,
      blockSyntaxes: kLatexBlockSyntaxes,
    );

/// 收集所有 tag == [tag] 的元素内容（深度遍历）。
List<String> _tags(List<md.Node> nodes, String tag) {
  final out = <String>[];
  void walk(md.Node n) {
    if (n is md.Element) {
      if (n.tag == tag) out.add(n.textContent);
      final children = n.children;
      if (children != null) children.forEach(walk);
    }
  }

  nodes.forEach(walk);
  return out;
}

/// 整篇文档的纯文本内容（用于断言"未被识别成公式时文本原样保留"）。
String _plain(List<md.Node> nodes) => nodes.map((n) => n.textContent).join();

void main() {
  group('行内公式 \$...\$', () {
    test('识别单美元公式并剥离定界符', () {
      final nodes = _doc().parse(r'质能方程 $E=mc^2$ 成立');
      expect(_tags(nodes, 'latex-inline'), ['E=mc^2']);
      expect(_plain(nodes), '质能方程 E=mc^2 成立');
    });

    test(r'支持含反斜杠命令的公式（\frac \times \sqrt 不被转义吃掉）', () {
      final nodes = _doc().parse(r'$\frac{a}{b} \times \sqrt{x}$');
      expect(_tags(nodes, 'latex-inline'), [r'\frac{a}{b} \times \sqrt{x}']);
    });

    test('一行内多个行内公式各自识别', () {
      final nodes = _doc().parse(r'$a$ 与 $b$');
      expect(_tags(nodes, 'latex-inline'), ['a', 'b']);
    });
  });

  group(r'行内公式 \(...\)', () {
    test(r'识别 \(x+y\)', () {
      final nodes = _doc().parse(r'和 \(x+y\) 一样');
      expect(_tags(nodes, 'latex-inline'), ['x+y']);
      expect(_plain(nodes), '和 x+y 一样');
    });
  });

  group(r'独立公式 $$...$$', () {
    test('整行双美元块产出 latex-block', () {
      final nodes = _doc().parse(r'$$a^2+b^2=c^2$$');
      expect(_tags(nodes, 'latex-block'), ['a^2+b^2=c^2']);
    });

    test('跨行双美元块合并为单个公式', () {
      const src = r'$$' '\n' r'\int_0^1 x\,dx' '\n' r'$$';
      final nodes = _doc().parse(src);
      expect(_tags(nodes, 'latex-block'), [r'\int_0^1 x\,dx']);
    });

    test('段落中间的双美元按行内公式处理', () {
      final nodes = _doc().parse(r'前 $$x$$ 后');
      expect(_tags(nodes, 'latex-inline'), ['x']);
      expect(_tags(nodes, 'latex-block'), isEmpty);
    });

    test('带前后空白的独立公式行仍识别', () {
      final nodes = _doc().parse(r'   $$y = kx + b$$   ');
      expect(_tags(nodes, 'latex-block'), ['y = kx + b']);
    });
  });

  group(r'独立公式 \[...\]', () {
    test(r'识别 \[x^2\]', () {
      final nodes = _doc().parse(r'\[x^2\]');
      expect(_tags(nodes, 'latex-block'), ['x^2']);
    });
  });

  group('不误伤：金额与转义', () {
    test(r'\$100 转义后不识别为公式', () {
      final nodes = _doc().parse(r'花费 \$100 元');
      expect(_tags(nodes, 'latex-inline'), isEmpty);
      // 反斜杠由标准转义语法消费，文本仍是字面美元符号。
      expect(_plain(nodes), r'花费 $100 元');
    });

    test("金额 5 美元 / 6 美元不识别", () {
      final nodes = _doc().parse(r'价格 $5 和 $6 元');
      expect(_tags(nodes, 'latex-inline'), isEmpty);
      expect(_plain(nodes), r'价格 $5 和 $6 元');
    });

    test('未闭合的美元符号保持纯文本', () {
      final nodes = _doc().parse(r'计算 $x^2 还没写完');
      expect(_tags(nodes, 'latex-inline'), isEmpty);
      expect(_plain(nodes), r'计算 $x^2 还没写完');
    });

    test('空公式不产出元素', () {
      final nodes = _doc().parse(r'a $$ b');
      expect(_tags(nodes, 'latex-inline'), isEmpty);
      expect(_tags(nodes, 'latex-block'), isEmpty);
    });
  });

  group('不误伤：代码', () {
    test('行内代码里的美元符号不识别为公式', () {
      final nodes = _doc().parse(r'写作 `$x$` 表示公式');
      expect(_tags(nodes, 'latex-inline'), isEmpty);
    });

    test('围栏代码块里的美元符号不识别为公式', () {
      final nodes = _doc().parse('```\n\$x\$\n```');
      expect(_tags(nodes, 'latex-inline'), isEmpty);
      expect(_tags(nodes, 'latex-block'), isEmpty);
    });
  });

  group('与普通 Markdown 混排', () {
    test('公式不破坏列表与强调', () {
      final nodes = _doc().parse('- **粗** \$x\$\n- 第二项');
      expect(_tags(nodes, 'latex-inline'), ['x']);
      expect(_tags(nodes, 'strong'), ['粗']);
      expect(_tags(nodes, 'li'), hasLength(2));
    });
  });
}
