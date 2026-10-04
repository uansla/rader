import 'package:flutter/material.dart';

import '../../app_state.dart';
import '../../models/book.dart';

Future<void> showBookCleanupDialog(
    BuildContext context, AppState state) async {
  final books = List<Book>.of(state.books)
    ..sort((a, b) => b.addedAt.compareTo(a.addedAt));

  if (books.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('当前没有可清理的书籍或文档记录')),
    );
    return;
  }

  final selected = <int>{};

  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          final allSelected = selected.length == books.length;
          final selectedCount = selected.length;
          return AlertDialog(
            title: Row(
              children: [
                const Expanded(child: Text('清理书籍/文档记录')),
                Text(
                  '$selectedCount/${books.length}',
                  style: Theme.of(dialogContext).textTheme.bodySmall,
                ),
              ],
            ),
            content: SizedBox(
              width: 620,
              height: 480,
              child: Column(
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '这里只清理 Reader 中的导入/扫描记录，不删除电脑上的原文件。清理后的路径也不会在以后自动扫描时重新加入。',
                      style: Theme.of(dialogContext).textTheme.bodySmall,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      TextButton.icon(
                        onPressed: () {
                          setDialogState(() {
                            if (allSelected) {
                              selected.clear();
                            } else {
                              selected
                                ..clear()
                                ..addAll(
                                  books
                                      .where((b) => b.id != null)
                                      .map((b) => b.id!),
                                );
                            }
                          });
                        },
                        icon: Icon(
                          allSelected
                              ? Icons.deselect_outlined
                              : Icons.select_all,
                        ),
                        label: Text(allSelected ? '取消全选' : '全选'),
                      ),
                      const Spacer(),
                      if (selectedCount > 0)
                        Text(
                          '将清理 $selectedCount 条记录',
                          style: Theme.of(dialogContext).textTheme.bodySmall,
                        ),
                    ],
                  ),
                  const Divider(height: 1),
                  const SizedBox(height: 4),
                  Expanded(
                    child: ListView.builder(
                      itemCount: books.length,
                      itemBuilder: (context, index) {
                        final book = books[index];
                        final id = book.id;
                        if (id == null) return const SizedBox.shrink();
                        final checked = selected.contains(id);
                        return CheckboxListTile(
                          value: checked,
                          onChanged: (value) {
                            setDialogState(() {
                              if (value == true) {
                                selected.add(id);
                              } else {
                                selected.remove(id);
                              }
                            });
                          },
                          secondary: Icon(
                            book.isAudio
                                ? Icons.headphones_outlined
                                : Icons.menu_book_outlined,
                          ),
                          title: Text(
                            book.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            '${book.format.toUpperCase()} · ${book.path}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          controlAffinity: ListTileControlAffinity.leading,
                          dense: true,
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('取消'),
              ),
              FilledButton.icon(
                onPressed: selected.isEmpty
                    ? null
                    : () async {
                        final count = selected.length;
                        await state.deleteBooks(
                          books.where(
                            (b) => b.id != null && selected.contains(b.id),
                          ),
                        );
                        if (dialogContext.mounted) {
                          Navigator.pop(dialogContext);
                        }
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('已清理 $count 条记录')),
                          );
                        }
                      },
                icon: const Icon(Icons.delete_sweep_outlined),
                label: Text(selected.isEmpty
                    ? '清理记录'
                    : '清理 $selectedCount 条'),
              ),
            ],
          );
        },
      );
    },
  );
}
