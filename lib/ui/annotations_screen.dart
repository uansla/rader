import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models/book.dart';
import '../models/bookmark.dart';
import '../models/note.dart';
import 'reader_screen.dart';

/// 某本书的书签 / 笔记汇总页：集中查看、跳转定位、编辑/删除、导出 Markdown/JSON。
class AnnotationsScreen extends StatefulWidget {
  final Book book;
  const AnnotationsScreen({super.key, required this.book});

  @override
  State<AnnotationsScreen> createState() => _AnnotationsScreenState();
}

class _AnnotationsScreenState extends State<AnnotationsScreen> {
  List<Bookmark> _bookmarks = [];
  List<Note> _notes = [];
  List<String> _titles = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final state = context.read<AppState>();
    final session = await state.textContent.open(widget.book);
    final bookmarks = await state.bookmarkRepo.getForBook(widget.book.id!);
    final notes = await state.noteRepo.getForBook(widget.book.id!);
    if (!mounted) return;
    setState(() {
      _titles = session.titles;
      _bookmarks = bookmarks;
      _notes = notes;
      _loading = false;
    });
  }

  Future<void> _exportMarkdown() async {
    final state = context.read<AppState>();
    final md = await state.markdownExporter.buildForBook(
        widget.book.id!, _titles);
    final result = await FilePicker.platform.saveFile(
      dialogTitle: '导出标注 Markdown',
      fileName:
          '${widget.book.title}_标注.md',
      type: FileType.custom,
      allowedExtensions: const ['md'],
    );
    if (result == null || result.isEmpty) return;
    await File(result).writeAsString(md, encoding: utf8);
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('已导出到：$result')));
    }
  }

  Future<void> _exportJson() async {
    final payload = json.encode({
      'app': 'reader-annotations',
      'book_id': widget.book.id,
      'title': widget.book.title,
      'bookmarks': [
        for (final b in _bookmarks)
          {
            'chapter_idx': b.chapterIdx,
            'position': b.position,
            'text': b.text,
            'created_at': b.createdAt.millisecondsSinceEpoch,
          }
      ],
      'notes': [
        for (final n in _notes)
          {
            'chapter_idx': n.chapterIdx,
            'position': n.position,
            'text': n.text,
            'created_at': n.createdAt.millisecondsSinceEpoch,
          }
      ],
    });
    final result = await FilePicker.platform.saveFile(
      dialogTitle: '导出标注 JSON',
      fileName: '${widget.book.title}_标注.json',
      type: FileType.custom,
      allowedExtensions: const ['json'],
    );
    if (result == null || result.isEmpty) return;
    await File(result).writeAsString(payload, encoding: utf8);
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('已导出到：$result')));
    }
  }

  Future<void> _deleteBookmark(Bookmark bm) async {
    final state = context.read<AppState>();
    await state.bookmarkRepo.remove(bm.id!);
    await _load();
  }

  Future<void> _editNote(Note note) async {
    final state = context.read<AppState>();
    final controller = TextEditingController(text: note.text);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('编辑笔记'),
        content: TextField(
          controller: controller,
          maxLines: 4,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text),
              child: const Text('保存')),
        ],
      ),
    );
    if (result == null || result.trim().isEmpty) return;
    await state
        .noteRepo
        .update(Note(
          id: note.id,
          bookId: note.bookId,
          chapterIdx: note.chapterIdx,
          position: note.position,
          text: result.trim(),
          createdAt: note.createdAt,
        ));
    await _load();
  }

  Future<void> _deleteNote(Note note) async {
    final state = context.read<AppState>();
    await state.noteRepo.remove(note.id!);
    await _load();
  }

  void _openAt(int chapterIdx, int pos) {
    final b = widget.book.copyWith(
        chapterIndex: chapterIdx, position: pos, progress: 0.0);
    Navigator.push(context,
        MaterialPageRoute(builder: (_) => ReaderScreen(book: b)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.book.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            icon: const Icon(Icons.description_outlined),
            tooltip: '导出 Markdown',
            onPressed: _exportMarkdown,
          ),
          IconButton(
            icon: const Icon(Icons.data_object),
            tooltip: '导出 JSON',
            onPressed: _exportJson,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(8),
              children: [
                if (_notes.isNotEmpty) ...[
                  _SectionTitle(text: '笔记（${_notes.length}）'),
                  for (final n in _notes)
                    _NoteTile(
                      note: n,
                      chapterTitle: _chapterTitle(n.chapterIdx),
                      onTap: () => _openAt(n.chapterIdx, n.position),
                      onEdit: () => _editNote(n),
                      onDelete: () => _deleteNote(n),
                    ),
                  const SizedBox(height: 16),
                ],
                if (_bookmarks.isNotEmpty) ...[
                  _SectionTitle(text: '书签（${_bookmarks.length}）'),
                  for (final bm in _bookmarks)
                    _BookmarkTile(
                      bookmark: bm,
                      chapterTitle: _chapterTitle(bm.chapterIdx),
                      onTap: () => _openAt(bm.chapterIdx, bm.position),
                      onDelete: () => _deleteBookmark(bm),
                    ),
                ],
                if (_notes.isEmpty && _bookmarks.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: Text('这本书还没有书签或笔记')),
                  ),
              ],
            ),
    );
  }

  String _chapterTitle(int idx) {
    if (_titles.isNotEmpty && idx < _titles.length) return _titles[idx];
    return '第${idx + 1}章';
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
      child: Text(text,
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(color: Theme.of(context).colorScheme.primary)),
    );
  }
}

class _NoteTile extends StatelessWidget {
  final Note note;
  final String chapterTitle;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  const _NoteTile({
    required this.note,
    required this.chapterTitle,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      child: ListTile(
        leading: const Icon(Icons.edit_note),
        title: Text(note.text, maxLines: 3, overflow: TextOverflow.ellipsis),
        subtitle: Text(chapterTitle),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
                icon: const Icon(Icons.edit_outlined, size: 20),
                onPressed: onEdit),
            IconButton(
                icon: const Icon(Icons.delete_outline, size: 20),
                onPressed: onDelete),
          ],
        ),
        onTap: onTap,
      ),
    );
  }
}

class _BookmarkTile extends StatelessWidget {
  final Bookmark bookmark;
  final String chapterTitle;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  const _BookmarkTile({
    required this.bookmark,
    required this.chapterTitle,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      child: ListTile(
        leading: const Icon(Icons.bookmark),
        title: Text(bookmark.text,
            maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Text(chapterTitle),
        trailing: IconButton(
            icon: const Icon(Icons.delete_outline, size: 20),
            onPressed: onDelete),
        onTap: onTap,
      ),
    );
  }
}
