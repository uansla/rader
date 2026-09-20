import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'embedded_tts.dart';
import 'neural_tts.dart';

/// 朗读服务，优先级：
/// 1. 系统语音引擎（flutter_tts，音质好、多音色）
/// 2. Piper 神经语音（华研女声，内嵌离线）
/// 3. espeak-ng 兜底（保证能读）
class TtsService {
  final FlutterTts _tts = FlutterTts();
  final AudioPlayer _fallbackPlayer = AudioPlayer();
  EmbeddedTts? _embedded;
  NeuralTts? _neural;
  bool _ready = false;
  bool _useSystem = false;
  bool _neuralReady = false;
  bool _embeddedReady = false;
  String? _dataPath;

  int _neuralToken = 0;
  Completer<void>? _cancelCompleter;
  bool _neuralRunning = false;

  /// 朗读自然结束（读完一段文本）时的回调，用于自动翻页继续读。
  void Function()? onFinished;

  /// 朗读进度回调：某句开始朗读时触发。
  /// [start]/[end] 为句子在朗读文本中的字符区间（相对偏移），
  /// [durationSeconds] 为该句音频时长。
  void Function(int start, int end, double durationSeconds)? onProgress;

  Future<void> init() async {
    if (_ready) return;
    _useSystem = await _checkSystemTts();
    if (_useSystem) {
      // 系统引擎读完一段文本后触发，用于自动翻页
      _tts.setCompletionHandler(() => onFinished?.call());
      // flutter_tts reports native word/range offsets. Forward them to the
      // reader so scrolling and the persistent reading position follow the
      // actual spoken location instead of only the manually scrolled location.
      _tts.setProgressHandler(
          (String text, int start, int end, String word) {
        onProgress?.call(start, end, 0);
      });
    }
    if (!_useSystem) {
      _neural = NeuralTts();
      final paths = await _resolvePaths();
      if (paths != null) {
        _dataPath = paths.dataPath;
        _neuralReady = await _neural!.init(
          modelPath: paths.modelPath,
          configPath: paths.modelConfigPath,
          dataPath: paths.dataPath,
        );
      }
      if (!_neuralReady) {
        _embedded = EmbeddedTts.tryLoad();
        if (_embedded != null && _dataPath != null) {
          _embeddedReady = _embedded!.init(_dataPath!);
        }
      }
    }
    _ready = true;
  }

  /// 是否有任一可用引擎。
  Future<bool> isAvailable() async {
    await init();
    return _useSystem || _neuralReady || _embeddedReady;
  }

  /// 系统是否有可用的中文语音引擎。
  Future<bool> _checkSystemTts() async {
    try {
      for (var i = 0; i < 4; i++) {
        final avail = await _tts.isLanguageAvailable('zh-CN');
        if (avail == 1) return true;
        await Future.delayed(const Duration(milliseconds: 500));
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<void> setLanguage(String lang) => _tts.setLanguage(lang);
  Future<void> setRate(double rate) => _tts.setSpeechRate(rate);
  Future<void> setPitch(double pitch) => _tts.setPitch(pitch);

  /// 朗读。成功返回 true。
  Future<bool> speak(String text) async {
    await init();
    if (_useSystem) {
      try {
        await _tts.stop();
        await _tts.speak(text).timeout(const Duration(seconds: 5));
        return true;
      } catch (_) {
        return false;
      }
    }
    if (_neuralReady) {
      _startNeural(text);
      return true;
    }
    if (_embeddedReady) {
      final wav = _embedded!.synthesize(text);
      if (wav.isNotEmpty) {
        try {
          final tmp = await _writeTempWav(wav);
          await _fallbackPlayer.stop();
          await _fallbackPlayer.setFilePath(tmp.path);
          await _fallbackPlayer.play();
          return true;
        } catch (_) {
          return false;
        }
      }
    }
    return false;
  }

  // ===== 神经语音 =====

  void _startNeural(String text) {
    _completeCancel();
    final token = ++_neuralToken;
    final cancel = Completer<void>();
    _cancelCompleter = cancel;
    _neuralRunning = true;
    _runNeural(text, token, cancel);
  }

  /// 安全完成并清空当前的取消信号，避免重复 complete 抛异常。
  void _completeCancel() {
    final c = _cancelCompleter;
    _cancelCompleter = null;
    if (c != null && !c.isCompleted) {
      c.complete();
    }
  }

  Future<void> _runNeural(String text, int token, Completer<void> cancel) async {
    final sentences = _splitSentences(text);
    var runningOffset = 0;
    for (final s in sentences) {
      if (token != _neuralToken) break;
      final wav = await _neural!.synthesize(s);
      if (wav.isEmpty) continue;
      if (token != _neuralToken) break;
      final duration = _wavDuration(wav);
      try {
        final tmp = await _writeTempWav(wav);
        await _fallbackPlayer.stop();
        await _fallbackPlayer.setFilePath(tmp.path);
        await _fallbackPlayer.play();
        // 报告句子区间，读者据此高亮当前朗读的整句
        onProgress?.call(runningOffset, runningOffset + s.length, duration);
        // 等待本句播放完成：轮询当前状态（避免错过 completed 事件卡死），
        // 带超时兜底保证每句必定前进。
        final waitUntil = DateTime.now()
            .add(Duration(seconds: (duration + 5).ceil()));
        while (token == _neuralToken) {
          final st = _fallbackPlayer.processingState;
          if (st == ProcessingState.completed || st == ProcessingState.idle) {
            break;
          }
          if (DateTime.now().isAfter(waitUntil)) break;
          await Future.delayed(const Duration(milliseconds: 100));
        }
      } catch (_) {
        // 播放异常继续下一句
      }
      runningOffset += s.length;
    }
    _neuralRunning = false;
    // 自然读完（未被 stop 打断）才触发自动翻页
    if (token == _neuralToken) {
      onFinished?.call();
    }
  }

  /// 从 WAV 字节估算时长（秒）。解析 data 块大小 / (采样率*2)。
  double _wavDuration(Uint8List wav) {
    try {
      if (wav.length < 44) return 0;
      final bytes = ByteData.sublistView(wav);
      final sampleRate = bytes.getUint32(24, Endian.little);
      final dataSize = bytes.getUint32(40, Endian.little);
      if (sampleRate <= 0) return 0;
      return dataSize / (sampleRate * 2.0);
    } catch (_) {
      return 0;
    }
  }

  bool get neuralRunning => _neuralRunning;

  /// 按句切分，每段不超过约 80 字。
  List<String> _splitSentences(String text) {
    final out = <String>[];
    final buf = StringBuffer();
    final breakers = RegExp(r'[。！？；，,.!?;]|\n');
    for (final ch in text.split('')) {
      buf.write(ch);
      if (breakers.hasMatch(ch) || buf.length >= 80) {
        final s = buf.toString().trim();
        if (s.isNotEmpty) out.add(s);
        buf.clear();
      }
    }
    final last = buf.toString().trim();
    if (last.isNotEmpty) out.add(last);
    return out;
  }

  // ===== 路径解析 =====

  Future<({String dataPath, String modelPath, String modelConfigPath})?>
      _resolvePaths() async {
    try {
      if (Platform.isAndroid) {
        final support = await getApplicationSupportDirectory();
        final dest = p.join(support.path, 'espeak-ng-data');
        await _copyNativeAssetDir('espeak-ng-data', dest);
        final modelPath = await _extractAssetFile(
            'assets/zh_CN-huayan-medium.onnx', 'zh_CN-huayan-medium.onnx',
            support.path);
        final modelConfigPath = await _extractAssetFile(
            'assets/zh_CN-huayan-medium.onnx.json',
            'zh_CN-huayan-medium.onnx.json', support.path);
        if (modelPath == null || modelConfigPath == null) return null;
        return (
          dataPath: p.join(support.path, 'espeak-ng-data'),
          modelPath: modelPath,
          modelConfigPath: modelConfigPath,
        );
      }
      if (Platform.isWindows) {
        final dir = File(Platform.resolvedExecutable).parent.path;
        final dataPath = p.join(dir, 'espeak-ng-data');
        final modelPath = p.join(dir, 'zh_CN-huayan-medium.onnx');
        final modelConfigPath = p.join(dir, 'zh_CN-huayan-medium.onnx.json');
        if (Directory(dataPath).existsSync() &&
            File(modelPath).existsSync() &&
            File(modelConfigPath).existsSync()) {
          return (
            dataPath: dataPath,
            modelPath: modelPath,
            modelConfigPath: modelConfigPath,
          );
        }
      }
    } catch (_) {}
    return null;
  }

  /// 用原生通道把 assets 里的 espeak-ng-data 拷贝到应用目录（绕开 Flutter 打包器）。
  Future<int> _copyNativeAssetDir(String src, String dest) async {
    try {
      const channel = MethodChannel('reader/multicast');
      final count = await channel
          .invokeMethod<int>('copyAssetDir', {'src': src, 'dst': dest});
      return count ?? 0;
    } catch (_) {
      return 0;
    }
  }

  Future<String?> _extractAssetFile(
      String asset, String fileName, String destParent) async {
    final data = await rootBundle.load(asset);
    final file = File(p.join(destParent, fileName));
    if (!file.existsSync()) {
      await file.writeAsBytes(data.buffer.asUint8List());
    }
    return file.path;
  }

  Future<File> _writeTempWav(Uint8List wav) async {
    final dir = await getTemporaryDirectory();
    final file = File(p.join(
        dir.path, 'reader_tts_${DateTime.now().millisecondsSinceEpoch}.wav'));
    await file.writeAsBytes(wav);
    return file;
  }

  // ===== 控制 =====

  Future<void> stop() async {
    // 递增 token 使正在运行的神经朗读循环失效
    _neuralToken++;
    _completeCancel();
    try {
      await _tts.stop();
    } catch (_) {}
    try {
      await _fallbackPlayer.stop();
    } catch (_) {}
  }

  Future<void> pause() async {
    try {
      await _tts.pause();
    } catch (_) {}
  }

  Future<void> resume() async {
    try {
      await _tts.speak('');
    } catch (_) {}
  }

  Future<void> dispose() async {
    _cancelCompleter?.complete();
    try {
      await _tts.stop();
    } catch (_) {}
    try {
      await _fallbackPlayer.dispose();
    } catch (_) {}
    _embedded?.dispose();
    _neural?.dispose();
  }
}
