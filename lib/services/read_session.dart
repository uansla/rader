import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/repositories.dart';

/// 阅读会话计时：进入阅读器后每分钟累加一次阅读时长，
/// 同时写入 read_daily（供日历热力图 / 连续打卡使用）。
/// 达到设定的连续阅读时长后触发护眼提醒。
class ReadSession {
  final int bookId;
  final BookRepository _books;
  final ReadDailyRepository _daily;

  Timer? _ticker;
  int _elapsedMinutes = 0;
  bool _disposed = false;

  /// 连续阅读多少分钟后提醒休息（默认 45）。
  final int eyeRestMinutes;
  final VoidCallback? onEyeRest;

  ReadSession({
    required this.bookId,
    required BookRepository books,
    required ReadDailyRepository daily,
    this.eyeRestMinutes = 45,
    this.onEyeRest,
  })  : _books = books, // ignore: prefer_initializing_formals
        _daily = daily { // ignore: prefer_initializing_formals
    _ticker = Timer.periodic(const Duration(minutes: 1), (_) => _tick());
  }

  void _tick() {
    if (_disposed) return;
    _elapsedMinutes++;
    final now = DateTime.now();
    _books.addReadMinutes(bookId, 1);
    _daily.addMinutes(now, 1);
    if (_elapsedMinutes == eyeRestMinutes && onEyeRest != null) {
      onEyeRest!();
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _ticker?.cancel();
  }
}

/// 睡眠定时：倒计时结束后执行回调（暂停朗读 / 返回书架）。
class SleepTimer {
  Timer? _timer;
  Duration? remaining;
  final VoidCallback onExpire;
  final Duration Function(Duration) _tickTransform;

  SleepTimer(this.onExpire, {Duration Function(Duration)? tickTransform})
      : _tickTransform = tickTransform ?? _defaultTick;

  static Duration _defaultTick(Duration d) =>
      d - const Duration(seconds: 1);

  bool get active => _timer != null;

  void start(Duration total) {
    stop();
    remaining = total;
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (remaining == null) return;
      remaining = _tickTransform(remaining!);
      if (remaining!.inSeconds <= 0) {
        t.cancel();
        _timer = null;
        remaining = null;
        onExpire();
      }
    });
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    remaining = null;
  }

  void dispose() => stop();
}
