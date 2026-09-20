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
        title: const Text('书架'),
        actions: [
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
                      ? _BookGrid(books: books, onReturn: _loadStats)
                      : _BookList(books: books, onReturn: _loadStats)),
            ),
          ],
        ),
      ),
    );
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
  const _BookGrid({required this.books, required this.onReturn});

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
      itemBuilder: (context, i) => _BookCell(book: books[i], onReturn: onReturn),
    );
  }
}

class _BookList extends StatelessWidget {
  final List<Book> books;
  final Future<void> Function() onReturn;
  const _BookList({required this.books, required this.onReturn});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final b in books) _BookListTile(book: b, onReturn: onReturn),
      ],
    );
  }
}

class _BookListTile extends StatelessWidget {
  final Book book;
  final Future<void> Function() onReturn;
  const _BookListTile({required this.book, required this.onReturn});

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();
    return ListTile(
      leading: BookCover(book: book, width: 40, height: 56),
      title: Text(book.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(_subtitle(),
          maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (book.readMinutes > 0)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Icon(Icons.timer_outlined,
                  size: 16, color: Theme.of(context).colorScheme.outline),
            ),
          IconButton(
            icon: Icon(book.isFavorite ? Icons.star : Icons.star_border,
                color: book.isFavorite ? Colors.amber : null),
            onPressed: () => state.toggleFavorite(book),
          ),
        ],
      ),
      onTap: () => _open(context, state),
      onLongPress: () => _showMenu(context, state),
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
      await Navigator.push(context,
          MaterialPageRoute(builder: (_) => PlayerScreen(book: book)));
    } else {
      await Navigator.push(context,
          MaterialPageRoute(builder: (_) => ReaderScreen(book: book)));
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
  const _BookCell({required this.book, required this.onReturn});

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => _open(context, state),
      onLongPress: () => _showMenu(context, state),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              BookCover(book: book, width: double.infinity, height: 96),
              if (book.readMinutes > 0)
                Positioned(
                  right: 4,
                  top: 4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.timer, size: 10, color: Colors.white),
                        const SizedBox(width: 2),
                        Text(_fmtMinutes(book.readMinutes),
                            style: const TextStyle(color: Colors.white, fontSize: 9)),
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
            _subtitle(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.outline),
          ),
        ],
      ),
    );
  }

  static String _fmtMinutes(int m) {
    if (m < 60) return '$m分';
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
      await Navigator.push(context,
          MaterialPageRoute(builder: (_) => PlayerScreen(book: book)));
    } else {
      await Navigator.push(context,
          MaterialPageRoute(builder: (_) => ReaderScreen(book: book)));
    }
    await onReturn();
  }

  void _showMenu(BuildContext context, AppState state) {
    _showBookMenu(context, state, book, onReturn);
  }
}

void _showBookMenu(BuildContext context, AppState state, Book book,
    Future<void> Function() onReturn) {
  showModalBottomSheet<void>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: Text(book.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          ListTile(
            leading: Icon(book.isFavorite ? Icons.star : Icons.star_border),
            title: Text(book.isFavorite ? '取消收藏' : '收藏'),
            onTap: () {
              state.toggleFavorite(book);
              Navigator.pop(ctx);
            },
          ),
          ListTile(
            leading: Icon(book.completed ? Icons.undo : Icons.check_circle_outline),
            title: Text(book.completed ? '取消已读完' : '标记为已读完'),
            onTap: () async {
              await state.bookRepo.setCompleted(book.id!, !book.completed);
              await state.scan(dirs: const []);
              if (ctx.mounted) Navigator.pop(ctx);
            },
          ),
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: const Text('编辑信息'),
            onTap: () {
              Navigator.pop(ctx);
              _showEditDialog(context, state, book, onReturn);
            },
          ),
          ListTile(
            leading: const Icon(Icons.bookmark_outline),
            title: const Text('查看标注'),
            onTap: () {
              Navigator.pop(ctx);
              Navigator.push(context,
                  MaterialPageRoute(builder: (_) => AnnotationsScreen(book: book)));
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: const Text('删除记录'),
            onTap: () async {
              Navigator.pop(ctx);
              final ok = await showDialog<bool>(
                context: context,
                builder: (c) => AlertDialog(
                  title: const Text('删除该书？'),
                  content: Text('仅从书架移除记录，不删除磁盘文件。\n${book.title}'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(c, false),
                        child: const Text('取消')),
                    TextButton(
                        onPressed: () => Navigator.pop(c, true),
                        child: const Text('删除')),
                  ],
                ),
              );
              if (ok == true) {
                await state.deleteBook(book);
                await onReturn();
              }
            },
          ),
        ],
      ),
    ),
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
