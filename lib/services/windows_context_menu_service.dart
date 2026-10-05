import 'dart:io';

/// Registers the Reader shell verb for supported files under the current user (HKCU).
/// No administrator permission is required.
class WindowsContextMenuService {
  static const _extensions = <String>[
    'txt','epub','mobi','azw3','html','htm','md','markdown','fb2',
    'odt','docx','mp3','m4a','aac','wav','flac','ogg','opus','m4b','amr',
  ];

  static const _menuName='Reader';

  static String _shellKey(String extension) {
    return r'HKCU\Software\Classes\SystemFileAssociations\.' +
        extension + r'\shell\' + _menuName;
  }

  static Future<bool> _reg(List<String> arguments) async {
    try {
      final result=await Process.run('reg.exe',arguments);
      return result.exitCode==0;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> install() async {
    if (!Platform.isWindows) return false;
    final exe=Platform.resolvedExecutable;
    if (exe.isEmpty || !File(exe).existsSync()) return false;

    var ok=true;
    for (final extension in _extensions) {
      final key=_shellKey(extension);
      ok=await _reg([
        'ADD',key,'/ve','/t','REG_SZ','/d','用 Reader 打开','/f',
      ]) && ok;
      ok=await _reg([
        'ADD',key,'/v','Icon','/t','REG_SZ','/d',exe,'/f',
      ]) && ok;
      ok=await _reg([
        'ADD',key + r'\command','/ve','/t','REG_SZ','/d','"$exe" "%1"','/f',
      ]) && ok;
    }
    return ok;
  }

  static Future<bool> uninstall() async {
    if (!Platform.isWindows) return false;
    var ok=true;
    for (final extension in _extensions) {
      final key=_shellKey(extension);
      final removed=await _reg(['DELETE',key,'/f']);
      if (!removed) {
        final exists=await _reg(['QUERY',key]);
        if (exists) ok=false;
      }
    }
    return ok;
  }

  static Future<bool> isInstalled() async {
    if (!Platform.isWindows) return false;
    return _reg(['QUERY',_shellKey('epub')]);
  }
}
