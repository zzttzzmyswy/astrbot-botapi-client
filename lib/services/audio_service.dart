// lib/services/audio_service.dart
import 'dart:io';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'platform/permission_service.dart';

class AudioService {
  final _recorder = AudioRecorder();
  final _player = AudioPlayer();
  String? _recordingPath;
  final PermissionService _permission;

  AudioService(this._permission);

  Future<bool> hasPermission() async => _permission.hasMic();

  Future<void> startRecording() async {
    if (!await _permission.requestMic()) return; // 未授权不录
    final dir = await getTemporaryDirectory();
    // AAC-LC(m4a)：Android 原生 MediaCodec 编码，体积约为同采样率 WAV 的 1/20，
    // 长录音不再动辄几十 MB。单声道 64kbps 对语音足够，上传/试听均正常。
    _recordingPath = '${dir.path}/draft_record.m4a';
    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 64000,
        sampleRate: 44100,
        numChannels: 1,
      ),
      path: _recordingPath!,
    );
  }

  Future<File?> stopRecording() async {
    final path = await _recorder.stop();
    if (path != null && File(path).existsSync()) {
      return File(path);
    }
    return null;
  }

  /// 复用内部单一 recorder 暴露振幅流,避免调用方再 new 一个 AudioRecorder。
  Stream<Amplitude> amplitudeStream(Duration interval) {
    return _recorder.onAmplitudeChanged(interval);
  }

  Future<void> playFile(String path) async {
    await _player.play(DeviceFileSource(path));
  }

  Future<void> stopPlaying() async {
    await _player.stop();
  }

  Future<void> dispose() async {
    await _player.dispose();
    await _recorder.dispose();
  }
}
