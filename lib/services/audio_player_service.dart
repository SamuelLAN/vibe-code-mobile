import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

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

  /// æ­æ¾æå®è·¯å¾çé³é¢æä»¶
  /// å¦ææ¯åä¸ä¸ªæä»¶ï¼ååæ¢æ­æ¾/æåç¶æ
  Future<void> play(String filePath) async {
    try {
      // æ£æ¥æä»¶æ¯å¦å­å¨
      final file = File(filePath);
      if (!await file.exists()) {
        debugPrint('[AudioPlayerService] æ­æ¾å¤±è´¥: æä»¶ä¸å­å¨ - $filePath');
        return;
      }

      // æ£æ¥æä»¶å¤§å°
      final fileSize = await file.length();
      if (fileSize == 0) {
        debugPrint('[AudioPlayerService] æ­æ¾å¤±è´¥: æä»¶ä¸ºç©º - $filePath');
        return;
      }
      debugPrint('[AudioPlayerService] æ­æ¾æä»¶: $filePath, å¤§å°: $fileSize bytes');

      // å¦ææ¯åä¸ä¸ªæä»¶ï¼åæ¢æ­æ¾/æå
      if (_currentFilePath == filePath) {
        if (_player.playing) {
          await _player.pause();
        } else {
          await _player.play();
        }
        return;
      }

      // æ­æ¾æ°æä»¶
      _currentFilePath = filePath;
      await _player.setFilePath(filePath);
      await _player.play();
      debugPrint('[AudioPlayerService] å¼å§æ­æ¾é³é¢: $filePath');
    } catch (e) {
      debugPrint('[AudioPlayerService] æ­æ¾é³é¢å¤±è´¥: $e');
      debugPrint('[AudioPlayerService] éè¯¯è¯¦æ: æä»¶è·¯å¾=$filePath');
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
