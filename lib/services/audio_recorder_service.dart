import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

/// 检测是否在 iOS 模拟器上
bool get isIOSSimulator {
  if (kIsWeb || !Platform.isIOS || defaultTargetPlatform != TargetPlatform.iOS) {
    return false;
  }

  // 真机和模拟器都会满足 Platform.isIOS，因此需要看 iOS Simulator 注入的环境变量。
  final env = Platform.environment;
  return env.containsKey('SIMULATOR_DEVICE_NAME') ||
      env.containsKey('SIMULATOR_UDID');
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

    if (isIOSSimulator) {
      debugPrint('iOS 模拟器不支持真实麦克风录音，生成模拟 WAV 文件用于调试');
      return _createSimulatorAudioFile();
    }

    // 检查权限
    if (!await hasPermission()) {
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

    final output = await _selectRecordingOutput();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    _currentFilePath = p.join(voiceDir.path, 'voice_$timestamp${output.extension}');

    debugPrint('[AudioRecorder] 录音文件路径: $_currentFilePath');
    debugPrint('[AudioRecorder] 开始录音，编码=${output.encoderLabel}, 声道=1');

    // 开始录音
    try {
      await _recorder.start(
        output.config,
        path: _currentFilePath!,
      );

      _isRecording = true;
      debugPrint('[AudioRecorder] 录音已开始, isRecording: $_isRecording');
      return _currentFilePath;
    } catch (e) {
      debugPrint('[AudioRecorder] 开始录音失败: $e');
      return null;
    }
  }

  /// 为 iOS 模拟器创建模拟音频文件
  Future<String?> _createSimulatorAudioFile() async {
    final dir = await getApplicationDocumentsDirectory();
    final voiceDir = Directory(p.join(dir.path, 'voice'));
    if (!await voiceDir.exists()) {
      await voiceDir.create(recursive: true);
    }

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final filePath = p.join(voiceDir.path, 'voice_$timestamp.wav');

    // 创建一个有效的 WAV 文件（包含最小 PCM 音频数据）
    final file = File(filePath);
    final minimalWav = _getMinimalWavData();
    await file.writeAsBytes(minimalWav);

    _currentFilePath = filePath;
    _isRecording = true;

    debugPrint('[AudioRecorder] 创建模拟音频文件: $filePath, 大小: ${minimalWav.length} bytes');
    return filePath;
  }

  /// 生成最小有效的 WAV 数据（包含 PCM 静音）
  /// WAV 文件结构: RIFF header + fmt chunk + data chunk
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

  /// 停止录音
  /// 返回录音文件路径
  Future<String?> stopRecording() async {
    if (!_isRecording) return null;

    debugPrint('[AudioRecorder] 停止录音...');

    // 如果是模拟器，不要调用 recorder.stop()
    if (isIOSSimulator) {
      _isRecording = false;
      final resultPath = _currentFilePath;
      debugPrint('[AudioRecorder] 模拟器录音文件路径: $resultPath');
      _currentFilePath = null;
      return resultPath;
    }

    final path = await _recorder.stop();
    _isRecording = false;

    final resultPath = path ?? _currentFilePath;

    // 验证录音文件有效性
    if (resultPath != null) {
      final file = File(resultPath);
      if (await file.exists()) {
        final fileSize = await file.length();
        final fileExt = p.extension(resultPath).toLowerCase();
        debugPrint('[AudioRecorder] 录音完成, 文件路径: $resultPath');
        debugPrint('[AudioRecorder] 文件扩展名: $fileExt, 大小: $fileSize bytes');
        if (fileSize == 0) {
          debugPrint('[AudioRecorder] 警告: 录音文件为空!');
        } else {
          await _logAudioFileSignature(file, fileExt);
        }
      } else {
        debugPrint('[AudioRecorder] 警告: 录音文件不存在: $resultPath');
      }
    }

    _currentFilePath = null;
    return resultPath;
  }

  /// 取消录音
  Future<void> cancelRecording() async {
    if (!_isRecording) return;

    debugPrint('[AudioRecorder] 取消录音...');

    // 如果是模拟器，直接清理状态
    if (isIOSSimulator) {
      _isRecording = false;
      if (_currentFilePath != null) {
        final file = File(_currentFilePath!);
        if (await file.exists()) {
          await file.delete();
          debugPrint('[AudioRecorder] 已删除模拟录音文件: $_currentFilePath');
        }
      }
      _currentFilePath = null;
      return;
    }

    await _recorder.stop();
    _isRecording = false;

    // 删除临时文件
    if (_currentFilePath != null) {
      final file = File(_currentFilePath!);
      if (await file.exists()) {
        await file.delete();
        debugPrint('[AudioRecorder] 已删除临时录音文件: $_currentFilePath');
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

  Future<_RecordingOutput> _selectRecordingOutput() async {
    // `record` 官方文档说明采样率/码率需要谨慎配置；iOS 上优先使用平台默认 AAC/M4A，兼容性更好。
    final preferAac = Platform.isIOS || Platform.isMacOS;
    if (preferAac && await _recorder.isEncoderSupported(AudioEncoder.aacLc)) {
      return const _RecordingOutput(
        extension: '.m4a',
        encoderLabel: 'aacLc (m4a)',
        config: RecordConfig(
          encoder: AudioEncoder.aacLc,
          numChannels: 1,
        ),
      );
    }

    if (await _recorder.isEncoderSupported(AudioEncoder.wav)) {
      return const _RecordingOutput(
        extension: '.wav',
        encoderLabel: 'wav (pcm16)',
        config: RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 16000,
          numChannels: 1,
        ),
      );
    }

    return const _RecordingOutput(
      extension: '.m4a',
      encoderLabel: 'aacLc fallback (m4a)',
      config: RecordConfig(
        encoder: AudioEncoder.aacLc,
        numChannels: 1,
      ),
    );
  }

  Future<void> _logAudioFileSignature(File file, String fileExt) async {
    final bytes = await file.openRead(0, 12).fold<List<int>>(<int>[], (acc, chunk) {
      if (acc.length >= 12) return acc;
      acc.addAll(chunk);
      if (acc.length > 12) {
        return acc.sublist(0, 12);
      }
      return acc;
    });
    final ascii = bytes.map((b) => (b >= 32 && b <= 126) ? String.fromCharCode(b) : '.').join();
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
    debugPrint('[AudioRecorder] 文件签名: ascii=$ascii hex=$hex');

    if (fileExt == '.wav' && bytes.length >= 4) {
      final header = String.fromCharCodes(bytes.take(4));
      debugPrint('[AudioRecorder] WAV 文件头校验: $header (期望 RIFF)');
    } else if (fileExt == '.m4a' && bytes.length >= 8) {
      final brand = String.fromCharCodes(bytes.skip(4).take(4));
      debugPrint('[AudioRecorder] M4A 文件头校验: offset4=$brand (常见为 ftyp)');
    }
  }
}

class _RecordingOutput {
  const _RecordingOutput({
    required this.extension,
    required this.encoderLabel,
    required this.config,
  });

  final String extension;
  final String encoderLabel;
  final RecordConfig config;
}
