import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 自定义字体：把用户选择的 ttf 复制到应用目录，
/// 通过 dart:ui 的 FontLoader 运行时注册，即可在 TextStyle 里按家族名使用。
/// 注意：运行时注册的字体在每次进程启动后都需要重新加载。
class FontManager {
  static const _dirName = 'custom_fonts';

  static Future<File?> getFontFile(String familyName) async {
    if (familyName.isEmpty) return null;
    final dir = await _fontsDir();
    final f = File(p.join(dir.path, '$familyName.ttf'));
    if (!f.existsSync()) return null;
    return f;
  }

  static Future<Directory> _fontsDir() async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory(p.join(support.path, _dirName));
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  /// 导入一个 ttf 文件，注册为给定家族名，返回家族名。
  static Future<String?> importFont({String? familyName}) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['ttf', 'otf'],
    );
    if (result == null || result.files.isEmpty) return null;
    final src = result.files.first.path;
    if (src == null || src.isEmpty) return null;
    final name = familyName ??
        _sanitize(p.basenameWithoutExtension(src));
    final dir = await _fontsDir();
    final dest = File(p.join(dir.path, '$name.ttf'));
    try {
      await File(src).copy(dest.path);
    } catch (e) {
      return '复制字体失败: $e';
    }
    final ok = await registerFromFile(dest);
    return ok ? name : '字体注册失败';
  }

  /// 从文件注册字体，返回是否成功。
  static Future<bool> registerFromFile(File file) async {
    if (!file.existsSync()) return false;
    final bytes = await file.readAsBytes();
    final loader = FontLoader(_fontFamilyFrom(file.path));
    loader.addFont(Future.value(ByteData.view(bytes.buffer)));
    await loader.load();
    return true;
  }

  /// 启动时重载已保存的自定义字体。
  static Future<void> reloadSaved(String familyName) async {
    if (familyName.isEmpty) return;
    final f = await getFontFile(familyName);
    if (f != null) {
      await registerFromFile(f);
    }
  }

  /// 删除自定义字体文件。
  static Future<void> removeFont(String familyName) async {
    if (familyName.isEmpty) return;
    final dir = await _fontsDir();
    final f = File(p.join(dir.path, '$familyName.ttf'));
    if (f.existsSync()) {
      try {
        await f.delete();
      } catch (_) {}
    }
  }

  static String _fontFamilyFrom(String path) =>
      _sanitize(p.basenameWithoutExtension(path));

  static String _sanitize(String s) {
    var out = s.trim().replaceAll(RegExp(r'[^\w\u4e00-\u9fa5-]'), '_');
    if (out.isEmpty) out = 'custom_font';
    return out;
  }
}
