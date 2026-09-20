import 'dart:async';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models/book.dart';
import '../models/chapter.dart';

class PlayerScreen extends StatefulWidget {
  final Book book;
  const PlayerScreen({super.key, required this.book});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  late final AppState _state;
  List<Chapter> _chapters = [];
  bool _loading = true;
  int _track = 0;
  double _speed = 1.0;
  bool _playing = false;
  bool _completed = false;
  Duration _position = Duration.zero;
  Duration? _duration;
  Timer? _sleepTimer;
  Duration? _sleepRemaining;
  Timer? _saveTimer;
  Timer? _listenTimer;
  StreamSubscription<PlayerState>? _stateSub;
  StreamSubscription<Duration>? _posSub;
  StreamSubscription<Duration?>? _durSub;
  bool _changingTrack = false;

  @override
  void initState() {
    super.initState();
    _state = context.read<AppState>();
    _track = widget.book.chapterIndex.clamp(0, 100000);
    _load();
    _listenTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      _state.bookRepo.addReadMinutes(widget.book.id!, 1);
      _state.readDailyRepo.addMinutes(DateTime.now(), 1);
    });
    _stateSub = _state.audio.playerStateStream.listen((s) {
      if (!mounted) return;
      setState(() {
        _playing = s.playing;
        _completed = s.processingState == ProcessingState.completed;
      });
      if (s.processingState == ProcessingState.completed) {
        _next();
      }    });
    _posSub = _state.audio.positionStream.listen((d) {
      if (!mounted) return;
      setState(() => _position = d);
      _scheduleSave();
    });
    _durSub = _state.audio.durationStream.listen((d) {
      if (!mounted) return;
      setState(() => _duration = d);
    });
  }

  Future<void> _load() async {
    _chapters = await _state.chapterRepo.getForBook(widget.book.id!);
    if (!mounted) return;
    setState(() => _loading = false);
    if (_chapters.isNotEmpty) {
      _track = widget.book.chapterIndex.clamp(0, _chapters.length - 1);
      final pos = widget.book.position;
      await _playTrack(_track,
          resume: widget.book.lastReadAt != null ? Duration(milliseconds: pos) : Duration.zero);
    }
  }

  @override
  void dispose() {
    _sleepTimer?.cancel();
    _saveTimer?.cancel();
    _listenTimer?.cancel();
    _stateSub?.cancel();
    _posSub?.cancel();
    _durSub?.cancel();
    _state.audio.pause();
    _saveNow();
    super.dispose();
  }

  Future<void> _playTrack(int idx, {Duration resume = Duration.zero}) async {
    if (_changingTrack) return;
    if (idx < 0 || idx >= _chapters.length) return;
    _changingTrack = true;
    try {
      setState(() {
        _track = idx;
        _playing = true;
        _completed = false;
      });
      _state.recordHistory(widget.book.id!,
          action: 'listen', chapterIdx: idx, position: resume.inMilliseconds);
      // 加超时保护：即使 just_audio 在极少数情况下挂起，
      // 也会在超时后继续执行 finally，避免 _changingTrack 永远卡死导致切歌失效。
      await _state.audio
          .playFile(_chapters[idx].filePath!)
          .timeout(const Duration(seconds: 8), onTimeout: () {});
      if (resume > Duration.zero) {
        await _state.audio.seek(resume);
      }
    } finally {
      _changingTrack = false;
    }
  }

  Future<void> _togglePlay() async {
    final audio = _state.audio;
    if (audio.isPlaying) {
      await audio.pause();
    } else {
      if (_completed) {
        await _playTrack(_track);
      } else {
        await audio.play();
      }
    }
    setState(() {});
  }

  Future<void> _next() async {
    if (_track < _chapters.length - 1) {
      await _playTrack(_track + 1);
    }
  }

  Future<void> _prev() async {
    if (_position.inSeconds > 5) {
      await _state.audio.seek(Duration.zero);
    } else if (_track > 0) {
      await _playTrack(_track - 1);
    }
  }

  Future<void> _setSpeed(double s) async {
    setState(() => _speed = s);
    await _state.audio.setSpeed(s);
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 2), _saveNow);
  }

  void _saveNow() {
    final overall = _chapters.isEmpty
        ? 0.0
        : ((_track + (_duration == null || _duration!.inMilliseconds == 0
                ? 0
                : _position.inMilliseconds / _duration!.inMilliseconds)) /
            _chapters.length).clamp(0.0, 1.0);
    _state.updateProgress(
      widget.book,
      chapterIdx: _track,
      position: _position.inMilliseconds,
      progress: overall,
    );
  }

  void _startSleepTimer(Duration d) {
    _sleepTimer?.cancel();
    _sleepRemaining = d;
    _sleepTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() => _sleepRemaining = _sleepRemaining! - const Duration(seconds: 1));
      if (_sleepRemaining!.inSeconds <= 0) {
        t.cancel();
        _state.audio.pause();
        setState(() {
          _sleepRemaining = null;
          _playing = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('定时关闭已生效')),
        );
      }
    });
  }

  void _showSleepDialog() {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
                title: const Text('15 分钟后'), onTap: () { _startSleepTimer(const Duration(minutes: 15)); Navigator.pop(ctx); }),
            ListTile(
                title: const Text('30 分钟后'), onTap: () { _startSleepTimer(const Duration(minutes: 30)); Navigator.pop(ctx); }),
            ListTile(
                title: const Text('60 分钟后'), onTap: () { _startSleepTimer(const Duration(minutes: 60)); Navigator.pop(ctx); }),
            ListTile(
                title: const Text('本集结束'), onTap: () { _startSleepTimer(const Duration(hours: 24)); Navigator.pop(ctx); }),
            if (_sleepRemaining != null)
              ListTile(
                  title: const Text('取消定时'),
                  onTap: () { _sleepTimer?.cancel(); setState(() => _sleepRemaining = null); Navigator.pop(ctx); }),
          ],
        ),
      ),
    );
  }

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    return h > 0
        ? '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}'
        : '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Scaffold(
      appBar: AppBar(title: Text(widget.book.title)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: _chapters.length,
                    itemBuilder: (context, i) {
                      final ch = _chapters[i];
                      final active = i == _track;
                      return ListTile(
                        dense: true,
                        leading: Icon(
                          active ? Icons.play_circle : Icons.music_note,
                          color: active ? accent : null,
                        ),
                        title: Text(
                          ch.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: active ? accent : null,
                            fontWeight: active ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                        trailing: active && _playing
                            ? const Icon(Icons.equalizer, size: 18)
                            : null,
                        onTap: () => _playTrack(i),
                      );
                    },
                  ),
                ),
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Text(_fmt(_position),
                                style: Theme.of(context).textTheme.bodySmall),
                            Expanded(
                              child: Slider(
                                value: _duration == null || _duration!.inMilliseconds == 0
                                    ? 0
                                    : (_position.inMilliseconds /
                                            _duration!.inMilliseconds)
                                        .clamp(0.0, 1.0),
                                onChanged: (v) async {
                                  final d = _duration;
                                  if (d == null) return;
                                  final target = Duration(
                                      milliseconds: (d.inMilliseconds * v).round());
                                  await _state.audio.seek(target);
                                },
                                activeColor: accent,
                              ),
                            ),
                            Text(_fmt(_duration ?? Duration.zero),
                                style: Theme.of(context).textTheme.bodySmall),
                          ],
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.bedtime_outlined),
                              onPressed: _showSleepDialog,
                              tooltip: '定时关闭',
                            ),
                            const SizedBox(width: 12),
                            IconButton(
                              iconSize: 36,
                              icon: const Icon(Icons.skip_previous),
                              onPressed: _prev,
                              tooltip: '上一集',
                            ),
                            const SizedBox(width: 8),
                            IconButton.filled(
                              iconSize: 44,
                              icon: Icon(
                                  _playing ? Icons.pause : Icons.play_arrow),
                              onPressed: _togglePlay,
                              tooltip: _playing ? '暂停' : '播放',
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              iconSize: 36,
                              icon: const Icon(Icons.skip_next),
                              onPressed: _next,
                              tooltip: '下一集',
                            ),
                            const SizedBox(width: 12),
                            PopupMenuButton<double>(
                              initialValue: _speed,
                              onSelected: _setSpeed,
                              icon: Text('${_speed}x',
                                  style: Theme.of(context).textTheme.titleMedium),
                              tooltip: '倍速',
                              itemBuilder: (context) => [0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 3.0]
                                  .map((s) => PopupMenuItem(
                                        value: s,
                                        child: Text('${s}x'),
                                      ))
                                  .toList(),
                            ),
                          ],
                        ),
                        if (_sleepRemaining != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text('定时 ${_fmt(_sleepRemaining!)} 后关闭',
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: accent)),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
