import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

/// Piper 神经语音（华研女声），在后台 isolate 里做 ONNX 推理，
/// 避免合成耗时阻塞 UI。
///
/// 优先级：系统引擎 > 神经语音 > espeak 兜底。
class NeuralTts {
  Isolate? _worker;
  SendPort? _toWorker;
  final Map<int, Completer<dynamic>> _pending = {};
  int _nextId = 0;
  bool _ready = false;

  /// 初始化后台合成器。[modelPath]/[configPath]/[dataPath] 为设备文件路径。
  Future<bool> init({
    required String modelPath,
    required String configPath,
    required String dataPath,
  }) async {
    if (_ready) return true;
    final handshake = ReceivePort();
    _worker = await Isolate.spawn(_workerEntry, handshake.sendPort);
    final gotWorkerPort = Completer<SendPort>();
    handshake.listen((msg) {
      if (msg is SendPort) {
        if (!gotWorkerPort.isCompleted) gotWorkerPort.complete(msg);
      } else {
        _onMessage(msg);
      }
    });
    _toWorker = await gotWorkerPort.future;
    final ok = await _request<bool>(
        'init', {'model': modelPath, 'config': configPath, 'data': dataPath});
    _ready = ok ?? false;
    return _ready;
  }

  bool get ready => _ready;

  /// 同步等待合成结果，返回 WAV 字节。
  Future<Uint8List> synthesize(String text) async {
    if (!_ready || _worker == null) return Uint8List(0);
    final wav = await _request<Uint8List>('synth', {'text': text});
    return wav ?? Uint8List(0);
  }

  void dispose() {
    _worker?.kill(priority: Isolate.immediate);
    _worker = null;
    _toWorker = null;
    _ready = false;
    _pending.clear();
  }

  Future<T?> _request<T>(String cmd, Map<String, dynamic> payload) async {
    if (_toWorker == null) return null;
    final id = _nextId++;
    final c = Completer<T>();
    _pending[id] = c;
    _toWorker!.send({'cmd': cmd, 'id': id, ...payload});
    return c.future;
  }

  void _onMessage(dynamic msg) {
    if (msg is Map && msg['id'] is int) {
      final c = _pending.remove(msg['id']);
      if (c != null) c.complete(msg['result']);
    }
  }
}

// ===== 后台 isolate =====

void _workerEntry(SendPort mainPort) {
  final receive = ReceivePort();
  mainPort.send(receive.sendPort);
  final impl = _NeuralWorker();
  receive.listen((msg) {
    if (msg is! Map) return;
    final id = msg['id'];
    final cmd = msg['cmd'];
    dynamic result;
    switch (cmd) {
      case 'init':
        result = impl.init(msg['model'], msg['config'], msg['data']);
        break;
      case 'synth':
        result = impl.synthesize(msg['text']);
        break;
    }
    mainPort.send({'id': id, 'result': result});
  });
}

// 后台 worker 内的 FFI 封装（不能跨 isolate 传 Pointer）。
class _NeuralWorker {
  Pointer<Void>? _handle;
  bool _ok = false;

  late final _InitDart _initFn;
  late final _SynthDart _synthFn;
  late final _FreeSamplesDart _freeFn;

  bool init(String modelPath, String configPath, String dataPath) {
    try {
      final DynamicLibrary lib;
      if (Platform.isAndroid) {
        lib = DynamicLibrary.open('libreader_tts.so');
      } else if (Platform.isWindows) {
        lib = DynamicLibrary.open('reader_tts.dll');
      } else {
        return false;
      }
      _initFn = lib.lookupFunction<_InitC, _InitDart>('reader_tts_init');
      _synthFn = lib.lookupFunction<_SynthC, _SynthDart>('reader_tts_synthesize');
      _freeFn =
          lib.lookupFunction<_FreeSamplesC, _FreeSamplesDart>('reader_tts_free_samples');

      final model = modelPath.toNativeUtf8();
      final cfg = configPath.toNativeUtf8();
      final data = dataPath.toNativeUtf8();
      _handle = _initFn(model, cfg, data).cast<Void>();
      calloc.free(model);
      calloc.free(cfg);
      calloc.free(data);
      _ok = _handle != nullptr;
      return _ok;
    } catch (_) {
      return false;
    }
  }

  Uint8List synthesize(String text) {
    if (!_ok || _handle == null) return Uint8List(0);
    try {
      final t = text.toNativeUtf8();
      final out = calloc<Pointer<Int16>>();
      final outLen = calloc<Int32>();
      final rate = calloc<Int32>();
      final ok = _synthFn(_handle!, t, out, outLen, rate);
      calloc.free(t);
      if (ok == 0) {
        calloc.free(out);
        calloc.free(outLen);
        calloc.free(rate);
        return Uint8List(0);
      }
      final n = outLen.value;
      final sr = rate.value;
      final samplesPtr = out.value;
      final samples = samplesPtr.asTypedList(n);
      final wav = _buildWav(samples, sr);
      _freeFn(samplesPtr);
      calloc.free(out);
      calloc.free(outLen);
      calloc.free(rate);
      return wav;
    } catch (_) {
      return Uint8List(0);
    }
  }

  Uint8List _buildWav(Int16List samples, int sampleRate) {
    final dataSize = samples.length * 2;
    final out = BytesBuilder();
    void s(String str) => out.add(str.codeUnits);
    void u16(int v) => out.add([v & 0xff, (v >> 8) & 0xff]);
    void u32(int v) => out.add([
          v & 0xff,
          (v >> 8) & 0xff,
          (v >> 16) & 0xff,
          (v >> 24) & 0xff,
        ]);
    s('RIFF');
    u32(36 + dataSize);
    s('WAVE');
    s('fmt ');
    u32(16);
    u16(1);
    u16(1);
    u32(sampleRate);
    u32(sampleRate * 2);
    u16(2);
    u16(16);
    s('data');
    u32(dataSize);
    final bytes = ByteData(dataSize);
    for (var i = 0; i < samples.length; i++) {
      bytes.setInt16(i * 2, samples[i], Endian.little);
    }
    out.add(bytes.buffer.asUint8List());
    return out.toBytes();
  }
}

// FFI 签名（与 reader_tts.cpp 一致）
typedef _InitC = Pointer<Void> Function(
    Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>);
typedef _InitDart = Pointer<Void> Function(
    Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>);
typedef _SynthC = Int32 Function(Pointer<Void>, Pointer<Utf8>,
    Pointer<Pointer<Int16>>, Pointer<Int32>, Pointer<Int32>);
typedef _SynthDart = int Function(Pointer<Void>, Pointer<Utf8>,
    Pointer<Pointer<Int16>>, Pointer<Int32>, Pointer<Int32>);
typedef _FreeSamplesC = Void Function(Pointer<Int16>);
typedef _FreeSamplesDart = void Function(Pointer<Int16>);
