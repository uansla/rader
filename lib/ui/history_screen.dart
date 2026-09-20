import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import 'player_screen.dart';
import 'reader_screen.dart';

/// 阅读历史时间线：展示最近打开/听过的书与进度。
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<Map<String, Object?>> _rows = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final rows = await context.read<AppState>().historyRepo.recentWithBooks(limit: 200);
    if (!mounted) return;
    setState(() => _rows = rows);
  }

  Future<void> _open(Map<String, Object?> r) async {
    final state = context.read<AppState>();
    final book = await state.bookRepo.getById(r['book_id'] as int);
    if (book == null || !mounted) return;
    if (book.isAudio) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => PlayerScreen(book: book)));
    } else {
      Navigator.push(context, MaterialPageRoute(builder: (_) => ReaderScreen(book: book)));
    }
  }

  String _actionName(String? action) {
    switch (action) {
      case 'listen':
        return '听过';
      case 'read':
        return '读过';
      default:
        return '打开';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('阅读历史')),
      body: _rows.isEmpty
          ? const Center(child: Text('暂无阅读记录'))
          : ListView.separated(
              padding: const EdgeInsets.all(8),
              itemCount: _rows.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final r = _rows[i];
                final ts = (r['ts'] as int?) ?? 0;
                final time = ts > 0
                    ? DateTime.fromMillisecondsSinceEpoch(ts)
                    : null;
                final title = (r['book_title'] as String?) ?? '未知书籍';
                final isAudio = r['book_type'] == 'audio';
                return ListTile(
                  leading: Icon(
                    isAudio ? Icons.headphones : Icons.menu_book,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                    '${_actionName(r['action'] as String?)}'
                    '${time != null ? ' · ${_fmtTime(time)}' : ''}',
                  ),
                  trailing: const Icon(Icons.chevron_right, size: 18),
                  onTap: () => _open(r),
                );
              },
            ),
    );
  }

  static String _fmtTime(DateTime t) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(t.year, t.month, t.day);
    final hh = '${t.hour.toString().padLeft(2, '0')}:'
        '${t.minute.toString().padLeft(2, '0')}';
    if (day == today) return '今天 $hh';
    if (day == today.subtract(const Duration(days: 1))) return '昨天 $hh';
    return '${t.month}/${t.day} $hh';
  }
}
