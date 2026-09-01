// lib/util/upload_reconcile.dart
//
// 分块上传的「未知结局」协调逻辑。
//
// 服务端对 upload_id 的 .part 文件盲目追加，并在每次 /upload/chunk 后返回当前
// part 大小（offset）。当某一块请求超时/连接失败时，客户端无法确定该块是否已
// 写入；重试前先以 0 字节块 probe 取回服务端真实 offset，据此决定该块 重发 /
// 跳过 / 整次放弃。所有判定是纯函数，便于单测。

enum ChunkProbeResult { sendChunk, skipChunk, abort }

/// 依据 probe 返回的服务端 offset 与本地期望 offset 判定下一步。
/// - [expectedOffset]：本次重试前客户端上次成功推进的 offset（即本块起点）
/// - [serverOffset]：probe 拿到的服务端 part 大小
/// - [chunkLength]：本块字节数
ChunkProbeResult reconcileChunkAfterProbe({
  required int expectedOffset,
  required int serverOffset,
  required int chunkLength,
}) {
  if (serverOffset < expectedOffset) return ChunkProbeResult.abort;
  final gap = serverOffset - expectedOffset;
  if (gap == 0) return ChunkProbeResult.sendChunk;
  if (gap == chunkLength) return ChunkProbeResult.skipChunk;
  // 部分写入/漂移：无法安全续传，放弃整次（调用方换新 upload_id 从头来）
  return ChunkProbeResult.abort;
}