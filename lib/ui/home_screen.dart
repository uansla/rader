import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import 'bookshelf_screen.dart';
import 'library_screen.dart';
import 'player_screen.dart';
import 'reader_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  final List<String> initialOpenPaths;

  const HomeScreen({
    super.key,
    this.initialOpenPaths=const [],
  });

  @override
  State<HomeScreen> createState()=>_HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _index=0;
  bool _startupOpenScheduled=false;
  bool _startupOpenHandled=false;

  @override
  Widget build(BuildContext context) {
    final state=context.watch<AppState>();

    if (state.initialized &&
        widget.initialOpenPaths.isNotEmpty &&
        !_startupOpenScheduled &&
        !_startupOpenHandled) {
      _startupOpenScheduled=true;
      WidgetsBinding.instance.addPostFrameCallback((_)=>_openStartupFiles());
    }

    const pages=[
      BookshelfScreen(),
      LibraryScreen(),
      SettingsScreen(),
    ];

    return Scaffold(
      body:IndexedStack(index:_index,children:pages),
      bottomNavigationBar:NavigationBar(
        selectedIndex:_index,
        onDestinationSelected:(i)=>setState(()=>_index=i),
        destinations:const [
          NavigationDestination(
            icon:Icon(Icons.menu_book_outlined),
            selectedIcon:Icon(Icons.menu_book),
            label:'书架',
          ),
          NavigationDestination(
            icon:Icon(Icons.video_library_outlined),
            selectedIcon:Icon(Icons.video_library),
            label:'文库',
          ),
          NavigationDestination(
            icon:Icon(Icons.settings_outlined),
            selectedIcon:Icon(Icons.settings),
            label:'设置',
          ),
        ],
      ),
    );
  }

  Future<void> _openStartupFiles() async {
    if (!mounted || _startupOpenHandled) return;
    final state=context.read<AppState>();
    if (!state.initialized) {
      _startupOpenScheduled=false;
      return;
    }

    _startupOpenHandled=true;
    for (final path in widget.initialOpenPaths) {
      if (!mounted) return;
      final book=await state.openExternalFile(path);
      if (!mounted) return;

      if (book==null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content:Text('Reader 不支持或无法读取：$path')),
        );
        continue;
      }

      if (book.isAudio) {
        await Navigator.push(
          context,
          MaterialPageRoute(builder:(_)=>PlayerScreen(book:book)),
        );
      } else {
        await Navigator.push(
          context,
          MaterialPageRoute(builder:(_)=>ReaderScreen(book:book)),
        );
      }
    }
  }
}
