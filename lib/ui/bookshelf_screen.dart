import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../core/app_settings.dart';
import '../models/book.dart';
import 'annotations_screen.dart';
import 'history_screen.dart';
import 'player_screen.dart';
import 'reader_screen.dart';
import 'stats_screen.dart';
import 'widgets/book_cover.dart';

class BookshelfScreen extends StatefulWidget {
  const BookshelfScreen({super.key});

  @override
  State<BookshelfScreen> createState() => _BookshelfScreenState();
}

enum _Filter { all, favorite, recent, completed }

class _BookshelfScreenState extends State<BookshelfScreen> {
  _Filter _filter = _Filter.all;
  String _query = '';
  String? _tag;
  int _todayMinutes = 0;
  int _streak = 0;
  bool _statsLoaded = false;
  bool _selectionMode = false;
  final Set<int> _selectedBookIds = <int>{};

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    final state = context.read<AppState>();
    final (today, streak) = await state.todayMinutesAndStreak();
    if (!mounted) return;
    setState(() {
      _todayMinutes = today;
      _streak = streak;
      _statsLoaded = true;
    });
  }

  List<Book> _applyFilters(List<Book> books) {
    if (_query.isNotEmpty) {
      books = books
          .where((b) =>
              b.title.toLowerCase().contains(_query.toLowerCase()) ||
              b.author.toLowerCase().contains(_query.toLowerCase()))
          .toList();
    }
    if (_tag != null) {
      books = books.where((b) => _tagsOf(b).contains(_tag)).toList();
    }
    switch (_filter) {
      case _Filter.favorite:
        books = books.where((b) => b.isFavorite).toList();
        break;
      case _Filter.recent:
        books = books.where((b) => b.lastReadAt != null).toList();
        books.sort((a, b) => (b.lastReadAt ?? DateTime(0))
            .compareTo(a.lastReadAt ?? DateTime(0)));
        break;
      case _Filter.completed:
        books = books.where((b) => b.completed).toList();
        break;
      case _Filter.all:
        books.sort((a, b) =>
            (b.lastReadAt ?? DateTime(0)).compareTo(a.lastReadAt ?? DateTime(0)));
        break;
    }
    return books;
  }

  static List<String> _tagsOf(Book b) {
    return b.tags
        .split(',')
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toSet()
        .toList();
  }

  List<String> _allTags(List<Book> books) {
    final set = <String>{};
    for (final b in books) {
      set.addAll(_tagsOf(b));
    }
    return set.toList()..sort();
  }

  Book? _continueReading(List<Book> books) {
    final candidates = books
        .where((b) => b.lastReadAt != null && b.progress < 1.0)
        .toList()
      ..sort((a, b) => (b.lastReadAt ?? DateTime(0))
          .compareTo(a.lastReadAt ?? DateTime(0)));
    if (candidates.isEmpty) return null;
    return candidates.first;
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final books = _applyFilters(List.of(state.books));
    final tags = _allTags(state.books);
    final continueBook = _continueReading(state.books);
    final gridMode =
        state.settings.shelfMode == ShelfViewMode.grid;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _selectionMode ? '已选择 ${_selectedBookIds.length} 本' : '书架',
        ),
        actions: _selectionMode
            ? [
                IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: '取消选择',
                  onPressed: _exitSelectionMode,
                ),
                IconButton(
                  icon: const Icon(Icons.select_all),
                  tooltip: '全选当前显示',
                  onPressed: books.isEmpty ? null : () => _selectAll(books),
                ),
                if (_selectedBookIds.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    tooltip: '删除记录',
                    onPressed: () => _confirmSelectedAction(
                      context,
                      state,
                      cleanup: false,
                    ),
                  ),
                if (_selectedBookIds.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.delete_sweep_outlined),
                    tooltip: '清理记录',
                    onPressed: () => _confirmSelectedAction(
                      context,
                      state,
                      cleanup: true,
                    ),
                  ),
              ]
            : [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () => _showSearch(context),
          ),
          IconButton(
            icon: Icon(gridMode ? Icons.view_list : Icons.grid_view),
            tooltip: gridMode ? '切换为列表' : '切换为网格',
            onPressed: () => state.updateSettings(
                state.settings.copyWith(
                    shelfMode: gridMode ? ShelfViewMode.list : ShelfViewMode.grid)),
          ),
          IconButton(
            icon: const Icon(Icons.bar_chart),
            tooltip: '阅读统计',
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const StatsScreen())),
          ),
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: '阅读历史',
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const HistoryScreen())),
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined),
            tooltip: '选择并清理书籍/文档记录',
            onPressed: () => _enterSelectionMode(),
          ),
          IconButton(
            icon: state.scanning
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
            onPressed: state.scanning ? null : () => state.scan(),
            tooltip: '重新扫描',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await state.scan();
          await _loadStats();
        },
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            if (continueBook != null)
              _ContinueCard(book: continueBook),
            _StatsCard(
                today: _todayMinutes,
                streak: _streak,
                target: state.settings.dailyTarget,
                loaded: _statsLoaded),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: SegmentedButton<_Filter>(
                segments: const [
                  ButtonSegment(value: _Filter.all, label: Text('全部')),
                  ButtonSegment(value: _Filter.favorite, label: Text('收藏')),
                  ButtonSegment(value: _Filter.recent, label: Text('最近')),
                  ButtonSegment(value: _Filter.completed, label: Text('已读完')),
                ],
                selected: {_filter},
                onSelectionChanged: (s) => setState(() => _filter = s.first),
                showSelectedIcon: false,
              ),
            ),
            if (tags.isNotEmpty)
              SizedBox(
                height: 40,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: const Text('全部标签'),
                        selected: _tag == null,
                        onSelected: (_) => setState(() => _tag = null),
                      ),
                    ),
                    for (final t in tags)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          label: Text(t),
                          selected: _tag == t,
                          onSelected: (_) => setState(() => _tag = t),
                        ),
                      ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: books.isEmpty
                  ? _EmptyView(scanning: state.scanning)
                  : (gridMode
                      ? _BookGrid(
                          books: books,
                          onReturn: _loadStats,
                          selectionMode: _selectionMode,
                          selectedBookIds: _selectedBookIds,
                          onToggleSelection: _toggleSelection,
                          onRightClick: _showRightClickMenu,
                        )
                      : _BookList(
                          books: books,
                          onReturn: _loadStats,
                          selectionMode: _selectionMode,
                          selectedBookIds: _selectedBookIds,
                          onToggleSelection: _toggleSelection,
                          onRightClick: _showRightClickMenu,
                        )),
            ),
          ],
        ),
      ),
    );
  }

  void _enterSelectionMode({Book? initial}) {
    setState(() {
      _selectionMode = true;
      if (initial?.id != null) _selectedBookIds.add(initial!.id!);
    });
  }

  void _exitSelectionMode() {
    setState(() {
      _selectionMode = false;
      _selectedBookIds.clear();
    });
  }

  void _toggleSelection(Book book) {
    final id = book.id;
    if (id == null) return;
    setState(() {
      _selectionMode = true;
      if (_selectedBookIds.contains(id)) {
        _selectedBookIds.remove(id);
      } else {
        _selectedBookIds.add(id);
      }
    });
  }

  void _selectAll(List<Book> visibleBooks) {
    final ids = visibleBooks.where((b) => b.id != null).map((b) => b.id!).toList();
    setState(() {
      if (ids.isNotEmpty && ids.every(_selectedBookIds.contains)) {
        _selectedBookIds.removeAll(ids);
      } else {
        _selectedBookIds.addAll(ids);
      }
    });
  }

  List<Book> _selectedBooks(AppState state) {
    return state.books
        .where((b) => b.id != null && _selectedBookIds.contains(b.id))
        .toList();
  }

  Future<void> _confirmSelectedAction(
    BuildContext context,
    AppState state, {
    required bool cleanup,
  }) async {
    final selected = _selectedBooks(state);
    if (selected.isEmpty) return;
    final count = selected.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(cleanup
            ? '清理选中的 ${count} 条记录？'
            : '删除选中的 ${count} 条记录？'),
        content: Text(
          cleanup
              ? '只清理 Reader 中的导入/扫描记录，不删除硬盘、U盘、存储卡上的原文件。清理后也不会被自动扫描重新加入。'
              : '只从 Reader 书架删除记录，不删除原文件。以后重新扫描目录时可以再次加入。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(cleanup ? '清理' : '删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    if (cleanup) {
      await state.cleanupBooks(selected);
    } else {
      await state.removeBooks(selected);
    }
    if (!mounted) return;
    setState(() {
      _selectionMode = false;
      _selectedBookIds.clear();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          cleanup
              ? '已清理 ${count} 条记录'
              : '已删除 ${count} 条记录',
        ),
      ),
    );
  }

  Future<void> _showRightClickMenu(
    Book book,
    Offset globalPosition,
  ) async {
    final state = context.read<AppState>();
    final action = await _showBookContextMenu(
      context,
      book,
      globalPosition,
    );
    if (!mounted || action == null) return;

    switch (action) {
      case 'open':
        if (book.isAudio) {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => PlayerScreen(book: book)),
          );
        } else {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => ReaderScreen(book: book)),
          );
        }
        await _loadStats();
        break;
      case 'favorite':
        await state.toggleFavorite(book);
        break;
      case 'remove':
      case 'cleanup':
        final cleanup = action == 'cleanup';
        final ok = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(cleanup ? '清理这条记录？' : '删除这条记录？'),
            content: Text(
              cleanup
                  ? '只清理 Reader 的导入记录，不删除原文件；清理后不会自动重新扫描加入。\n${book.title}'
                  : '只从 Reader 书架删除记录，不删除原文件；以后重新扫描可以再次加入。\n${book.title}',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(cleanup ? '清理' : '删除'),
              ),
            ],
          ),
        );
        if (ok == true) {
          if (cleanup) {
            await state.cleanupBooks([book]);
          } else {
            await state.removeBooks([book]);
          }
        }
        break;
      case 'annotations':
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => AnnotationsScreen(book: book)),
        );
        break;
      case 'edit':
        await _showEditDialog(context, state, book, _loadStats);
        break;
    }
  }

  void _showSearch(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: TextField(
          autofocus: true,
          decoration: const InputDecoration(hintText: '搜索书名或作者'),
          onChanged: (v) => setState(() => _query = v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }
}

class _ContinueCard extends StatelessWidget {
  final Book book;
  const _ContinueCard({required this.book});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final pct = (book.progress * 100).clamp(0, 100).toInt();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      child: Card(
        elevation: 0,
        color: scheme.primaryContainer,
        child: ListTile(
          leading: Icon(book.isAudio ? Icons.headphones : Icons.menu_book,
              color: scheme.onPrimaryContainer),
          title: Text('继续阅读',
              style: TextStyle(
                  color: scheme.onPrimaryContainer, fontWeight: FontWeight.bold)),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 2),
              Text(book.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: scheme.onPrimaryContainer)),
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: book.progress.clamp(0.0, 1.0),
                  minHeight: 4,
                  backgroundColor: scheme.surface,
                ),
              ),
            ],
          ),
          trailing: Text('$pct%',
              style: TextStyle(color: scheme.onPrimaryContainer)),
          onTap: () {
            if (book.isAudio) {
              Navigator.push(context,
                  MaterialPageRoute(builder: (_) => PlayerScreen(book: book)));
            } else {
              Navigator.push(context,
                  MaterialPageRoute(builder: (_) => ReaderScreen(book: book)));
            }
          },
        ),
      ),
    );
  }
}

class _StatsCard extends StatelessWidget {
  final int today;
  final int streak;
  final int target;
  final bool loaded;
  const _StatsCard(
      {required this.today,
      required this.streak,
      required this.target,
      required this.loaded});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final done = today >= target && target > 0;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          Icon(Icons.local_fire_department,
              size: 18,
              color: streak > 0 ? Colors.deepOrange : scheme.outline),
          const SizedBox(width: 4),
          Text('连续 $streak 天',
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(width: 12),
          Icon(Icons.timer_outlined, size: 18, color: scheme.primary),
          const SizedBox(width: 4),
          Text(loaded ? '今日 $today/$target 分钟' : '今日 -/$target 分钟',
              style: Theme.of(context).textTheme.bodySmall),
          if (done) ...[
            const SizedBox(width: 8),
            Icon(Icons.check_circle, size: 16, color: scheme.primary),
            const SizedBox(width: 2),
            Text('今日目标已达成',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: scheme.primary)),
          ],
        ],
      ),
    );
  }
}

class _BookGrid extends StatelessWidget {
  final List<Book> books;
  final Future<void> Function() onReturn;
  final bool selectionMode;
  final Set<int> selectedBookIds;
  final ValueChanged<Book> onToggleSelection;
  final void Function(Book, Offset) onRightClick;

  const _BookGrid({
    required this.books,
    required this.onReturn,
    required this.selectionMode,
    required this.selectedBookIds,
    required this.onToggleSelection,
    required this.onRightClick,
  });

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 140,
        mainAxisSpacing: 14,
        crossAxisSpacing: 14,
        childAspectRatio: 72 / 130,
      ),
      itemCount: books.length,
      itemBuilder: (context, i) {
        final book = books[i];
        return _BookCell(
          book: book,
          onReturn: onReturn,
          selectionMode: selectionMode,
          selected: book.id != null && selectedBookIds.contains(book.id),
          onToggleSelection: onToggleSelection,
          onRightClick: onRightClick,
        );
      },
    );
  }
}

class _BookList extends StatelessWidget {
  final List<Book> books;
  final Future<void> Function() onReturn;
  final bool selectionMode;
  final Set<int> selectedBookIds;
  final ValueChanged<Book> onToggleSelection;
  final void Function(Book, Offset) onRightClick;

  const _BookList({
    required this.books,
    required this.onReturn,
    required this.selectionMode,
    required this.selectedBookIds,
    required this.onToggleSelection,
    required this.onRightClick,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final b in books)
          _BookListTile(
            book: b,
            onReturn: onReturn,
            selectionMode: selectionMode,
            selected: b.id != null && selectedBookIds.contains(b.id),
            onToggleSelection: onToggleSelection,
            onRightClick: onRightClick,
          ),
      ],
    );
  }
}

class _BookListTile extends StatelessWidget {
  final Book book;
  final Future<void> Function() onReturn;
  final bool selectionMode;
  final bool selected;
  final ValueChanged<Book> onToggleSelection;
  final void Function(Book, Offset) onRightClick;

  const _BookListTile({
    required this.book,
    required this.onReturn,
    required this.selectionMode,
    required this.selected,
    required this.onToggleSelection,
    required this.onRightClick,
  });

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();
    final available = _sourceAvailable(book);
    return GestureDetector(
      onSecondaryTapUp: (details) => onRightClick(book, details.globalPosition),
      child: ListTile(
        selected: selected,
        leading: Stack(
          children: [
            BookCover(book: book, width: 40, height: 56),
            if (selectionMode)
              Positioned(
                left: -2,
                top: -2,
                child: _SelectionMark(selected: selected),
              ),
          ],
        ),
        title: Text(book.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          available ? _subtitle() : '${_subtitle()} · 文件不可用',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (book.readMinutes > 0)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Icon(
                  Icons.timer_outlined,
                  size: 16,
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
            IconButton(
              icon: Icon(
                book.isFavorite ? Icons.star : Icons.star_border,
                color: book.isFavorite ? Colors.amber : null,
              ),
              onPressed: selectionMode ? null : () => state.toggleFavorite(book),
            ),
          ],
        ),
        onTap: () {
          if (selectionMode) {
            onToggleSelection(book);
          } else {
            _open(context, state);
          }
        },
        onLongPress: selectionMode ? null : () => _showMenu(context, state),
      ),
    );
  }

  String _subtitle() {
    final b = book;
    final buf = StringBuffer(b.format.toUpperCase());
    if (b.lastReadAt != null) {
      buf.write(' · ${DateFormat('M/d').format(b.lastReadAt!)}');
    }
    if (b.isAudio && b.totalChapters > 0) {
      buf.write(' · ${b.totalChapters}集');
    }
    if (b.completed) {
      buf.write(' · 已读完');
    }
    return buf.toString();
  }

  Future<void> _open(BuildContext context, AppState state) async {
    if (book.isAudio) {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => PlayerScreen(book: book)),
      );
    } else {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ReaderScreen(book: book)),
      );
    }
    await onReturn();
  }

  void _showMenu(BuildContext context, AppState state) {
    _showBookMenu(context, state, book, onReturn);
  }
}

class _BookCell extends StatelessWidget {
  final Book book;
  final Future<void> Function() onReturn;
  final bool selectionMode;
  final bool selected;
  final ValueChanged<Book> onToggleSelection;
  final void Function(Book, Offset) onRightClick;

  const _BookCell({
    required this.book,
    required this.onReturn,
    required this.selectionMode,
    required this.selected,
    required this.onToggleSelection,
    required this.onRightClick,
  });

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();
    final scheme = Theme.of(context).colorScheme;
    final available = _sourceAvailable(book);
    return GestureDetector(
      onSecondaryTapUp: (details) => onRightClick(book, details.globalPosition),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () {
          if (selectionMode) {
            onToggleSelection(book);
          } else {
            _open(context, state);
          }
        },
        onLongPress: selectionMode ? null : () => _showMenu(context, state),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                Opacity(
                  opacity: available ? 1 : 0.55,
                  child: BookCover(
                    book: book,
                    width: double.infinity,
                    height: 96,
                  ),
                ),
                if (!available)
                  Positioned(
                    left: 4,
                    top: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.surface.withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.folder_off_outlined, size: 11),
                          SizedBox(width: 2),
                          Text('文件不可用', style: TextStyle(fontSize: 9)),
                        ],
                      ),
                    ),
                  ),
                if (selectionMode)
                  Positioned(
                    left: 4,
                    bottom: 4,
                    child: _SelectionMark(selected: selected),
                  ),
                if (book.readMinutes > 0)
                  Positioned(
                    right: 4,
                    top: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.timer, size: 10, color: Colors.white),
                          const SizedBox(width: 2),
                          Text(
                            ${_fmtMinutes(book.readMinutes)},
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              book.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            Text(
              '${_subtitle()}${available ? '' : ' · 文件不可用'}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  static String _fmtMinutes(int m) {
    if (m < 60) return '${m}分';
    return '${(m / 60).floor()}时${m % 60}分';
  }

  String _subtitle() {
    final b = book;
    final buf = StringBuffer(b.format.toUpperCase());
    if (b.lastReadAt != null) {
      buf.write(' · ${DateFormat('M/d').format(b.lastReadAt!)}');
    }
    if (b.isAudio && b.totalChapters > 0) {
      buf.write(' · ${b.totalChapters}集');
    }
    if (b.completed) {
      buf.write(' · 已读完');
    }
    return buf.toString();
  }

  Future<void> _open(BuildContext context, AppState state) async {
    if (book.isAudio) {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => PlayerScreen(book: book)),
      );
    } else {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ReaderScreen(book: book)),
      );
    }
    await onReturn();
  }

  void _showMenu(BuildContext context, AppState state) {
    _showBookMenu(context, state, book, onReturn);
  }
}

class _SelectionMark extends StatelessWidget {
  final bool selected;
  const _SelectionMark({required this.selected});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: selected ? scheme.primary : scheme.surface,
        shape: BoxShape.circle,
        border: Border.all(color: scheme.outline, width: 1.5),
        boxShadow: const [
          BoxShadow(blurRadius: 3, offset: Offset(0, 1)),
        ],
      ),
      child: Icon(
        selected ? Icons.check : Icons.circle_outlined,
        size: 16,
        color: selected ? scheme.onPrimary : scheme.outline,
      ),
    );
  }
}


void _showBookMenu(
  BuildContext context,
  AppState state,
  Book book,
  Future<void> Function() onReturn,
) {
  showModalBottomSheet<void>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: Text(
              book.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              _sourceAvailable(book) ? book.path : '文件当前不可用：请连接原来的硬盘/U盘/存储卡',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          ListTile(
            leading: Icon(book.isFavorite ? Icons.star : Icons.star_border),
            title: Text(book.isFavorite ? '取消收藏' : '收藏'),
            onTap: () async {
              await state.toggleFavorite(book);
              if (ctx.mounted) Navigator.pop(ctx);
            },
          ),
          ListTile(
            leading: const Icon(Icons.bookmark_outline),
            title: const Text('查看标注'),
            onTap: () {
              Navigator.pop(ctx);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => AnnotationsScreen(book: book)),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: const Text('删除记录'),
            subtitle: const Text('不删除原文件，之后重新扫描可以再次加入'),
            onTap: () async {
              Navigator.pop(ctx);
              await state.removeBooks([book]);
              await onReturn();
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete_sweep_outlined),
            title: const Text('清理记录'),
            subtitle: const Text('不删除原文件，清理后禁止自动重新扫描'),
            onTap: () async {
              Navigator.pop(ctx);
              await state.cleanupBooks([book]);
              await onReturn();
            },
          ),
        ],
      ),
    ),
  );
}

bool _sourceAvailable(Book book) {
  return FileSystemEntity.typeSync(book.path) != FileSystemEntityType.notFound;
}

Future<String?> _showBookContextMenu(
  BuildContext context,
  Book book,
  Offset globalPosition,
) async {
  return showMenu<String>(
    context: context,
    position: RelativeRect.fromLTRB(
      globalPosition.dx,
      globalPosition.dy,
      globalPosition.dx,
      globalPosition.dy,
    ),
    items: [
      PopupMenuItem<String>(
        value: 'open',
        enabled: _sourceAvailable(book),
        child: Text(
          _sourceAvailable(book)
              ? '打开'
              : '打开（文件当前不可用）',
        ),
      ),
      PopupMenuItem<String>(
        value: 'favorite',
        child: Text(book.isFavorite ? '取消收藏' : '收藏'),
      ),
      const PopupMenuDivider(),
      const PopupMenuItem<String>(
        value: 'remove',
        child: Text('删除记录'),
      ),
      const PopupMenuItem<String>(
        value: 'cleanup',
        child: Text('清理记录并禁止再次自动扫描'),
      ),
      const PopupMenuDivider(),
      const PopupMenuItem<String>(
        value: 'annotations',
        child: Text('查看标注'),
      ),
      const PopupMenuItem<String>(
        value: 'edit',
        child: Text('编辑信息'),
      ),
    ],
  );
}

Future<void> _showEditDialog(BuildContext context, AppState state, Book book,
    Future<void> Function() onReturn) async {
  final titleCtl = TextEditingController(text: book.title);
  final authorCtl = TextEditingController(text: book.author);
  final tagsCtl = TextEditingController(text: book.tags);
  var colorIdx = book.coverColor;

  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDlg) => AlertDialog(
        title: const Text('编辑书籍信息'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleCtl,
                decoration: const InputDecoration(labelText: '书名'),
              ),
              TextField(
                controller: authorCtl,
                decoration: const InputDecoration(labelText: '作者'),
              ),
              TextField(
                controller: tagsCtl,
                decoration: const InputDecoration(
                    labelText: '标签', hintText: '多个标签用逗号分隔'),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: Text('封面色',
                    style: Theme.of(context).textTheme.bodySmall),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (var i = 0; i < BookCover.kCoverColors.length; i++)
                    InkWell(
                      onTap: () => setDlg(() => colorIdx = i),
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: BookCover.kCoverColors[i],
                          shape: BoxShape.circle,
                          border: Border.all(
                            width: 3,
                            color: colorIdx == i
                                ? Theme.of(context).colorScheme.primary
                                : Colors.transparent,
                          ),
                        ),
                        child: colorIdx == i
                            ? const Icon(Icons.check, color: Colors.white, size: 18)
                            : null,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () async {
              await state.bookRepo.setInfo(book.id!,
                  title: titleCtl.text.trim(),
                  author: authorCtl.text.trim(),
                  tags: tagsCtl.text.trim());
              if (colorIdx >= 0 && colorIdx != book.coverColor) {
                await state.bookRepo.setCoverColor(book.id!, colorIdx);
              }
              await state.scan(dirs: const []);
              await onReturn();
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    ),
  );
}

class _EmptyView extends StatelessWidget {
  final bool scanning;
  const _EmptyView({required this.scanning});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 60),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.menu_book_outlined,
                size: 64, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 12),
            Text(scanning ? '正在扫描…' : '书架上还没有书'),
            const SizedBox(height: 4),
            Text(
              '请到「文库」添加扫描目录或导入书籍',
              style: TextStyle(color: Theme.of(context).colorScheme.outline),
            ),
          ],
        ),
      ),
    );
  }
}
