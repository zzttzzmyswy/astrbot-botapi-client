// integration_test/markdown_device_test.dart
//
// 真机渲染回归测试：在真实 Android 设备上验证 Markdown + 数学公式渲染。
//
// 与 test/markdown_view_test.dart 的区别：那些用例跑在宿主 VM 的 flutter_test
// 里，这里跑在设备上，覆盖的是真实引擎、真实字体加载与 APK 内的资源打包
// （flutter_math_fork 的 KaTeX 字体是随包 asset，打包缺失时公式会渲染成方框，
// 宿主测试不一定能暴露）。
//
// 运行方式：
//   flutter test integration_test/markdown_device_test.dart -d <device-id>
//
// 需要抓真机截图时加 --dart-define=HOLD_SCREENSHOT=true，用例会在渲染完画面后
// 停留一段时间，方便外部 adb exec-out screencap 抓图。
import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart' as fmath;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:astrbot_app/screens/chat/markdown/markdown_view.dart';

const _holdForScreenshot = bool.fromEnvironment('HOLD_SCREENSHOT');

/// 一条典型的模型回复：标题、强调、列表、表格、alert、行内代码、多种公式。
const _sample = '''
## 二次方程求根

对于一般形式 \$ax^2+bx+c=0\$，判别式为

\$\$\\Delta = b^2 - 4ac\$\$

- 当 \$\\Delta > 0\$ 时有两个实根
- 当 \$\\Delta = 0\$ 时有一个重根

| 情况 | 根 |
| --- | --- |
| \$\\Delta>0\$ | 两个不相等实根 |

> [!NOTE]
> 这里要求 \$a \\ne 0\$

\\[x = \\frac{-b \\pm \\sqrt{\\Delta}}{2a}\\]

行内代码 `\$not_math\$` 不应渲染，价格 \$5 和 \$6 也不应渲染。
''';

Future<void> _pump(WidgetTester t, String text, {bool isDark = false}) async {
  await t.pumpWidget(MaterialApp(
    theme: ThemeData(brightness: isDark ? Brightness.dark : Brightness.light),
    home: Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF0E0E10) : const Color(0xFFF7F7FA),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: buildMarkdown(text,
                  isDark ? Colors.white : Colors.black, isDark),
            ),
          ),
        ),
      ),
    ),
  ));
  await t.pumpAndSettle();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('典型混合消息在真机上渲染出全部公式', (t) async {
    await _pump(t, _sample);
    expect(t.takeException(), isNull);
    // 行内 5 个（ax^2+bx+c / Δ>0 / Δ=0 / 表格单元 / a≠0）+ 独立块 2 个。
    expect(find.byType(fmath.Math), findsNWidgets(7));
    expect(find.byType(Table), findsOneWidget);
    expect(find.byIcon(Icons.check_box), findsNothing);

    if (_holdForScreenshot) {
      await Future<void>.delayed(const Duration(seconds: 20));
    }
  });

  testWidgets('非法公式在真机上降级不崩', (t) async {
    await _pump(t, r'结果 $\begin{unknown}$ 结束');
    expect(t.takeException(), isNull);
    expect(find.byType(fmath.Math), findsOneWidget);
  });

  testWidgets('暗色主题下公式可渲染', (t) async {
    await _pump(t, r'暗色 $$\int_0^1 x\,dx = \frac{1}{2}$$', isDark: true);
    expect(t.takeException(), isNull);
    expect(find.byType(fmath.Math), findsOneWidget);

    if (_holdForScreenshot) {
      await Future<void>.delayed(const Duration(seconds: 20));
    }
  });

  testWidgets('长公式不溢出窄屏', (t) async {
    await _pump(
      t,
      r'$$\hat{H}\psi = -\frac{\hbar^2}{2m}\nabla^2\psi + V(\mathbf{r})\psi'
      r' = E\psi$$',
    );
    expect(t.takeException(), isNull);
    expect(find.byType(fmath.Math), findsOneWidget);
  });
}
