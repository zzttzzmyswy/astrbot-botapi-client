// lib/screens/chat/message_grouping.dart
//
// 连续消息分组：同一发送方、同一天、间隔不超过 [kGroupGap] 的普通消息归为一组。
// 组内气泡间距收紧、只在组尾显示时间，界面更接近主流 IM 的节奏感。
// 纯函数，便于单测。
import '../../models/message.dart';

const Duration kGroupGap = Duration(minutes: 3);

/// 思考 / 工具状态是「系统行」，不参与气泡分组，且会打断分组。
bool isSystemRow(LocalMessage m) =>
    m.msgType == 'thinking' || m.msgType == 'tool_status';

/// [a] 与紧随其后的 [b] 是否属于同一组。
bool sameGroup(LocalMessage a, LocalMessage b) {
  if (isSystemRow(a) || isSystemRow(b)) return false;
  if (a.isFromMe != b.isFromMe) return false;
  final da = DateTime.fromMillisecondsSinceEpoch(a.createdAt, isUtc: true)
      .toLocal();
  final db = DateTime.fromMillisecondsSinceEpoch(b.createdAt, isUtc: true)
      .toLocal();
  if (da.year != db.year || da.month != db.month || da.day != db.day) {
    return false;
  }
  return (b.createdAt - a.createdAt).abs() <= kGroupGap.inMilliseconds;
}
