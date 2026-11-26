# Reader 阅读器

> 一款有灵魂的本地阅读器：离线朗读、局域网传书、阅读统计，跨 Android / Windows。

本地优先、无广告、不联网也能用的阅读应用。支持 TXT / EPUB / MOBI / HTML / MD 以及 MP3 / M4A / FLAC 有声书。朗读引擎内置多级回退，任何设备都能「开口读」。

---

## ✨ 功能特性

- **📚 多格式书架**：TXT / EPUB / MOBI / HTML / MD 文本书 + MP3 / M4A / FLAC 有声书
- **🔊 离线朗读（核心）**：三级引擎自动回退
  1. **系统语音引擎**（有则优先，音质好、多音色，如手机的 Google TTS）
  2. **内嵌神经语音「超文 Chaowen」**（Piper + ONNX，离线中文女声，Android/Windows 内置）
  3. **espeak-ng 兜底**（任何设备保证能读）
- **📖 朗读体验**：跟随朗读自动滚动、读完一章自动翻下一章、点击即停、退出即停
- **📶 局域网传书**：设备间自动发现 + HTTP 直传，无需数据线
- **📊 阅读统计**：每日时长、日历热力图、连续打卡、书籍阅读时长
- **🔖 书签 / 笔记 / 目录 / 搜索**
- **⏰ 睡眠定时 / 深色模式 / 字体与排版自定义**
- **🖥️ 跨平台**：Android（APK）+ Windows（便携版）

---

## 📦 安装

从本仓库 [Releases](https://github.com/uansla/rader/releases) 下载对应 Windows 版本：

| 平台 | 文件 | 说明 |
|------|------|------|
| Android | `Reader_vX.Y.Z.apk` | 直接安装（arm64，约 141MB，含离线语音模型） |
| Windows 7 / 8 / 8.1 | `Reader_vX.Y.Z_Windows_7-8.1_x64.zip` | Flutter 3.16 legacy build，优先使用 Windows SAPI 系统语音 |\n| Windows 10 / 11 | `Reader_vX.Y.Z_Windows_10-11_x64.zip` | 内置 Matcha 中文语音模型，CPU 推理，无需显卡驱动 |

> Win7/8.1 版使用系统 SAPI 语音；Win10/11 版使用随包提供的 Matcha 离线语音模型。两个版本均以 CPU 运行语音，无需独立显卡驱动。系统声音输出仍需有可用音频设备。
> Android 需要 Android 10+（API 29+）。

📚 完整文档见 [`docs/`](docs/README.md)（同步 GitHub Wiki）。

---

## 🚀 快速使用

### 添加书籍
1. 打开「文库」→「添加目录」，选择存放书籍的目录（如 `Download`），或「选择文件导入」。
2. 书架会自动扫描目录，显示所有书籍。

### 局域网传书（手机 ↔ 手机 / 平板 / Windows）
1. 两部设备连同一个 WiFi。
2. 在来源设备上打开目标书籍 → 「传书」，选择目标设备。
3. 接收方在「文库」→ 接收列表确认即可。

### 朗读
1. 打开一本书，点底部「朗读」。
2. 朗读开始：文字随朗读自动滚动，读完一章自动翻到下一章。
3. 再点一次「朗读」停止；退出小说即自动停止。

### 有声书
- 支持 MP3 / M4A / FLAC，支持章节、进度记忆、倍速。

---

## 🎙️ 朗读引擎说明

语音方式按 Windows 版本区分：

```
系统引擎（Google TTS / SAPI 等，多音色）
        ↓ 无中文语音时
内嵌神经语音「超文 Chaowen」（Piper huayan，离线女声）
        ↓ 模型/库加载失败时
espeak-ng（离线机器人腔兜底）
```

- 手机（有 Google TTS）：优先使用系统引擎，多音色可选。
- Windows 7/8/8.1 构建优先调用 SAPI 系统语音；Windows 10/11 构建直接使用随包内置的 Matcha 离线模型。

---

## 🔧 开发 / 构建

### 环境
- Flutter SDK（Dart 3.x）
- Android 构建：Android SDK + NDK（原生 TTS 库已预编译随仓库提供）

### 从源码构建
```bash
git clone https://github.com/uansla/rader.git
cd rader

# Android APK
flutter pub get
flutter build apk --release
# 输出：build/app/outputs/flutter-apk/app-release.apk

# Windows 10/11（Flutter 3.47.2）
flutter build windows --release --dart-define=READER_LEGACY_WINDOWS=false

# Windows 7/8/8.1 需使用 Flutter 3.16.9 与旧版依赖集，
# 请使用 .github/workflows/build-test-package.yml 对应的 legacy CI 构建。
# 构建后需把 native/espeak-ng 下的 DLL + espeak-ng-data + 语音模型
# 一并拷贝到 Release 目录（已包含在仓库 native/ 目录）
```

### 项目结构
```
lib/
  services/
    tts_service.dart        # 朗读引擎三级回退
    neural_tts.dart         # Piper 神经语音（后台 isolate + FFI）
    embedded_tts.dart       # espeak-ng 兜底（FFI）
    discovery_service.dart  # 局域网设备发现 + HTTP 传书
  ui/
    reader_screen.dart      # 阅读器（分页/滚动、朗读、书签）
    bookshelf_screen.dart   # 书架
    library_screen.dart     # 文库（扫描/导入）
    stats_screen.dart       # 阅读统计热力图
  data/                     # SQLite 数据层
android/app/src/main/jniLibs/  # 预编译原生 TTS 库（.so）
native/espeak-ng/              # Windows 原生库 + 语音数据
assets/                        # 华研语音模型（ONNX）
```

### 原生 TTS 库来源
- **espeak-ng**：`espeak-ng/espeak-ng`（v1.52 编译）
- **Piper**：`rhasspy/piper` + `piper-phonemize`
- **ONNX Runtime**：`microsoft/onnxruntime`
- **华研中文语音**：[Piper Voices - huayan](https://huggingface.co/rhasspy/piper-voices/tree/main/zh/zh_CN/huayan)（CC BY-NC 4.0，仅可学习研究使用）

---

## 📄 协议

本仓库代码遵循 MIT License（见 `LICENSE`）。

> 注意：内置的华研语音模型（`zh_CN-chaowen-medium.onnx`）遵循 [CC BY-NC 4.0](https://creativecommons.org/licenses/by-nc/4.0/)（仅限非商业使用），请遵守其授权条款。

---

## 🙏 致谢

- [Flutter](https://flutter.dev)
- [espeak-ng](https://github.com/espeak-ng/espeak-ng)
- [Piper TTS](https://github.com/rhasspy/piper)
- [ONNX Runtime](https://github.com/microsoft/onnxruntime)
- [just_audio](https://pub.dev/packages/just_audio) / [flutter_tts](https://pub.dev/packages/flutter_tts)


> Windows 测试版当前使用 Piper「超文 Chaowen Medium」（约 63.2MB，22.05kHz）。Android 端现阶段仍保留原有模型资源，后续 Matcha Icefall zh-Baker 测试确定后再统一调整。