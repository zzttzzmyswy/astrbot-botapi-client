// lib/util/download_resume.dart
//
// 下载续传的纯判定逻辑：解析 Content-Range、处理 416 后再决定收尾/重下。
// 实际 HTTP 层在 botapi_http.dart，这里只保留可单测的决策。

/// 解析 Content-Range 的 total：
/// `bytes 0-99/5000` → 5000；`bytes */5000` → 5000；无法解析 → null。
int? parseContentRangeTotal(String? header) {
  if (header == null) return null;
  final trimmed = header.trim();
  final i = trimmed.lastIndexOf('/');
  if (i < 0) return null;
  return int.tryParse(trimmed.substring(i + 1).trim());
}

enum PartRangeDecision { complete, restart }

/// 服务端返回 416（Range 范围无效）时：部分文件长度已覆盖服务端 total →
/// 视为完整（改名收尾即可）；否则说明部分文件与服务端不一致 → 删除重新下载。
PartRangeDecision decideRange416({
  required int partLength,
  required int? serverTotal,
}) {
  if (serverTotal != null && partLength >= serverTotal) {
    return PartRangeDecision.complete;
  }
  return PartRangeDecision.restart;
}