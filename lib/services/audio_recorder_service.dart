import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

/// 录音服务
class AudioRecorderService {
  AudioRecorderService();

  final AudioRecorder _recorder = AudioRecorder();
  String? _currentFilePath;
  bool _isRecording = false;

  bool get isRecording => _isRecording;
  String? get currentFilePath => _currentFilePath;

  /// 请求麦克风权限
  Future<bool> requestPermission() async {
    final status = await Permission.microphone.request();
    return status.isGranted;
  }

  /// 检查麦克风权限
  Future<bool> hasPermission() async {
    return await Permission.microphone.isGranted;
  }

  /// 开始录音
  /// 返回录音文件路径
  Future<String?> startRecording() async {
    if (_isRecording) return _currentFilePath;

    // 检查权限
    if (!await hasPermission()) {
      final granted = await requestPermission();
      if (!granted) return null;
    }

    // 创建录音文件路径
    final dir = await getApplicationDocumentsDirectory();
    final voiceDir = Directory(p.join(dir.path, 'voice'));
    if (!await voiceDir.exists()) {
      await voiceDir.create(recursive: true);
    }

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    _currentFilePath = p.join(voiceDir.path, 'voice_$timestamp.m4a');

    // 开始录音
    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 128000,
        sampleRate: 44100,
      ),
      path: _currentFilePath!,
    );

    _isRecording = true;
    return _currentFilePath;
  }

  /// 停止录音
  /// 返回录音文件路径
  Future<String?> stopRecording() async {
    if (!_isRecording) return null;

    final path = await _recorder.stop();
    _isRecording = false;

    final resultPath = path ?? _currentFilePath;
    _currentFilePath = null;
    
    return resultPath;
  }

  /// 取消录音
  Future<void> cancelRecording() async {
    if (!_isRecording) return;

    await _recorder.stop();
    _isRecording = false;

    // 删除临时文件
    if (_currentFilePath != null) {
      final file = File(_currentFilePath!);
      if (await file.exists()) {
        await file.delete();
      }
    }
    _currentFilePath = null;
  }

  /// 释放资源
  Future<void> dispose() async {
    if (_isRecording) {
      await _recorder.stop();
    }
    _recorder.dispose();
  }
}
