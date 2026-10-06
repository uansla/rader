import 'dart:async';
import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

/// Offline Matcha Icefall zh-Baker TTS backend for Windows.
///
/// The native sherpa-onnx bindings are initialized inside the worker isolate,
/// as required by sherpa-onnx. The worker returns PCM as a WAV byte buffer so
/// the existing Reader audio playback path can be reused.
class MatchaTts {
  Isolate? _worker;
  SendPort? _toWorker;
  final Map<int, Completer<dynamic>> _pending = <int, Completer<dynamic>>{};
  int _nextId = 0;
  bool _ready = false;

  Future<bool> init({
    required String acousticModelPath,
    required String vocoderPath,
    required String lexiconPath,
    required String tokensPath,
    required String ruleFsts,
    int numThreads = 2,
  }) async {
    if (_ready) return true;

    final handshake = ReceivePort();
    _worker = await Isolate.spawn(_workerEntry, handshake.sendPort);

    final gotWorkerPort = Completer<SendPort>();
    handshake.listen((message) {
      if (message is SendPort) {
        if (!gotWorkerPort.isCompleted) gotWorkerPort.complete(message);
      } else {
        _onMessage(message);
      }
    });

    _toWorker = await gotWorkerPort.future;
    final ok = await _request<bool>('init', <String, dynamic>{
      'acousticModel': acousticModelPath,
      'vocoder': vocoderPath,
      'lexicon': lexiconPath,
      'tokens': tokensPath,
      'ruleFsts': ruleFsts,
      'numThreads': numThreads,
    });
    _ready = ok ?? false;
    return _ready;
  }

  bool get ready => _ready;

  Future<Uint8List> synthesize(
    String text, {
    double speed = 1.0,
  }) async {
    if (!_ready || _worker == null) return Uint8List(0);
    final wav = await _request<Uint8List>('synth', <String, dynamic>{
      'text': text,
      'speed': speed,
    });
    return wav ?? Uint8List(0);
  }

  Future<bool> selfTest() async {
    final wav = await synthesize(
      '这是一段普通话离线语音测试。欢迎使用 Reader 阅读器。',
    );
    return wav.length > 44;
  }

  void dispose() {
    _worker?.kill(priority: Isolate.immediate);
    _worker = null;
    _toWorker = null;
    _ready = false;
    _pending.clear();
  }

  Future<T?> _request<T>(String command, Map<String, dynamic> payload) async {
    if (_toWorker == null) return null;
    final id = _nextId++;
    final completer = Completer<T>();
    _pending[id] = completer;
    _toWorker!.send(<String, dynamic>{
      'cmd': command,
      'id': id,
      ...payload,
    });
    return completer.future;
  }

  void _onMessage(dynamic message) {
    if (message is Map && message['id'] is int) {
      final completer = _pending.remove(message['id']);
      if (completer != null) {
        completer.complete(message['result']);
      }
    }
  }

  static void _workerEntry(SendPort mainPort) {
    final receive = ReceivePort();
    mainPort.send(receive.sendPort);

    final worker = _MatchaWorker();
    receive.listen((message) {
      if (message is! Map) return;
      final id = message['id'];
      final command = message['cmd'];

      dynamic result;
      switch (command) {
        case 'init':
          result = worker.init(
            message['acousticModel'] as String,
            message['vocoder'] as String,
            message['lexicon'] as String,
            message['tokens'] as String,
            message['ruleFsts'] as String,
            message['numThreads'] as int? ?? 2,
          );
          break;
        case 'synth':
          result = worker.synthesize(
            message['text'] as String,
            (message['speed'] as num?)?.toDouble() ?? 1.0,
          );
          break;
      }

      mainPort.send(<String, dynamic>{'id': id, 'result': result});
    });
  }
}

class _MatchaWorker {
  sherpa.OfflineTts? _tts;

  bool init(
    String acousticModel,
    String vocoder,
    String lexicon,
    String tokens,
    String ruleFsts,
    int numThreads,
  ) {
    try {
      sherpa.initBindings();

      final matcha = sherpa.OfflineTtsMatchaModelConfig(
        acousticModel: acousticModel,
        vocoder: vocoder,
        lexicon: lexicon,
        tokens: tokens,
      );

      final model = sherpa.OfflineTtsModelConfig(
        matcha: matcha,
        numThreads: numThreads,
        debug: false,
        provider: 'cpu',
      );

      final config = sherpa.OfflineTtsConfig(
        model: model,
        ruleFsts: ruleFsts,
        maxNumSenetences: 1,
      );

      final tts = sherpa.OfflineTts(config);
      if (tts.sampleRate <= 0) {
        tts.free();
        return false;
      }

      _tts = tts;
      return true;
    } catch (_) {
      return false;
    }
  }

  Uint8List synthesize(String text, double speed) {
    final tts = _tts;
    if (tts == null) return Uint8List(0);

    try {
      final audio = tts.generate(
        text: text,
        sid: 0,
        speed: speed <= 0 ? 1.0 : speed,
      );
      if (audio.samples.isEmpty || audio.sampleRate <= 0) {
        return Uint8List(0);
      }
      return _buildWav(audio.samples, audio.sampleRate);
    } catch (_) {
      return Uint8List(0);
    }
  }

  Uint8List _buildWav(Float32List samples, int sampleRate) {
    final dataSize = samples.length * 2;
    final builder = BytesBuilder();

    void ascii(String value) => builder.add(value.codeUnits);
    void u16(int value) {
      builder.add(<int>[value & 0xff, (value >> 8) & 0xff]);
    }
    void u32(int value) {
      builder.add(<int>[
        value & 0xff,
        (value >> 8) & 0xff,
        (value >> 16) & 0xff,
        (value >> 24) & 0xff,
      ]);
    }

    ascii('RIFF');
    u32(36 + dataSize);
    ascii('WAVE');
    ascii('fmt ');
    u32(16);
    u16(1);
    u16(1);
    u32(sampleRate);
    u32(sampleRate * 2);
    u16(2);
    u16(16);
    ascii('data');
    u32(dataSize);

    final pcm = ByteData(dataSize);
    for (var i = 0; i < samples.length; i++) {
      final sample = (samples[i] * 32767.0).round();
      final clamped = sample < -32768
          ? -32768
          : sample > 32767
              ? 32767
              : sample;
      pcm.setInt16(i * 2, clamped, Endian.little);
    }
    builder.add(pcm.buffer.asUint8List());
    return builder.toBytes();
  }
}
