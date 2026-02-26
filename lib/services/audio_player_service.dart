import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path/path.dart' as p;

/// 音频播放服务 - 提供语音消息的播放功能
class AudioPlayerService {
  AudioPlayerService();

  final AudioPlayer _player = AudioPlayer();
  
  /// 当前正在播放的文件路径
  String? _currentFilePath;
  
  /// 播放状态监听器
  final List<VoidCallback> _listeners = [];

  /// 当前播放状态
  bool get isPlaying => _player.playing;
  
  /// 当前播放的文件路径
  String? get currentFilePath => _currentFilePath;
  
  /// 当前播放位置（毫秒）
  Duration get position => _player.position;
  
  /// 音频总时长（毫秒）
  Duration? get duration => _player.duration;

  /// 初始化播放器
  Future<void> init() async {
    _player.playerStateStream.listen((state) {
      // 播放完成时重置状态
      if (state.processingState == ProcessingState.completed) {
        _currentFilePath = null;
        _notifyListeners();
      }
      _notifyListeners();
    });
  }

  /// 添加状态监听器
  void addListener(VoidCallback listener) {
    _listeners.add(listener);
  }

  /// 移除状态监听器
  void removeListener(VoidCallback listener) {
    _listeners.remove(listener);
  }

  void _notifyListeners() {
    for (final listener in _listeners) {
      listener();
    }
  }

  /// 播放指定路径的音频文件
  /// 如果是同一个文件，则切换播放/暂停状态
  Future<void> play(String filePath) async {
    try {
      // 检查文件是否存在
      final file = File(filePath);
      if (!await file.exists()) {
        debugPrint('[AudioPlayerService] 播放失败: 文件不存在 - $filePath');
        return;
      }

      // 检查文件大小
      final fileSize = await file.length();
      if (fileSize == 0) {
        debugPrint('[AudioPlayerService] 播放失败: 文件为空 - $filePath');
        return;
      }
      debugPrint('[AudioPlayerService] 播放文件: $filePath, 大小: $fileSize bytes');

      final ext = p.extension(filePath).toLowerCase();
      if (fileSize >= 4) {
        final headerBytes = await file.openRead(0, 4).first;
        final header = String.fromCharCodes(headerBytes);
        if (ext == '.m4a' && header == 'RIFF') {
          debugPrint(
            '[AudioPlayerService] 扩展名(.m4a)与文件内容(RIFF/WAV)不一致，iOS 播放可能报 -11829',
          );
        }
      }

      // 如果是同一个文件，切换播放/暂停
      if (_currentFilePath == filePath) {
        if (_player.playing) {
          await _player.pause();
        } else {
          await _player.play();
        }
        return;
      }

      // 播放新文件
      _currentFilePath = filePath;
      await _player.setFilePath(filePath);
      await _player.play();
      debugPrint('[AudioPlayerService] 开始播放音频: $filePath');
    } catch (e) {
      debugPrint('[AudioPlayerService] 播放音频失败: $e');
      debugPrint('[AudioPlayerService] 错误详情: 文件路径=$filePath');
      _currentFilePath = null;
    }
  }

  /// 暂停播放
  Future<void> pause() async {
    await _player.pause();
  }

  /// 停止播放
  Future<void> stop() async {
    await _player.stop();
    _currentFilePath = null;
  }

  /// 跳转到指定位置
  Future<void> seek(Duration position) async {
    await _player.seek(position);
  }

  /// 释放资源
  Future<void> dispose() async {
    await _player.dispose();
    _listeners.clear();
  }
}
