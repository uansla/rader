import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

/// 内嵌 espeak-ng 兜底 TTS（无系统语音引擎时使用）。
/// 通过 Dart FFI 直接调用 espeak-ng 的 C API，把文字合成为 WAV 字节。
/// 音质为 espeak-ng 机器人腔，但完全离线、跨平台、不依赖设备安装任何引擎。
class EmbeddedTts {
  static const int _audioOutputRetrieval = 1;
  static const int _posCharacter = 1;

  late final _InitDart _init;
  late final _SetVoiceDart _setVoice;
  late final _SynthDart _synth;
  late final _SyncDart _sync;
  late final _TermDart _terminate;
  late final _SetCbDart _setCallback;

  static final List<int> _pcm = <int>[];
  int _sampleRate = 22050;
  bool _inited = false;

  EmbeddedTts._(DynamicLibrary lib) {
    _init = lib.lookupFunction<_InitC, _InitDart>('espeak_Initialize');
    _setVoice =
        lib.lookupFunction<_SetVoiceC, _SetVoiceDart>('espeak_SetVoiceByName');
    _synth = lib.lookupFunction<_SynthC, _SynthDart>('espeak_Synth');
    _sync = lib.lookupFunction<_SyncC, _SyncDart>('espeak_Synchronize');
    _terminate = lib.lookupFunction<_TermC, _TermDart>('espeak_Terminate');
    _setCallback =
        lib.lookupFunction<_SetCbC, _SetCbDart>('espeak_SetSynthCallback');
  }

  /// 加载原生库。Windows 加载 espeak-ng.dll，Android 加载 libespeak-ng.so。
  static EmbeddedTts? tryLoad() {
    try {
      final DynamicLibrary lib;
      if (Platform.isWindows) {
        lib = DynamicLibrary.open('espeak-ng.dll');
      } else if (Platform.isAndroid) {
        lib = DynamicLibrary.open('libespeak-ng.so');
      } else {
        return null;
      }
      return EmbeddedTts._(lib);
    } catch (_) {
      return null;
    }
  }

  /// 初始化。[dataPath] 指向 espeak-ng-data 目录。
  /// 成功返回 true；espeak_Initialize 返回采样率（>0 表示成功）。
  bool init(String dataPath) {
    if (_inited) return true;
    try {
      final path = dataPath.toNativeUtf8();
      final rate = _init(_audioOutputRetrieval, 0, path, 0);
      calloc.free(path);
      if (rate <= 0) return false;
      _sampleRate = rate;
      _inited = true;
      _setCallback(Pointer.fromFunction(_onSamples, 0));
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 把文字合成为 WAV 字节。
  Uint8List synthesize(String text) {
    if (!_inited) return Uint8List(0);
    _pcm.clear();
    try {
      final voice = 'cmn'.toNativeUtf8();
      _setVoice(voice);
      calloc.free(voice);
      final t = text.toNativeUtf8();
      _synth(t.cast<Void>(), t.length, 0, _posCharacter, 0, 0, nullptr, nullptr);
      calloc.free(t);
      _sync();
      return _buildWav();
    } catch (_) {
      return Uint8List(0);
    }
  }

  void dispose() {
    if (_inited) {
      try {
        _terminate();
      } catch (_) {}
      _inited = false;
    }
  }

  // 原生回调：接收 PCM 采样。
  static int _onSamples(Pointer<Int16> wav, int numsamples, Pointer<Void> events) {
    for (var i = 0; i < numsamples; i++) {
      _pcm.add(wav[i]);
    }
    return 0; // 继续
  }

  Uint8List _buildWav() {
    final samples = _pcm;
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
    u16(1); // PCM
    u16(1); // mono
    u32(_sampleRate);
    u32(_sampleRate * 2);
    u16(2);
    u16(16);
    s('data');
    u32(dataSize);
    for (final v in samples) {
      u16(v & 0xffff);
    }
    return out.toBytes();
  }
}

// FFI 签名
typedef _InitC = Int32 Function(Int32, Int32, Pointer<Utf8>, Int32);
typedef _InitDart = int Function(int, int, Pointer<Utf8>, int);
typedef _SetVoiceC = Int32 Function(Pointer<Utf8>);
typedef _SetVoiceDart = int Function(Pointer<Utf8>);
typedef _SynthC = Int32 Function(Pointer<Void>, IntPtr, Uint32, Int32, Uint32,
    Uint32, Pointer<Uint32>, Pointer<Void>);
typedef _SynthDart = int Function(Pointer<Void>, int, int, int, int, int,
    Pointer<Uint32>, Pointer<Void>);
typedef _SyncC = Int32 Function();
typedef _SyncDart = int Function();
typedef _TermC = Int32 Function();
typedef _TermDart = int Function();
typedef _SetCbC = Void Function(Pointer<NativeFunction<_TtsCallbackC>>);
typedef _SetCbDart = void Function(Pointer<NativeFunction<_TtsCallbackC>>);
typedef _TtsCallbackC = Int32 Function(Pointer<Int16>, Int32, Pointer<Void>);
