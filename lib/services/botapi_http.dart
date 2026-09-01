// lib/services/botapi_http.dart
import 'dart:io';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:dio/dio.dart';
import 'package:http_parser/http_parser.dart';
import 'package:path_provider/path_provider.dart';
import '../models/chat_session.dart';
import '../models/history_row.dart';
import '../services/session_store.dart' show kDefaultSessionId;
import '../util/download_resume.dart';
import '../util/retry.dart';
import '../util/upload_reconcile.dart';

/// 服务器不支持会话（GET /sessions 返回 404）。调用方据此降级为单会话模式。
class SessionApiUnavailable implements Exception {
  @override
  String toString() => 'SessionApiUnavailable: 服务器不支持 /sessions API';
}

/// 规整 serverUrl 为 botapi base：保证以 /api/v1/botapi 结尾、无尾斜杠。
String botapiBase(String serverUrl) {
  var s = serverUrl.trim();
  if (s.isEmpty) return s;
  while (s.endsWith('/')) {
    s = s.substring(0, s.length - 1);
  }
  if (s.endsWith('/api/v1/botapi')) return s;
  return '$s/api/v1/botapi';
}

/// 规整媒体下载 URL：服务端 file 事件的 url 可能是相对路径（如 /files/xxx），
/// dio 无法解析 host 会 connectionError。相对路径拼 serverUrl 的 origin；
/// 绝对 URL（带 scheme+host）原样返回。
String resolveMediaUrl(String url, String serverUrl) {
  final u = Uri.tryParse(url);
  if (u != null && u.hasScheme && u.host.isNotEmpty) return url;
  final origin = Uri.parse(botapiBase(serverUrl)).origin;
  final p = url.startsWith('/') ? url : '/$url';
  return '$origin$p';
}

class UploadResult {
  final String fileId;
  final String name;
  final String mimeType;
  final int size;
  const UploadResult({
    required this.fileId,
    required this.name,
    required this.mimeType,
    required this.size,
  });
}

/// botapi 无状态 REST 客户端。给定 (serverUrl, token)。
/// [sessionId] 为当前会话 id；空串或 "default"（默认会话）时，
/// 发送消息/拉历史省略 session_id（兼容不支持会话的老服务器）。
class BotApiHttp {
  final String serverUrl;
  final String token;
  final String sessionId;
  BotApiHttp({
    required this.serverUrl,
    required this.token,
    this.sessionId = '',
  });

  @visibleForTesting
  Map<String, String> get authHeaders => _authHeaders;

  String get _base => botapiBase(serverUrl);
  Map<String, String> get _authHeaders => {'Authorization': 'Bearer $token'};

  /// 校验 token。true=有效；false=无效(401)或不可达。
  /// 带 transient 重试：冷启动时 Dart HttpClient DNS 解析可能首几次失败
  /// （系统 curl 能解析但 dart:io 不能），重试几秒后即恢复。
  Future<bool> auth() async {
    try {
      return await withRetry<bool>(
        () async {
          final dio = Dio(BaseOptions(
            connectTimeout: const Duration(seconds: 12),
            receiveTimeout: const Duration(seconds: 12),
          ));
          final res = await dio.post('$_base/auth',
              data: {'token': token},
              options: Options(headers: {'Content-Type': 'application/json'}));
          if (res.statusCode == 200) return true;
          if (res.statusCode == 401) return false;
          // 5xx 等：当作可重试的瞬态错误抛出。
          throw DioException(
            requestOptions: res.requestOptions,
            type: DioExceptionType.badResponse,
            response: res,
          );
        },
        isTransient: (e) {
          // 连接级（含 DNS host lookup 失败）、超时 → 重试；badResponse(5xx) 也重试。
          if (e is DioException) {
            return e.type == DioExceptionType.connectionError ||
                e.type == DioExceptionType.connectionTimeout ||
                e.type == DioExceptionType.receiveTimeout ||
                e.type == DioExceptionType.sendTimeout ||
                e.type == DioExceptionType.badResponse;
          }
          return false;
        },
        maxAttempts: 4,
        delayFor: (i) => Duration(seconds: 1 << i), // 1s,2s,4s
      );
    } catch (_) {
      return false;
    }
  }

  /// 拉服务器会话列表（服务端 /sessions）。404 → 抛 [SessionApiUnavailable]
  /// （服务器不支持会话），供调用方降级为单会话模式。其余错误抛 DioException。
  Future<List<ChatSession>> fetchSessions() async {
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 12),
      receiveTimeout: const Duration(seconds: 12),
    ));
    try {
      final res = await dio.get('$_base/sessions',
          options: Options(headers: _authHeaders));
      if (res.statusCode == 200 && res.data is Map) {
        final m = res.data as Map<String, dynamic>;
        final list = (m['sessions'] as List?) ?? [];
        return list
            .map((e) => ChatSession.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
      }
      throw DioException(
        requestOptions: res.requestOptions,
        type: DioExceptionType.badResponse,
        response: res,
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) throw SessionApiUnavailable();
      rethrow;
    } finally {
      dio.close();
    }
  }

  /// 新建会话。返回新会话；达到上限或名字为空 → 返回 null（服务端 400）。
  /// 网络异常同样返回 null（调用方 UI 统一提示）。
  Future<ChatSession?> createSession(String name) async {
    try {
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 12),
        receiveTimeout: const Duration(seconds: 12),
      ));
      final res = await dio.post('$_base/sessions',
          data: {'name': name},
          options: Options(
              headers: {..._authHeaders, 'Content-Type': 'application/json'}));
      if (res.statusCode == 200 && res.data is Map) {
        final s = (res.data as Map)['session'];
        if (s is Map) return ChatSession.fromJson(Map<String, dynamic>.from(s));
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// 重命名会话。成功返回 true。
  Future<bool> renameSession(String sid, String name) async {
    try {
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 12),
        receiveTimeout: const Duration(seconds: 12),
      ));
      final res = await dio.post('$_base/sessions/$sid/rename',
          data: {'name': name},
          options: Options(
              headers: {..._authHeaders, 'Content-Type': 'application/json'}));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// 删除会话。成功返回 true。
  Future<bool> deleteSession(String sid) async {
    try {
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 12),
        receiveTimeout: const Duration(seconds: 12),
      ));
      final res = await dio.post('$_base/sessions/$sid/delete',
          options: Options(headers: _authHeaders));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// 发消息。返回 message_id；失败返回 null。
  Future<String?> sendMessage({String? text, List<String>? fileIds}) async {
    try {
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 30),
      ));
      final res = await dio.post('$_base/message',
          data: {
            if (text != null && text.isNotEmpty) 'text': text,
            if (fileIds != null && fileIds.isNotEmpty) 'file_ids': fileIds,
            if (sessionId.isNotEmpty && sessionId != kDefaultSessionId)
              'session_id': sessionId,
          },
          options: Options(headers: {..._authHeaders, 'Content-Type': 'application/json'}));
      if (res.statusCode == 200) {
        return (res.data is Map) ? (res.data as Map)['message_id'] as String? : null;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// 上传文件。>10MB 走分块(每块 5MB,绕过服务端 ~90s 请求超时),否则单次。
  /// 返回 (result, error),失败附原因(413/超时等)供 UI 提示。
  Future<({UploadResult? result, String? error})> uploadFile(
      File file, String contentType,
      {void Function(int sent, int total)? onProgress}) async {
    final size = await file.length();
    const threshold = 10 * 1024 * 1024; // 10MB
    if (size > threshold) {
      return _uploadChunked(file, contentType, size, onProgress);
    }
    return _uploadSingle(file, contentType, onProgress);
  }

  String _uploadError(DioException e) {
    final sc = e.response?.statusCode;
    if (sc == 413) {
      return '文件过大,服务端拒绝(413)。需在服务器 nginx 配置 '
          'client_max_body_size(如 200m)并 reload。';
    }
    if (e.type == DioExceptionType.sendTimeout ||
        e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout) {
      return '上传超时,网络过慢或文件过大';
    }
    return '上传失败: ${e.type.name}';
  }

  UploadResult _resultFrom(Map m) => UploadResult(
        fileId: m['file_id'] as String,
        name: m['name'] as String,
        mimeType: (m['mime_type'] as String?) ?? 'application/octet-stream',
        size: (m['size'] as num).toInt(),
      );

  Future<({UploadResult? result, String? error})> _uploadSingle(
      File file, String contentType,
      void Function(int, int)? onProgress) async {
    final dio = Dio(BaseOptions(
      baseUrl: _base,
      connectTimeout: const Duration(seconds: 15),
      sendTimeout: const Duration(minutes: 5),
      receiveTimeout: const Duration(minutes: 2),
    ));
    try {
      final filename = file.path.split('/').last;
      // 瞬态重试：FormData 每次重建，避免复用已消费的 multipart 流。
      final res = await withRetry(
        () async {
          final form = FormData.fromMap({
            'file': await MultipartFile.fromFile(file.path,
                filename: filename, contentType: MediaType.parse(contentType)),
          });
          return dio.post('/upload',
              data: form,
              options: Options(headers: _authHeaders),
              onSendProgress: onProgress);
        },
        isTransient: isTransientDioError,
        maxAttempts: 3,
        delayFor: (i) => Duration(seconds: 1 << i),
      );
      if (res.statusCode == 200 && res.data is Map) {
        return (result: _resultFrom(res.data as Map), error: null);
      }
      return (result: null, error: '上传失败: HTTP ${res.statusCode}');
    } on DioException catch (e) {
      return (result: null, error: _uploadError(e));
    } catch (e) {
      return (result: null, error: '上传失败: $e');
    } finally {
      dio.close();
    }
  }

  static const int _chunkSize = 5 * 1024 * 1024; // 5MB
  static const int _chunkMaxAttempts = 3;

  /// 分块上传:5MB/块,逐块 POST /upload/chunk,最后 /upload/complete 合并。
  /// 每块远小于服务端 ~90s 请求超时,绕过单次大文件 408。
  /// 质量加固:逐块瞬态重试(连接/超时);重试前用 0 字节块 probe 服务端真实
  /// offset,判定超时块是否已落地,避免重复追加导致文件损坏。
  Future<({UploadResult? result, String? error})> _uploadChunked(
      File file, String contentType, int total,
      void Function(int, int)? onProgress) async {
    final dio = Dio(BaseOptions(
      baseUrl: _base,
      connectTimeout: const Duration(seconds: 15),
      sendTimeout: const Duration(minutes: 5),
      receiveTimeout: const Duration(minutes: 2),
    ));
    try {
      final filename = file.path.split('/').last;
      final uploadId =
          '${DateTime.now().millisecondsSinceEpoch}_${filename.hashCode.abs()}';
      final raf = await file.open();
      int offset = 0;
      try {
        while (offset < total) {
          final remaining = total - offset;
          final thisLen = remaining > _chunkSize ? _chunkSize : remaining;
          final bytes = await raf.read(thisLen);
          if (bytes.isEmpty) {
            return (result: null, error: '上传失败: 文件读取为空');
          }
          final r = await _sendChunkWithRetry(
              dio, uploadId, offset, bytes, contentType, total, onProgress);
          if (r.error != null) return (result: null, error: r.error);
          final advanced = r.offset!;
          if (advanced <= offset) {
            return (result: null, error: '上传中断: 服务端进度未推进');
          }
          offset = advanced; // 以服务端 offset 推进,自愈字节漂移
        }
      } finally {
        await raf.close();
      }
      final res = await withRetry(
        () => dio.post('/upload/complete',
            data: {
              'upload_id': uploadId,
              'filename': filename,
              'mime_type': contentType,
            },
            options: Options(
                headers: {..._authHeaders, 'Content-Type': 'application/json'})),
        isTransient: isTransientDioError,
        maxAttempts: 3,
        delayFor: (i) => Duration(seconds: 1 << i),
      );
      if (res.statusCode == 200 && res.data is Map) {
        return (result: _resultFrom(res.data as Map), error: null);
      }
      return (result: null, error: '合并失败: HTTP ${res.statusCode}');
    } on DioException catch (e) {
      return (result: null, error: _uploadError(e));
    } catch (e) {
      return (result: null, error: '上传失败: $e');
    } finally {
      dio.close();
    }
  }

  /// 单块上传，失败时瞬态重试（probe 协调未知结局）。
  Future<({int? offset, String? error})> _sendChunkWithRetry(
      Dio dio, String uploadId, int offset, List<int> bytes,
      String contentType, int total, void Function(int, int)? onProgress) async {
    int attempt = 0;
    while (true) {
      try {
        final res = await dio.post('/upload/chunk',
            data: FormData.fromMap({
              'upload_id': uploadId,
              'offset': '$offset',
              'file': MultipartFile.fromBytes(bytes,
                  filename: 'chunk',
                  contentType: MediaType.parse(contentType)),
            }),
            options: Options(headers: _authHeaders),
            onSendProgress: (s, t) {
              if (onProgress != null) onProgress(offset + s, total);
            });
        if (res.statusCode != 200) {
          return (offset: null, error: '块上传失败: HTTP ${res.statusCode}');
        }
        final serverOffset = (res.data is Map)
            ? ((res.data as Map)['offset'] as num?)?.toInt()
            : null;
        final advanced = serverOffset ?? (offset + bytes.length);
        if (onProgress != null) onProgress(advanced, total);
        return (offset: advanced, error: null);
      } on DioException catch (e) {
        if (!isTransientDioError(e) || attempt >= _chunkMaxAttempts - 1) {
          return (offset: null, error: _uploadError(e));
        }
        // 超时/断连：该块可能已写入服务端。probe 真实 offset 后判定。
        final probe = await _probeChunkOffset(dio, uploadId);
        final probeErr = probe.error;
        final serverOffset = probe.offset;
        if (probeErr != null) {
          return (offset: null, error: probeErr);
        }
        if (serverOffset == null) {
          return (offset: null, error: '上传中断: 无法确认服务端进度');
        }
        switch (reconcileChunkAfterProbe(
            expectedOffset: offset,
            serverOffset: serverOffset,
            chunkLength: bytes.length)) {
          case ChunkProbeResult.skipChunk:
            if (onProgress != null) onProgress(serverOffset, total);
            return (offset: serverOffset, error: null);
          case ChunkProbeResult.abort:
            return (offset: null, error: '上传中断: 服务端分块进度异常,请重试');
          case ChunkProbeResult.sendChunk:
            attempt++;
            await Future.delayed(Duration(seconds: 1 << attempt));
        }
      }
    }
  }

  /// 0 字节块 probe：服务端对空块不追加，仅返回当前 .part 大小（真实 offset）。
  Future<({int? offset, String? error})> _probeChunkOffset(
      Dio dio, String uploadId) async {
    try {
      final res = await dio.post('/upload/chunk',
          data: FormData.fromMap({
            'upload_id': uploadId,
            'offset': '-1',
            'file': MultipartFile.fromBytes(const [],
                filename: 'probe',
                contentType: MediaType.parse('application/octet-stream')),
          }),
          options: Options(headers: _authHeaders));
      if (res.statusCode == 200 && res.data is Map) {
        final o = (res.data as Map)['offset'];
        return (offset: (o as num?)?.toInt(), error: null);
      }
      return (offset: null, error: '探测分块进度失败: HTTP ${res.statusCode}');
    } on DioException catch (e) {
      return (offset: null, error: _uploadError(e));
    }
  }

  /// 拉历史。since/before 为整数 id（可空）。limit 默认 50（最近消息足够）。
  Future<HistoryResult> fetchHistory({int? since, int? before, int limit = 50}) async {
    try {
      return await withRetry<HistoryResult>(
        () async {
          final dio = Dio(BaseOptions(
            connectTimeout: const Duration(seconds: 15),
            receiveTimeout: const Duration(seconds: 30),
          ));
          final q = <String, dynamic>{'limit': limit};
          if (since != null) q['since'] = since;
          if (before != null) q['before'] = before;
          if (sessionId.isNotEmpty && sessionId != kDefaultSessionId) {
            q['session_id'] = sessionId;
          }
          final res = await dio.get('$_base/history',
              queryParameters: q, options: Options(headers: _authHeaders));
          if (res.statusCode == 200 && res.data is Map) {
            final m = res.data as Map<String, dynamic>;
            final list = (m['messages'] as List?) ?? [];
            return HistoryResult(
              messages: list
                  .map((e) => HistoryRow.fromJson(
                      Map<String, dynamic>.from(e as Map)))
                  .toList(),
              hasMore: (m['has_more'] as bool?) ?? false,
            );
          }
          if (res.statusCode == 401) return const HistoryResult(messages: [], hasMore: false);
          throw DioException(
            requestOptions: res.requestOptions,
            type: DioExceptionType.badResponse,
            response: res,
          );
        },
        isTransient: (e) {
          if (e is DioException) {
            return e.type == DioExceptionType.connectionError ||
                e.type == DioExceptionType.connectionTimeout ||
                e.type == DioExceptionType.receiveTimeout ||
                e.type == DioExceptionType.sendTimeout ||
                e.type == DioExceptionType.badResponse;
          }
          return false;
        },
        maxAttempts: 4,
        delayFor: (i) => Duration(seconds: 1 << i),
      );
    } catch (_) {
      return const HistoryResult(messages: [], hasMore: false);
    }
  }

  /// 规整下载 URL：服务端 file 事件的 url 可能是相对路径（如 /files/xxx），
  /// dio 无法解析 host 会 connectionError。相对路径拼 serverUrl 的 origin。
  String _resolveUrl(String url) => resolveMediaUrl(url, serverUrl);

  /// 下载媒体 URL（单次有效，带认证）。写入 attachments 目录，返回本地 File。
  /// 流式写入文件，避免一次性 bytes 把大文件读入内存 OOM/超 receiveTimeout。
  ///
  /// 质量加固：先写 `name.part`，中断后保留部分文件；同 URL 再次下载时带
  /// `Range: bytes=<已收>-` 续传（服务端支持则 206 续传，忽略 Range 返回 200
  /// 则截断重写），瞬态失败自动重试，全失败把 .part 留给下次续传而非删除。
  /// [onProgress]：`(received, total)`，total 为服务端可确定的文件总长，未知为 null。
  Future<File?> downloadByUrl(String url,
      {void Function(int received, int? total)? onProgress}) async {
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      sendTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(minutes: 10),
    ));
    try {
      final dir = await getApplicationDocumentsDirectory();
      final cacheDir = Directory('${dir.path}/attachments');
      if (!await cacheDir.exists()) await cacheDir.create(recursive: true);
      final absUrl = _resolveUrl(url);
      final tail = Uri.parse(absUrl).pathSegments.isNotEmpty
          ? Uri.parse(absUrl).pathSegments.last
          : '';
      final name = (tail.isEmpty
              ? DateTime.now().millisecondsSinceEpoch.toString()
              : tail)
          .replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
      final finalFile = File('${cacheDir.path}/$name');
      if (await finalFile.exists() && await finalFile.length() > 0) {
        return finalFile; // 已完整下载过
      }
      final partFile = File('${cacheDir.path}/$name.part');
      try {
        return await withRetry(
          () => _streamDownloadInto(
              dio, partFile, absUrl, finalFile, onProgress),
          isTransient: isTransientDioError,
          maxAttempts: 3,
          delayFor: (i) => Duration(seconds: 1 << i),
        );
      } catch (_) {
        // 重试耗尽仍失败：保留 .part 供下次触发续传（不删除，不清 0）。
        return null;
      }
    } catch (_) {
      return null;
    } finally {
      dio.close();
    }
  }

  /// 单次「GET + 流写入 .part」：自带 Range 续传/截断重写/416 收尾与完成判定。
  /// 瞬态异常向上抛给外层 withRetry；本方法每次重入都按 .part 当前长度续传。
  Future<File> _streamDownloadInto(
      Dio dio, File part, String absUrl, File finalFile,
      void Function(int received, int? total)? onProgress) async {
    final start = await part.length();
    final headers = <String, String>{..._authHeaders};
    if (start > 0) headers['Range'] = 'bytes=$start-';
    Response<ResponseBody> res;
    try {
      res = await dio.get<ResponseBody>(absUrl,
          options: Options(responseType: ResponseType.stream, headers: headers));
    } on DioException {
      rethrow; // 交给外层 withRetry 判定瞬态
    }

    if (res.statusCode == 416) {
      // Range 与服务端冲突：部分文件可能已收全（中断残留在改名前的边界）。
      final total =
          parseContentRangeTotal(res.headers.value('content-range'));
      await res.data?.stream.listen(null).cancel();
      if (decideRange416(partLength: start, serverTotal: total) ==
          PartRangeDecision.complete) {
        await _renamePartToFinal(part, finalFile);
        return finalFile;
      }
      if (await part.exists()) await part.delete();
      return _streamDownloadInto(dio, part, absUrl, finalFile, onProgress);
    }

    final ct = res.headers.value('content-type') ?? '';
    if (res.statusCode != 200 && res.statusCode != 206) {
      await res.data?.stream.listen(null).cancel();
      throw DioException(
        requestOptions: res.requestOptions,
        type: DioExceptionType.badResponse,
        response: res,
      );
    }
    if (res.statusCode == 200 && ct.contains('application/json')) {
      // 过期/失效链接：非瞬态，直接放弃。
      await res.data?.stream.listen(null).cancel();
      throw DioException(
        requestOptions: res.requestOptions,
        type: DioExceptionType.badResponse,
        message: 'bad media response',
      );
    }

    // 期望总长：
    // - 206：Content-Range 的 total 是真值；缺失时退化为 start + content-length；
    // - 200：服务端忽略 Range 返回全量，content-length 就是总长（不是 start+它）。
    int expectedTotal = 0;
    bool totalKnown = false;
    final cl = int.tryParse(res.headers.value('content-length') ?? '');
    if (res.statusCode == 206) {
      final cr = parseContentRangeTotal(res.headers.value('content-range'));
      if (cr != null) {
        expectedTotal = cr;
        totalKnown = true;
      } else if (cl != null) {
        expectedTotal = start + cl;
        totalKnown = true;
      }
    } else if (cl != null) {
      expectedTotal = cl;
      totalKnown = true;
    }

    // 服务端忽略 Range 返回 200 全量：openWrite(writeOnly) 已截断 .part 从头写。
    final append = res.statusCode == 206;
    final sink = part.openWrite(
        mode: append ? FileMode.writeOnlyAppend : FileMode.writeOnly);
    int received = 0;
    try {
      await for (final chunk in res.data!.stream) {
        sink.add(chunk);
        received += chunk.length;
      }
      await sink.flush();
    } finally {
      await sink.close();
    }
    if (onProgress != null && (received > 0 || !totalKnown)) {
      onProgress(start + received, totalKnown ? expectedTotal : null);
    }

    final partLen = await part.length();
    final done = totalKnown ? partLen >= expectedTotal : received > 0;
    if (!done) {
      // 拿了部分字节但未达目标：保留 .part，抛瞬态类异常触发外层重试。
      throw DioException(
        requestOptions: res.requestOptions,
        type: DioExceptionType.receiveTimeout,
        message:
            '下载未完成 (len=$partLen, total=${totalKnown ? expectedTotal : "?"})',
      );
    }
    await _renamePartToFinal(part, finalFile);
    return finalFile;
  }

  Future<void> _renamePartToFinal(File part, File finalFile) async {
    if (await finalFile.exists()) await finalFile.delete();
    await part.rename(finalFile.path);
  }

  /// 清理 7 天前的附件缓存（botapi 媒体单次有效，本地缓存即下载文件）。
  static Future<void> cleanOldCache() async {
    final dir = await getApplicationDocumentsDirectory();
    final cacheDir = Directory('${dir.path}/attachments');
    if (!await cacheDir.exists()) return;
    final cutoff = DateTime.now().subtract(const Duration(days: 7));
    await for (final e in cacheDir.list()) {
      if (e is File) {
        final stat = await e.stat();
        if (stat.modified.isBefore(cutoff)) await e.delete();
      }
    }
  }
}
