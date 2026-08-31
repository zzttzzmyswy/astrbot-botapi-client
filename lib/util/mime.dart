// lib/util/mime.dart
//
// MIME 推断集中放这里：发送媒体、重试发送、分享/打开文件共用同一张映射表，
// 避免散落在 bubble/panel/screen 的多份 switch 各自漂移。

String _ext(String path) {
  final name = path.split('/').last.split('\\').last;
  final i = name.lastIndexOf('.');
  if (i < 0 || i == name.length - 1) return '';
  return name.substring(i + 1).toLowerCase();
}

/// 由文件名/路径推断 MIME；无法识别返回 application/octet-stream。
String mimeForExtension(String path) {
  switch (_ext(path)) {
    case 'jpg':
    case 'jpeg':
      return 'image/jpeg';
    case 'png':
      return 'image/png';
    case 'gif':
      return 'image/gif';
    case 'webp':
      return 'image/webp';
    case 'm4a':
      return 'audio/mp4';
    case 'aac':
      return 'audio/aac';
    case 'mp3':
      return 'audio/mpeg';
    case 'wav':
      return 'audio/wav';
    case 'ogg':
    case 'opus':
      return 'audio/ogg';
    case 'mp4':
      return 'video/mp4';
    case 'pdf':
      return 'application/pdf';
    case 'txt':
      return 'text/plain';
    case 'doc':
      return 'application/msword';
    case 'docx':
      return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
    case 'xls':
      return 'application/vnd.ms-excel';
    case 'xlsx':
      return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
    case 'zip':
      return 'application/zip';
    default:
      return 'application/octet-stream';
  }
}

/// 媒体发送用 MIME：
/// - 语音按实际扩展名（新版 m4a → audio/mp4；老版 wav 保留 audio/wav）；
/// - 图片统一 image/jpeg；
/// - 其余回退 octet-stream（调用方如需更精确可在 pick 时自行传入）。
String mimeForMediaSend(String filePath, String msgType) {
  if (msgType == 'voice') {
    final m = mimeForExtension(filePath);
    if (m == 'audio/mp4' || m == 'audio/aac' || m == 'audio/mpeg') return m;
    return 'audio/wav';
  }
  if (msgType == 'image') return 'image/jpeg';
  return mimeForExtension(filePath);
}
