// lib/services/botapi_http.dart
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:http_parser/http_parser.dart';
import 'package:path_provider/path_provider.dart';
import '../models/history_row.dart';
import '../util/retry.dart';

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
class BotApiHttp {
  final String serverUrl;
  final String token;
  BotApiHttp({required this.serverUrl, required this.token});

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

  /// 上传文件。返回 (result, error):成功 error=null;失败 result=null 并附原因
  /// (413=服务端 nginx 拒绝大文件,超时,等),便于 UI 给用户明确提示。
  Future<({UploadResult? result, String? error})> uploadFile(
      File file, String contentType,
      {void Function(int sent, int total)? onProgress}) async {
    try {
      final filename = file.path.split('/').last;
      final dio = Dio(BaseOptions(
        baseUrl: _base,
        connectTimeout: const Duration(seconds: 15),
        // 大文件 + 服务端处理慢(接收 body 后保存/反压)需足够长的发送与接收时限。
        // sendTimeout 覆盖发送请求体(含服务端反压导致的发送停滞);receiveTimeout
        // 覆盖服务端处理完返回响应。各 30/10 min 覆盖慢网络与大文件场景。
        sendTimeout: const Duration(minutes: 30),
        receiveTimeout: const Duration(minutes: 10),
      ));
      final form = FormData.fromMap({
        'file': await MultipartFile.fromFile(file.path,
            filename: filename, contentType: MediaType.parse(contentType)),
      });
      final res = await dio.post('/upload',
          data: form, options: Options(headers: _authHeaders), onSendProgress: onProgress);
      if (res.statusCode == 200 && res.data is Map) {
        final m = res.data as Map<String, dynamic>;
        return (
          result: UploadResult(
            fileId: m['file_id'] as String,
            name: m['name'] as String,
            mimeType: (m['mime_type'] as String?) ?? 'application/octet-stream',
            size: (m['size'] as num).toInt(),
          ),
          error: null,
        );
      }
      return (result: null, error: '上传失败: HTTP ${res.statusCode}');
    } on DioException catch (e) {
      final sc = e.response?.statusCode;
      if (sc == 413) {
        return (
          result: null,
          error: '文件过大,服务端拒绝(413)。需在服务器 nginx 配置 '
              'client_max_body_size(如 200m)并 reload。'
        );
      }
      if (e.type == DioExceptionType.sendTimeout ||
          e.type == DioExceptionType.connectionTimeout) {
        return (result: null, error: '上传超时,网络过慢或文件过大');
      }
      return (result: null, error: '上传失败: ${e.type.name}');
    } catch (e) {
      return (result: null, error: '上传失败: $e');
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

  /// 下载媒体 URL（单次有效，免认证）。写入 attachments 目录，返回本地 File。
  /// 流式写入文件，避免一次性 bytes 把大文件读入内存 OOM/超 receiveTimeout。
  Future<File?> downloadByUrl(String url) async {
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(minutes: 10),
    ));
    Response<ResponseBody>? res;
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
      final path = '${cacheDir.path}/$name';
      final existing = File(path);
      if (await existing.exists() && await existing.length() > 0) return existing;

      res = await dio.get<ResponseBody>(absUrl,
          options: Options(responseType: ResponseType.stream));
      final ct = res.headers.value('content-type') ?? '';
      if (res.statusCode != 200 || ct.contains('application/json')) {
        await res.data?.stream.listen(null).cancel();
        return null;
      }
      final sink = existing.openWrite();
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
      if (received == 0) {
        if (await existing.exists()) await existing.delete();
        return null;
      }
      return existing;
    } catch (_) {
      // 流被中途打断:关 sink、删半成品文件,避免缓存残缺文件误导"已下载"。
      try {
        await res?.data?.stream.listen(null).cancel();
      } catch (_) {}
      return null;
    } finally {
      dio.close();
    }
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
