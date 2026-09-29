// test/chat_ui_logic_test.dart
//
// 聊天页纯逻辑：消息分组规则、滚动条拖动比例换算。
import 'package:flutter_test/flutter_test.dart';

import 'package:astrbot_app/models/message.dart';
import 'package:astrbot_app/screens/chat/message_grouping.dart';
import 'package:astrbot_app/screens/chat/scroll_thumb.dart';

LocalMessage _m(bool me, int t, {String type = 'text'}) =>
    LocalMessage(msgType: type, content: 'x', isFromMe: me, createdAt: t);

void main() {
  group('sameGroup', () {
    final base = DateTime(2026, 9, 29, 12).millisecondsSinceEpoch;

    test('同一发送方、3 分钟内 → 同组', () {
      expect(sameGroup(_m(true, base), _m(true, base + 60000)), isTrue);
    });
    test('发送方不同 → 不同组', () {
      expect(sameGroup(_m(true, base), _m(false, base + 1000)), isFalse);
    });
    test('间隔超过 3 分钟 → 不同组', () {
      expect(sameGroup(_m(false, base), _m(false, base + 181000)), isFalse);
    });
    test('思考 / 工具状态行打断分组', () {
      expect(
          sameGroup(_m(false, base, type: 'thinking'), _m(false, base + 1)),
          isFalse);
      expect(
          sameGroup(_m(false, base), _m(false, base + 1, type: 'tool_status')),
          isFalse);
    });
    test('跨天 → 不同组', () {
      final late = DateTime(2026, 9, 29, 23, 59, 30).millisecondsSinceEpoch;
      final early = DateTime(2026, 9, 30, 0, 0, 10).millisecondsSinceEpoch;
      expect(sameGroup(_m(true, late), _m(true, early)), isFalse);
    });
  });

  group('thumbFraction', () {
    test('按轨道坐标换算并扣除抓取偏移', () {
      // 轨道 500、滑块 100：可移动范围 400。手指在滑块内 20 处按下，
      // 拖到轨道 y=220 → 滑块顶部 200 → 0.5。
      expect(
          thumbFraction(
              trackY: 220, grabOffset: 20, trackHeight: 500, thumbHeight: 100),
          0.5);
    });
    test('越界夹到 0..1', () {
      expect(
          thumbFraction(
              trackY: -50, grabOffset: 10, trackHeight: 500, thumbHeight: 100),
          0);
      expect(
          thumbFraction(
              trackY: 900, grabOffset: 10, trackHeight: 500, thumbHeight: 100),
          1);
    });
    test('轨道不足滑块高度 → 0（不除零）', () {
      expect(
          thumbFraction(
              trackY: 10, grabOffset: 0, trackHeight: 40, thumbHeight: 44),
          0);
    });
  });
}
