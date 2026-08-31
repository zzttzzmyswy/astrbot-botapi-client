// test/download_resume_test.dart
//
// 下载续传判定：Range 响应 total 解析、416 后收尾/重下。
import 'package:flutter_test/flutter_test.dart';
import 'package:astrbot_app/util/download_resume.dart';

void main() {
  group('parseContentRangeTotal', () {
    test('bytes 0-99/5000 → 5000', () {
      expect(parseContentRangeTotal('bytes 0-99/5000'), 5000);
    });
    test('bytes */5000 → 5000', () {
      expect(parseContentRangeTotal('bytes */5000'), 5000);
    });
    test('空/null/无斜杠 → null', () {
      expect(parseContentRangeTotal(null), isNull);
      expect(parseContentRangeTotal(''), isNull);
      expect(parseContentRangeTotal('bytes 0-99'), isNull);
    });
    test('非数字 total → null', () {
      expect(parseContentRangeTotal('bytes 0-99/x'), isNull);
    });
  });

  group('decideRange416', () {
    test('部分文件已覆盖 total → 完整,改名收尾', () {
      expect(
        decideRange416(partLength: 5000, serverTotal: 5000),
        PartRangeDecision.complete,
      );
      expect(
        decideRange416(partLength: 6000, serverTotal: 5000),
        PartRangeDecision.complete,
      );
    });
    test('长度不足/无法解析 → 删除重启下载', () {
      expect(
        decideRange416(partLength: 100, serverTotal: 5000),
        PartRangeDecision.restart,
      );
      expect(
        decideRange416(partLength: 100, serverTotal: null),
        PartRangeDecision.restart,
      );
    });
  });
}