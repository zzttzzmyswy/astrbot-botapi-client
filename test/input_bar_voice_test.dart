// test/input_bar_voice_test.dart
//
// 输入栏「按住说话」：长按必须触发录音回调。回归：麦克风按钮曾被 Tooltip 包裹，
// Tooltip 自带的长按识别器在手势竞技场中更深一层、抢先胜出，只弹出提示文字，
// 外层 GestureDetector 的 onLongPressStart 永远不触发 → 实际不录音。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:astrbot_app/screens/chat/input_bar.dart';

void main() {
  testWidgets('长按麦克风触发 onVoiceStart / onVoiceEnd，且不弹 Tooltip', (t) async {
    var started = 0, ended = 0;
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: ChatInputBar(
            send: () {},
            showAttachment: () {},
            controller: TextEditingController(),
            focusNode: FocusNode(),
            isDark: false,
            hasText: false,
            onVoiceStart: () => started++,
            onVoiceMove: (_) {},
            onVoiceEnd: () => ended++,
            onPickSlash: (_) {},
          ),
        ),
      ),
    ));

    final mic = find.byIcon(Icons.mic_none_rounded);
    final g = await t.startGesture(t.getCenter(mic));
    await t.pump(const Duration(milliseconds: 700));
    expect(started, 1, reason: '长按 500ms 后应开始录音');
    expect(find.text('按住说话'), findsNothing, reason: '不应抢手势弹出提示');
    await g.up();
    await t.pump();
    expect(ended, 1);
  });
}
