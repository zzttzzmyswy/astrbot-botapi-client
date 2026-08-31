// lib/services/media_registry.dart
//
// 下载管理页的数据源：把「消息表中带本地路径的媒体」与「附件目录中孤立下载
// 文件」合并成统一条目列表（去重、过滤 .part 半成品、按时间倒序）。
// 纯逻辑 + 显式输入，便于单测；真实的目录遍历在 build 里做。

import 'dart:io';
import '../models/message.dart';

enum DownloadCategory { image, audio, file }

class DownloadEntry {
  final String name;
  final String path;
  final DownloadCategory category;
  final int createdAt; // epoch ms
  final String? sourceUrl; // attachmentId（消息来源时）
  final bool fromMessage;

  const DownloadEntry({
    required this.name,
    required this.path,
    required this.category,
    required this.createdAt,
    this.sourceUrl,
    this.fromMessage = false,
  });
}

DownloadCategory categoryForMsgType(String msgType) {
  switch (msgType) {
    case 'image':
    case 'photo':
      return DownloadCategory.image;
    case 'voice':
    case 'audio':
    case 'record':
      return DownloadCategory.audio;
    default:
      return DownloadCategory.file;
  }
}

DownloadCategory categoryForPath(String path) {
  final name = path.split('/').last.split('\\').last;
  final i = name.lastIndexOf('.');
  final ext = (i < 0 || i == name.length - 1) ? '' : name.substring(i + 1).toLowerCase();
  if (const {'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'heic'}
      .contains(ext)) {
    return DownloadCategory.image;
  }
  if (const {'m4a', 'aac', 'mp3', 'wav', 'ogg', 'opus', 'amr', 'silk'}
      .contains(ext)) {
    return DownloadCategory.audio;
  }
  return DownloadCategory.file;
}

/// 从消息（带 localPath）与附件目录合并构建下载条目：
/// - 消息行：文件必须仍存在（stat 失败视为缺失，跳过）；
/// - 附件目录：跳过 `.part`（续传半成品）与隐藏文件；未被任何消息 localPath
///   引用的文件作为孤立条目补录（历史消息已删/未落库的下载文件）。
class MediaRegistry {
  static Future<List<DownloadEntry>> build({
    required List<LocalMessage> messages,
    required Directory attachmentsDir,
  }) async {
    final entries = <DownloadEntry>[];

    for (final m in messages) {
      final p = m.localPath ?? '';
      if (p.isEmpty) continue;
      final f = File(p);
      if (!await f.exists()) continue; // 文件被清，消息保留（可重新下载）
      final fallback = p.split('/').last.split('\\').last;
      entries.add(DownloadEntry(
        name: m.msgType == 'file' ? (m.content ?? fallback) : fallback,
        path: p,
        category: categoryForMsgType(m.msgType),
        createdAt: m.createdAt,
        sourceUrl: m.attachmentId,
        fromMessage: true,
      ));
    }

    final referenced = entries.map((e) => e.path).toSet();
    if (await attachmentsDir.exists()) {
      await for (final e in attachmentsDir.list()) {
        if (e is! File) continue;
        final name = e.uri.pathSegments.isNotEmpty
            ? e.uri.pathSegments.last
            : e.path.split('/').last;
        if (name.isEmpty ||
            name.startsWith('.') ||
            name.endsWith('.part')) {
          continue; // 半成品/隐藏文件不展示
        }
        if (referenced.contains(e.path)) continue; // 已被消息引用
        final stat = await e.stat();
        final fallback = e.path;
        entries.add(DownloadEntry(
          name: name,
          path: e.path,
          category: categoryForPath(fallback),
          createdAt: stat.modified.millisecondsSinceEpoch,
        ));
      }
    }

    entries.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return entries;
  }
}