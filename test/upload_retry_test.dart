// test/upload_retry_test.dart
//
// 分块上传「未知结局」协调：超时块是否落地由服务端 offset probe 判定。
// 判定错误会导致重复字节（跳过不够）或丢字节（重发不够），是正确性核心。
import 'package:flutter_test/flutter_test.dart';
import 'package:astrbot_app/util/upload_reconcile.dart';

void main() {
  group('reconcileChunkAfterProbe', () {
    const chunk = 5 * 1024 * 1024;

    test('probe 与服务端一致(块未落地) → 重发', () {
      expect(
        reconcileChunkAfterProbe(
            expectedOffset: 0, serverOffset: 0, chunkLength: chunk),
        ChunkProbeResult.sendChunk,
      );
      expect(
        reconcileChunkAfterProbe(
            expectedOffset: chunk, serverOffset: chunk, chunkLength: chunk),
        ChunkProbeResult.sendChunk,
      );
    });

    test('服务端多了一个整块(超时块已落地) → 跳过', () {
      expect(
        reconcileChunkAfterProbe(
            expectedOffset: 0, serverOffset: chunk, chunkLength: chunk),
        ChunkProbeResult.skipChunk,
      );
      expect(
        reconcileChunkAfterProbe(
            expectedOffset: chunk, serverOffset: 2 * chunk, chunkLength: chunk),
        ChunkProbeResult.skipChunk,
      );
    });

    test('末块小于 chunkSize 时按实际长度判定', () {
      const last = 12345;
      expect(
        reconcileChunkAfterProbe(
            expectedOffset: 2 * chunk, serverOffset: 2 * chunk + last,
            chunkLength: last),
        ChunkProbeResult.skipChunk,
      );
      expect(
        reconcileChunkAfterProbe(
            expectedOffset: 2 * chunk, serverOffset: 2 * chunk, chunkLength: last),
        ChunkProbeResult.sendChunk,
      );
    });

    test('部分写入/字节漂移 → 放弃整次(避免静默损坏)', () {
      expect(
        reconcileChunkAfterProbe(
            expectedOffset: 0, serverOffset: 123, chunkLength: chunk),
        ChunkProbeResult.abort,
      );
      expect(
        reconcileChunkAfterProbe(
            expectedOffset: 0, serverOffset: 2 * chunk, chunkLength: chunk),
        ChunkProbeResult.abort,
      );
    });

    test('服务端落后(字节丢失) → 放弃整次', () {
      expect(
        reconcileChunkAfterProbe(
            expectedOffset: chunk, serverOffset: 100, chunkLength: chunk),
        ChunkProbeResult.abort,
      );
    });
  });
}