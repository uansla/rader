import 'dart:async';

import 'package:just_audio/just_audio.dart';

class AudioPlaybackService {
  final AudioPlayer _player = AudioPlayer();
  Future<void> _loadChain = Future.value();

  Stream<Duration> get positionStream => _player.positionStream;
  Stream<Duration?> get durationStream => _player.durationStream;
  Stream<PlayerState> get playerStateStream => _player.playerStateStream;
  AudioPlayer get player => _player;

  Future<void> playFile(String path) {
    // 每个操作独立执行；失败/异常不阻塞后续操作。
    // 不显式 stop()：setFilePath 会自动停掉当前音源再加载新音源，
    // 避免在 completed 状态下 stop→play 的边界问题。
    final op = _loadChain.then((_) async {
      try {
        await _player.setFilePath(path);
        await _player.play();
      } catch (_) {}
    });
    _loadChain = op.catchError((_) {});
    return op;
  }

  Future<void> play() => _player.play();
  Future<void> pause() => _player.pause();
  Future<void> stop() => _player.stop();
  Future<void> seek(Duration position) => _player.seek(position);
  Future<void> setSpeed(double speed) => _player.setSpeed(speed);

  bool get isPlaying => _player.playing;

  Duration get currentPosition => _player.position;
  Duration? get duration => _player.duration;

  Future<void> dispose() async {
    await _player.dispose();
  }
}
