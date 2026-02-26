import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

/// 检测是否在 iOS 模拟器上
bool get isIOSSimulator {
  return !kIsWeb && Platform.isIOS &&
         defaultTargetPlatform == TargetPlatform.iOS;
}

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
    debugPrint('麦克风权限状态: $status');
    return status.isGranted;
  }

  /// 检查麦克风权限
  Future<bool> hasPermission() async {
    final status = await Permission.microphone.status;
    debugPrint('麦克风权限状态: $status');
    return status.isGranted;
  }

  /// 打开应用设置页面（需要用户手动开启权限）
  Future<bool> openSettings() async {
    return await openAppSettings();
  }

  /// 开始录音
  /// 返回录音文件路径
  Future<String?> startRecording() async {
    if (_isRecording) return _currentFilePath;

    debugPrint('开始录音...');

    // 检查权限
    if (!await hasPermission()) {
      // 在模拟器上，权限会被拒绝
      if (isIOSSimulator) {
        debugPrint('iOS 模拟器检测到，模拟器不支持真实录音功能');
        return null;
      }

      debugPrint('请求麦克风权限...');
      final granted = await requestPermission();
      if (!granted) {
        debugPrint('麦克风权限被拒绝');
        return null;
      }
    }
    debugPrint('麦克风权限已获取');

    // 创建录音文件路径
    final dir = await getApplicationDocumentsDirectory();
    final voiceDir = Directory(p.join(dir.path, 'voice'));
    if (!await voiceDir.exists()) {
      await voiceDir.create(recursive: true);
    }

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    _currentFilePath = p.join(voiceDir.path, 'voice_$timestamp.m4a');

    debugPrint('[AudioRecorder] å½é³æä»¶è·¯å¾: $_currentFilePath');
    debugPrint('[AudioRecorder] å¼å§å½é³, ä½¿ç¨ WAV æ ¼å¼ (PCM 16-bit, 16kHz, mono)');

    // å¼å§å½é³
    try {
      // ä½¿ç¨ WAV (PCM 16-bit) ç¼ç ä»¥ç¡®ä¿åç«¯è½å¤æ­£ç¡®æ­æ¾åè½¬å
      // 16kHz æ¯è¯­é³è¯å«æ åçéæ ·ç
      // mono (åå£°é) å¯¹è¯­é³è¯å«è¶³å¤ä¸æä»¶æ´å°
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 128000,
          sampleRate: 16000,
          numChannels: 1,
        ),
        path: _currentFilePath!,
      );

      _isRecording = true;
      debugPrint('[AudioRecorder] å½é³å·²å¼å§, isRecording: $_isRecording');
      return _currentFilePath;
    } catch (e) {
      debugPrint('[AudioRecorder] å¼å§å½é³å¤±è´¥: $e');
      return null;
    }
  }

  /// ä¸º iOS æ¨¡æå¨åå»ºæ¨¡æé³é¢æä»¶
  Future<String?> _createSimulatorAudioFile() async {
    final dir = await getApplicationDocumentsDirectory();
    final voiceDir = Directory(p.join(dir.path, 'voice'));
    if (!await voiceDir.exists()) {
      await voiceDir.create(recursive: true);
    }

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final filePath = p.join(voiceDir.path, 'voice_$timestamp.m4a');

    // åå»ºä¸ä¸ªææç WAV æä»¶ (åå«æå° PCM é³é¢æ°æ®)
    final file = File(filePath);
    final minimalWav = _getMinimalWavData();
    await file.writeAsBytes(minimalWav);

    _currentFilePath = filePath;
    _isRecording = true;

    debugPrint('[AudioRecorder] åå»ºæ¨¡æé³é¢æä»¶: $filePath, å¤§å°: ${minimalWav.length} bytes');
    return filePath;
  }

  /// çææå°ææç WAV æ°æ® (åå« PCM éé³)
  /// WAV æä»¶ç»æ: RIFF header + fmt chunk + data chunk
  List<int> _getMinimalWavData() {
    const sampleRate = 16000;
    const numChannels = 1;
    const bitsPerSample = 16;
    const byteRate = sampleRate * numChannels * bitsPerSample ~/ 8;
    const blockAlign = numChannels * bitsPerSample ~/ 8;
    const dataSize = sampleRate * 2; // 1 second of silence

    final wav = <int>[];

    // RIFF header
    wav.addAll([0x52, 0x49, 0x46, 0x46]); // "RIFF"
    final fileSize = 36 + dataSize;
    wav.addAll([
      fileSize & 0xFF,
      (fileSize >> 8) & 0xFF,
      (fileSize >> 16) & 0xFF,
      (fileSize >> 24) & 0xFF,
    ]);
    wav.addAll([0x57, 0x41, 0x56, 0x45]); // "WAVE"

    // fmt chunk
    wav.addAll([0x66, 0x6D, 0x74, 0x20]); // "fmt "
    wav.addAll([0x10, 0x00, 0x00, 0x00]); // chunk size = 16
    wav.addAll([0x01, 0x00]); // audio format = 1 (PCM)
    wav.addAll([numChannels & 0xFF]); // num channels
    wav.addAll([
      sampleRate & 0xFF,
      (sampleRate >> 8) & 0xFF,
      (sampleRate >> 16) & 0xFF,
      (sampleRate >> 24) & 0xFF,
    ]); // sample rate
    wav.addAll([
      byteRate & 0xFF,
      (byteRate >> 8) & 0xFF,
      (byteRate >> 16) & 0xFF,
      (byteRate >> 24) & 0xFF,
    ]); // byte rate
    wav.addAll([blockAlign & 0xFF, (blockAlign >> 8) & 0xFF]); // block align
    wav.addAll([bitsPerSample & 0xFF, (bitsPerSample >> 8) & 0xFF]); // bits per sample

    // data chunk
    wav.addAll([0x64, 0x61, 0x74, 0x61]); // "data"
    wav.addAll([
      dataSize & 0xFF,
      (dataSize >> 8) & 0xFF,
      (dataSize >> 16) & 0xFF,
      (dataSize >> 24) & 0xFF,
    ]);
    // PCM silence (16-bit samples of 0)
    wav.addAll(List<int>.filled(dataSize, 0x00));

    return wav;
  }

  /// åæ­¢å½é³
  /// è¿åå½é³æä»¶è·¯å¾
  Future<String?> stopRecording() async {
    if (!_isRecording) return null;

    debugPrint('[AudioRecorder] åæ­¢å½é³...');

    // å¦ææ¯æ¨¡æå¨ï¼ä¸è¦è°ç¨ recorder.stop()
    if (isIOSSimulator) {
      _isRecording = false;
      final resultPath = _currentFilePath;
      debugPrint('[AudioRecorder] æ¨¡æå¨å½é³æä»¶è·¯å¾: $resultPath');
      _currentFilePath = null;
      return resultPath;
    }

    final path = await _recorder.stop();
    _isRecording = false;

    final resultPath = path ?? _currentFilePath;

    // éªè¯å½é³æä»¶æææ§
    if (resultPath != null) {
      final file = File(resultPath);
      if (await file.exists()) {
        final fileSize = await file.length();
        final fileExt = p.extension(resultPath).toLowerCase();
        debugPrint('[AudioRecorder] å½é³å®æ, æä»¶è·¯å¾: $resultPath');
        debugPrint('[AudioRecorder] æä»¶æ©å±å: $fileExt, å¤§å°: $fileSize bytes');
        if (fileSize == 0) {
          debugPrint('[AudioRecorder] è­¦å: å½é³æä»¶ä¸ºç©º!');
        } else {
          // éªè¯æä»¶å¤´
          final bytes = await file.openRead(0, 4).first;
          final header = String.fromCharCodes(bytes);
          debugPrint('[AudioRecorder] æä»¶å¤´: $header (ææ: RIFF for WAV)');
        }
      } else {
        debugPrint('[AudioRecorder] è­¦å: å½é³æä»¶ä¸å­å¨: $resultPath');
      }
    }

    _currentFilePath = null;
    return resultPath;
  }

  /// åæ¶å½é³
  Future<void> cancelRecording() async {
    if (!_isRecording) return;

    debugPrint('[AudioRecorder] åæ¶å½é³...');

    // å¦ææ¯æ¨¡æå¨ï¼ç´æ¥æ¸çç¶æ
    if (isIOSSimulator) {
      _isRecording = false;
      if (_currentFilePath != null) {
        final file = File(_currentFilePath!);
        if (await file.exists()) {
          await file.delete();
          debugPrint('[AudioRecorder] å·²å é¤æ¨¡æå½é³æä»¶: $_currentFilePath');
        }
      }
      _currentFilePath = null;
      return;
    }

    await _recorder.stop();
    _isRecording = false;

    // å é¤ä¸´æ¶æä»¶
    if (_currentFilePath != null) {
      final file = File(_currentFilePath!);
      if (await file.exists()) {
        await file.delete();
        debugPrint('[AudioRecorder] å·²å é¤ä¸´æ¶å½é³æä»¶: $_currentFilePath');
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
