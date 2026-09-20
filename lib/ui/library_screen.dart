import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../services/format_detector.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen>
    with WidgetsBindingObserver {
  bool _importing = false;
  bool _dragging = false;
  bool _storageGranted = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkStorage();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 从系统「所有文件访问」授权页返回后重新检测
    if (state == AppLifecycleState.resumed) {
      _checkStorage();
    }
  }

  Future<void> _checkStorage() async {
    if (!Platform.isAndroid) return;
    final granted = await Permission.manageExternalStorage.isGranted;
    if (mounted && granted != _storageGranted) {
      setState(() => _storageGranted = granted);
      if (granted) {
        context.read<AppState>().scan();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('文库'),
        actions: [
          IconButton(
            icon: state.scanning
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
            onPressed: state.scanning ? null : () => state.scan(),
            tooltip: '扫描全部目录',
          ),
        ],
      ),
      body: DropTarget(
        onDragEntered: (_) => setState(() => _dragging = true),
        onDragExited: (_) => setState(() => _dragging = false),
        onDragDone: (details) {
          setState(() => _dragging = false);
          final paths = details.files.map((f) => f.path).where((e) => e.isNotEmpty).toList();
          _importPaths(paths, null);
        },
        child: Stack(
          children: [
            ListView(
              padding: const EdgeInsets.all(12),
              children: [
                if (!_storageGranted) _buildStorageBanner(state),
                _SectionTitle(
                  icon: Icons.folder_outlined,
                  text: '扫描目录',
                  trailing: IconButton(
                    icon: const Icon(Icons.add),
                    tooltip: '添加目录',
                    onPressed: _addFolder,
                  ),
                ),
                ...state.folders.map((f) => ListTile(
                      leading: const Icon(Icons.folder),
                      title: Text(f.path, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(f.enabled ? '已启用' : '已停用'),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        tooltip: '移除',
                        onPressed: () => state.removeFolder(f.id!),
                      ),
                    )),
                if (state.folders.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('暂无扫描目录，点击右上角 + 添加'),
                  ),
                const Divider(height: 32),
                _SectionTitle(
                  icon: Icons.upload_file,
                  text: '导入书籍',
                ),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      children: [
                        FilledButton.icon(
                          onPressed: _importing ? null : _pickAndImport,
                          icon: const Icon(Icons.file_open),
                          label: Text(_importing ? '导入中…' : '选择文件导入'),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '支持：TXT / EPUB / MOBI / HTML / MD / ODT / DOCX 及 MP3 / M4A / FLAC 等\nWindows 也可直接把文件拖进本窗口',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
                const Divider(height: 32),
                _SectionTitle(icon: Icons.info_outline, text: '状态'),
                Card(
                  child: ListTile(
                    leading: state.scanning
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check_circle_outline),
                    title: Text(state.lastScanMessage ?? '等待扫描'),
                    subtitle: Text('共 ${state.books.length} 本书籍'),
                  ),
                ),
              ],
            ),
            if (_dragging)
              Positioned.fill(
                child: Container(
                  color: Theme.of(context)
                      .colorScheme
                      .primary
                      .withValues(alpha: 0.08),
                  alignment: Alignment.center,
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text('松开以导入书籍文件'),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _requestStorageIfNeeded() async {
    if (!Platform.isAndroid) return;
    if (await Permission.manageExternalStorage.isGranted) return;
    // Android 11+ 需要「所有文件访问」才能扫描任意目录
    await Permission.manageExternalStorage.request();
    await _checkStorage();
  }

  Widget _buildStorageBanner(AppState state) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: scheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.folder_off_outlined, color: scheme.onPrimaryContainer),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('需要「所有文件访问」权限才能扫描手机目录',
                      style: TextStyle(
                          color: scheme.onPrimaryContainer,
                          fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text('Android 11 及以上需授权后才能扫描 Download 等目录，否则书架会一直为空。',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: scheme.onPrimaryContainer)),
            const SizedBox(height: 8),
            Row(
              children: [
                FilledButton.tonal(
                  onPressed: _requestStorageIfNeeded,
                  child: const Text('去授权'),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: state.scanning ? null : () => state.scan(),
                  child: const Text('重新扫描'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addFolder() async {
    await _requestStorageIfNeeded();
    final path = await FilePicker.platform.getDirectoryPath(
      dialogTitle: '选择要扫描的文件夹',
    );
    if (mounted && path != null && path.isNotEmpty) {
      context.read<AppState>().addFolder(path);
    }
  }

  Future<void> _pickAndImport() async {
    await _requestStorageIfNeeded();
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: const [
        'txt', 'epub', 'mobi', 'azw3', 'html', 'htm', 'md', 'markdown', 'fb2', 'odt', 'docx',
        'mp3', 'm4a', 'aac', 'wav', 'flac', 'ogg', 'opus', 'm4b', 'amr',
      ],
    );
    if (result == null || result.files.isEmpty) return;
    final paths = result.files.map((f) => f.path ?? '').where((e) => e.isNotEmpty).toList();
    if (mounted) await _importPaths(paths, context.read<AppState>());
  }

  Future<void> _importPaths(List<String> paths, AppState? cachedState) async {
    if (paths.isEmpty) return;
    final state = cachedState ?? context.read<AppState>();
    setState(() => _importing = true);
    try {
      final booksDir = await state.getBooksDirectory();
      var imported = 0;
      for (final src in paths) {
        final fmt = FormatDetector.detectFormat(src);
        if (fmt == null) continue;
        var name = p.basename(src);
        var dest = p.join(booksDir.path, name);
        var n = 1;
        while (File(dest).existsSync()) {
          final ext = p.extension(name);
          final base = p.basenameWithoutExtension(name);
          dest = p.join(booksDir.path, '$base($n)$ext');
          n++;
        }
        try {
          await File(src).copy(dest);
          imported++;
        } catch (_) {}
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已导入 $imported 个文件')),
        );
      }
      if (imported > 0) {
        await state.scan(dirs: [booksDir.path]);
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }
}

class _SectionTitle extends StatelessWidget {
  final IconData icon;
  final String text;
  final Widget? trailing;
  const _SectionTitle({required this.icon, required this.text, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 6),
        Text(text, style: Theme.of(context).textTheme.titleSmall),
        const Spacer(),
        ?trailing,
      ],
    );
  }
}
