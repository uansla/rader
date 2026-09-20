import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../core/app_settings.dart';
import '../core/app_theme.dart';
import '../models/book.dart';
import '../models/bookmark.dart';
import '../models/note.dart';
import '../services/read_session.dart';
import '../services/text_content_service.dart';
import '../services/theme_scheduler.dart';
import '../services/tts_service.dart';
import 'reader/scroll_reader_view.dart';

class ReaderScreen extends StatefulWidget {
  final Book book;
  const ReaderScreen({super.key, required this.book});

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  late PageController _pageController;
  final GlobalKey<ScrollReaderViewState> _scrollKey =
      GlobalKey<ScrollReaderViewState>();
  BookSession? _session;
  late ReaderSettings _settings;
  late ReaderPalette _palette;
  int _chapter = 0;
  bool _showBar = true;
  bool _loading = true;
  bool _ttsPlaying = false;
  final List<GlobalKey> _pageKeys = [];
  Timer? _saveTimer;

  // 滚动模式进度
  int _scrollCharPos = 0;
  double _scrollOverall = 0.0;

  // 阅读计时 / 睡眠定时 / 亮度
  ReadSession? _readSession;
  SleepTimer? _sleepTimer;
  Duration? _sleepRemaining;
  double _brightness = 0.0;

  // 提前捕获 tts 引用，dispose 时 context 可能已失效
  TtsService? _tts;
  // 朗读高亮跟随
  int _ttsBaseOffset = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _tts ??= context.read<AppState>().tts;
  }

  @override
  void initState() {
    super.initState();
    final state = context.read<AppState>();
    _tts = state.tts;
    _settings = state.settings;
    _palette = _paletteFor(ThemeScheduler.resolve(_settings));
    _chapter = widget.book.chapterIndex.clamp(0, 1000000);
    _load();
  }

  ReaderPalette _paletteFor(ReaderThemeMode m) {
    switch (m) {
      case ReaderThemeMode.dark:
        return ReaderPalette.dark;
      case ReaderThemeMode.sepia:
        return ReaderPalette.sepia;
      case ReaderThemeMode.light:
        return ReaderPalette.light;
    }
  }

  void _reapplyTheme() {
    setState(() {
      _palette = _paletteFor(ThemeScheduler.resolve(_settings));
    });
  }

  bool get _scrollMode => _settings.pageMode == ReaderPageMode.scroll;

  Future<void> _load() async {
    final state = context.read<AppState>();
    final session = await state.openBook(widget.book);
    if (!mounted) return;
    setState(() {
      _session = session;
      _chapter = widget.book.chapterIndex.clamp(0, session.titles.length - 1);
      _scrollOverall = widget.book.progress;
      _scrollCharPos = widget.book.position;
      _pageKeys
        ..clear()
        ..addAll(List.generate(session.titles.length, (_) => GlobalKey()));
      _loading = false;
    });
    _pageController = PageController(initialPage: _chapter);
    _readSession = ReadSession(
      bookId: widget.book.id!,
      books: state.bookRepo,
      daily: state.readDailyRepo,
      onEyeRest: _showEyeRest,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _restorePosition();
    });
  }

  TextStyle get _textStyle => TextStyle(
        fontSize: _settings.fontSize,
        height: _settings.lineHeight,
        fontFamily: _settings.customFontFamily.isNotEmpty
            ? _settings.customFontFamily
            : (_settings.fontFamily.isEmpty ? null : _settings.fontFamily),
        color: _palette.text,
      );

  @override
  void dispose() {
    // 先停朗读（即使 _saveNow 抛异常也要停掉），用提前捕获的引用避免 context 失效
    try {
      _tts?.onFinished = null;
      _tts?.onProgress = null;
      _tts?.stop();
    } catch (_) {}
    _saveTimer?.cancel();
    _sleepTimer?.dispose();
    _readSession?.dispose();
    try {
      _saveNow();
    } catch (_) {}
    _pageController.dispose();
    super.dispose();
  }

  void _restorePosition() {
    final pos = widget.book.position;
    if (_scrollMode) {
      // 滚动模式由 ScrollReaderView 按 progress 恢复：
      // 此时 position 是「全局字符偏移」，不能当作章节内偏移使用，
      // 否则会过度跳转。这里只需让滚动视图按 initialProgress 定位即可。
      return;
    }
    final body = _pageKeys[_chapter].currentState as _ChapterBodyState?;
    if (body != null && pos > 0) {
      body.scrollToChar(pos);
    }
  }

  void _saveNow() {
    final state = context.read<AppState>();
    final session = _session;
    if (session == null) return;
    int chapter;
    int charOffset;
    double overall;
    if (_scrollMode) {
      chapter = _chapter;
      charOffset = _scrollCharPos;
      overall = _scrollOverall;
    } else {
      final body = _pageKeys[_chapter].currentState as _ChapterBodyState?;
      chapter = _chapter;
      charOffset = body?.charOffset ?? 0;
      final totalChars = session.texts[_chapter].length;
      final within = totalChars == 0 ? 0.0 : (charOffset / totalChars);
      overall = (session.titles.isEmpty)
          ? 0.0
          : ((chapter + within) / session.titles.length).clamp(0.0, 1.0);
    }
    state.updateProgress(
      widget.book,
      chapterIdx: chapter,
      position: charOffset,
      progress: overall,
    );
    if (overall >= 0.999 && !widget.book.completed) {
      state.bookRepo.setCompleted(widget.book.id!, true);
    }
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 600), _saveNow);
  }

  void _showEyeRest() {
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _palette.toolbar,
        title: Text('休息一下吧', style: TextStyle(color: _palette.toolbarText)),
        content: Text('已连续阅读 45 分钟，眺望远处放松眼睛～',
            style: TextStyle(color: _palette.toolbarText)),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('好的'),
          ),
        ],
      ),
    );
  }

  // ---------- 睡眠定时 ----------
  void _startSleepTimer(Duration d) {
    _sleepTimer?.dispose();
    _sleepRemaining = d;
    final state = context.read<AppState>();
    _sleepTimer = SleepTimer(() {
      state.tts.stop();
      if (mounted) {
        setState(() => _sleepRemaining = null);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('定时已到，已暂停朗读')),
        );
      }
    });
    _sleepTimer!.start(d);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${d.inMinutes} 分钟后自动暂停朗读')),
    );
  }

  void _showSleepDialog() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: _palette.toolbar,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text('15 分钟后', style: TextStyle(color: _palette.toolbarText)),
              onTap: () {
                _startSleepTimer(const Duration(minutes: 15));
                Navigator.pop(ctx);
              },
            ),
            ListTile(
              title: Text('30 分钟后', style: TextStyle(color: _palette.toolbarText)),
              onTap: () {
                _startSleepTimer(const Duration(minutes: 30));
                Navigator.pop(ctx);
              },
            ),
            ListTile(
              title: Text('60 分钟后', style: TextStyle(color: _palette.toolbarText)),
              onTap: () {
                _startSleepTimer(const Duration(minutes: 60));
                Navigator.pop(ctx);
              },
            ),
            if (_sleepRemaining != null)
              ListTile(
                title: const Text('取消定时'),
                onTap: () {
                  _sleepTimer?.dispose();
                  _sleepTimer = null;
                  setState(() => _sleepRemaining = null);
                  Navigator.pop(ctx);
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleTts() async {
    final tts = _tts;
    final session = _session!;
    final body = _pageKeys[_chapter].currentState as _ChapterBodyState?;
    if (_ttsPlaying) {
      tts?.onFinished = null;
      tts?.onProgress = null;
      await tts?.stop();
      setState(() => _ttsPlaying = false);
      return;
    }
    var text = session.texts[_chapter];
    final start = (body?.charOffset ?? 0).clamp(0, text.length);
    if (start < text.length) {
      text = text.substring(start);
    }
    _ttsBaseOffset = start;
    tts!.onFinished = _autoAdvanceTts;
    tts.onProgress = _onTtsProgress;
    final ok = await tts.speak(text);
    if (!ok) {
      tts.onFinished = null;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('未检测到语音引擎，无法朗读。\n可在系统设置中安装语音合成引擎后再试')),
        );
      }
      return;
    }
    setState(() => _ttsPlaying = true);
  }

  /// 读完当前章后自动翻到下一章继续读；到最后一章则停止。
  void _autoAdvanceTts() {
    if (!mounted) return;
    final tts = _tts;
    final session = _session;
    if (session == null || !_ttsPlaying) return;
    if (_chapter >= session.titles.length - 1) {
      tts?.onFinished = null;
      setState(() => _ttsPlaying = false);
      return;
    }
    final next = _chapter + 1;
    _gotoChapter(next);
    _ttsBaseOffset = 0;
    final text = session.texts[next];
    tts?.speak(text).then((ok) {
      if (!ok && mounted) setState(() => _ttsPlaying = false);
    });
  }

  /// 句子开始回调：滚动到当前朗读句，跟随阅读。
  void _onTtsProgress(int start, int end, double duration) {
    if (!mounted) return;
    _scrollToReading(_ttsBaseOffset + start);
  }

  void _scrollToReading(int pos) {
    if (!mounted) return;
    final body = _pageKeys[_chapter].currentState as _ChapterBodyState?;
    body?.scrollToPosition(pos);
  }

  Future<void> _gotoChapter(int idx) async {
    final n = _session!.titles.length;
    if (idx < 0 || idx >= n) return;
    _chapter = idx;
    if (_scrollMode) {
      _scrollKey.currentState?.jumpToChapter(idx);
    } else {
      _pageController.jumpToPage(idx);
    }
    _saveNow();
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollMode) return;
      final body = _pageKeys[idx].currentState as _ChapterBodyState?;
      body?.scrollToTop();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _session == null) {
      return Scaffold(
        backgroundColor: _palette.background,
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final session = _session!;
    final chapterTitle = session.titles[_chapter];

    final Widget content = _scrollMode
        ? ScrollReaderView(
            key: _scrollKey,
            session: session,
            style: _textStyle,
            palette: _palette,
            contextMenuBuilder: _buildTextMenu,
            initialProgress: widget.book.progress,
            onProgress: (t) {
              if (t.$1 != _chapter) {
                setState(() {
                  _chapter = t.$1;
                  _scrollCharPos = t.$2;
                  _scrollOverall = t.$3;
                });
              } else {
                _chapter = t.$1;
                _scrollCharPos = t.$2;
                _scrollOverall = t.$3;
              }
              _scheduleSave();
            },
            onScrolled: () {},
            onReadFromPosition: (chapter, position) {
              _speakFromChapterPosition(chapter, position);
            },
          )
        : PageView.builder(
            controller: _pageController,
            scrollDirection: Axis.horizontal,
            itemCount: session.titles.length,
            onPageChanged: (i) {
              _chapter = i;
              _saveNow();
              setState(() {});
              WidgetsBinding.instance.addPostFrameCallback((_) {
                final body = _pageKeys[i].currentState as _ChapterBodyState?;
                if (body != null && i == _chapter) body.scrollToTop();
              });
            },
            itemBuilder: (context, i) => _ChapterBody(
              key: _pageKeys[i],
              text: session.texts[i],
              style: _textStyle,
              palette: _palette,
              contextMenuBuilder: _buildTextMenu,
              onScroll: () => _scheduleSave(),
            ),
          );

    final keyboard = CallbackShortcuts(
      bindings: {
        LogicalKeySet(LogicalKeyboardKey.arrowRight):
            () => _gotoChapter(_chapter + 1),
        LogicalKeySet(LogicalKeyboardKey.arrowLeft):
            () => _gotoChapter(_chapter - 1),
        LogicalKeySet(LogicalKeyboardKey.space):
            () => _gotoChapter(_chapter + 1),
        const SingleActivator(LogicalKeyboardKey.keyF, control: true):
            _openSearch,
        LogicalKeySet(LogicalKeyboardKey.escape):
            () => setState(() => _showBar = !_showBar),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: _palette.background,
          body: Stack(
            children: [
              Positioned.fill(child: content),
              // 内容区点击手势：翻章 / 收起或唤出工具栏。
              // 放在工具栏下方，避免遮挡顶栏/底栏按钮的点击。
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTapUp: (d) {
                    final w = MediaQuery.of(context).size.width;
                    if (d.localPosition.dx < w * 0.3) {
                      if (_chapter > 0) _gotoChapter(_chapter - 1);
                    } else if (d.localPosition.dx > w * 0.7) {
                      if (_chapter < session.titles.length - 1) {
                        _gotoChapter(_chapter + 1);
                      }
                    } else {
                      setState(() => _showBar = !_showBar);
                    }
                  },
                ),
              ),
              if (_showBar) ...[
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: _TopBar(
                    book: widget.book,
                    chapterTitle: chapterTitle,
                    palette: _palette,
                    onBack: () => Navigator.pop(context),
                    onSettings: _openSettings,
                    onToc: _openToc,
                  ),
                ),
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: _BottomBar(
                    palette: _palette,
                    chapter: _chapter,
                    total: session.titles.length,
                    scrollMode: _scrollMode,
                    scrollOverall: _scrollOverall,
                    isTtsPlaying: _ttsPlaying,
                    isSleepActive: _sleepRemaining != null,
                    onPrev:
                        _chapter > 0 ? () => _gotoChapter(_chapter - 1) : null,
                    onNext: _chapter < session.titles.length - 1
                        ? () => _gotoChapter(_chapter + 1)
                        : null,
                    onSearch: _openSearch,
                    onBookmark: _toggleBookmark,
                    onNote: _openNoteDialog,
                    onTts: _toggleTts,
                    onSleep: _showSleepDialog,
                    onSliderChanged: (v) =>
                        _gotoChapter((v * session.titles.length).floor()),
                  ),
                ),
              ],
              if (!_showBar)
                Positioned(
                  top: MediaQuery.of(context).padding.top + 8,
                  right: 8,
                  child: IconButton(
                    icon: Icon(Icons.menu, color: _palette.subtle),
                    onPressed: () => setState(() => _showBar = true),
                  ),
                ),
              // 页内亮度遮罩
              IgnorePointer(
                child: Container(
                  color: Colors.black.withValues(alpha: _brightness),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    return keyboard;
  }

  Widget _buildTextMenu(
      BuildContext context, EditableTextState editableTextState) {
    final buttons = <ContextMenuButtonItem>[
      ContextMenuButtonItem(
        label: '朗读所选文字',
        onPressed: () {
          final val = editableTextState.textEditingValue;
          final selected = val.selection.textInside(val.text);
          editableTextState.hideToolbar();
          if (selected.trim().isNotEmpty) {
            _speakSelectedText(selected);
          }
        },
      ),
      ContextMenuButtonItem(
        label: '从这里开始朗读',
        onPressed: () {
          final val = editableTextState.textEditingValue;
          final start = val.selection.isValid ? val.selection.start : -1;
          editableTextState.hideToolbar();
          if (start >= 0) {
            _speakFromPosition(start);
          }
        },
      ),
      ...editableTextState.contextMenuButtonItems,
      ContextMenuButtonItem(
        label: '全书搜索',
        onPressed: () {
          final val = editableTextState.textEditingValue;
          final q = val.selection.textInside(val.text);
          editableTextState.hideToolbar();
          if (q.isNotEmpty) _openSearch(initialQuery: q);
        },
      ),
    ];
    return AdaptiveTextSelectionToolbar.buttonItems(
      anchors: editableTextState.contextMenuAnchors,
      buttonItems: buttons,
    );
  }

  Future<void> _speakSelectedText(String selected) async {
    final tts = _tts;
    if (tts == null) return;
    await tts.stop();
    _ttsBaseOffset = 0;
    tts.onFinished = null;
    tts.onProgress = _onTtsProgress;
    final ok = await tts.speak(selected);
    if (!mounted) return;
    setState(() => _ttsPlaying = ok);
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('未检测到可用的离线语音引擎')),
      );
    }
  }

  Future<void> _speakFromChapterPosition(int chapter, int start) async {
    final session = _session;
    final tts = _tts;
    if (session == null || tts == null) return;
    if (chapter < 0 || chapter >= session.texts.length) return;

    final text = session.texts[chapter];
    final safeStart = start.clamp(0, text.length);
    if (safeStart >= text.length) return;

    _chapter = chapter;
    if (_scrollMode) {
      _scrollKey.currentState?.jumpToChapter(chapter, charPos: safeStart);
    } else {
      _pageController.jumpToPage(chapter);
    }
    await tts.stop();
    _ttsBaseOffset = safeStart;
    tts.onFinished = _autoAdvanceTts;
    tts.onProgress = _onTtsProgress;
    final ok = await tts.speak(text.substring(safeStart));
    if (!mounted) return;
    if (ok) {
      _scrollToReading(safeStart);
      setState(() => _ttsPlaying = true);
    } else {
      tts.onFinished = null;
      tts.onProgress = null;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('未检测到可用的离线语音引擎')),
      );
    }
  }

  Future<void> _speakFromPosition(int start) async {
    final session = _session;
    final tts = _tts;
    if (session == null || tts == null) return;
    final text = session.texts[_chapter];
    final safeStart = start.clamp(0, text.length);
    if (safeStart >= text.length) return;

    await tts.stop();
    _ttsBaseOffset = safeStart;
    tts.onFinished = _autoAdvanceTts;
    tts.onProgress = _onTtsProgress;
    final ok = await tts.speak(text.substring(safeStart));
    if (!mounted) return;
    if (ok) {
      _scrollToReading(safeStart);
      setState(() => _ttsPlaying = true);
    } else {
      tts.onFinished = null;
      tts.onProgress = null;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('未检测到可用的离线语音引擎')),
      );
    }
  }

  void _openSettings() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: _palette.toolbar,
      isScrollControlled: true,
      builder: (ctx) => _FontSettingsSheet(
        settings: _settings,
        palette: _palette,
        brightness: _brightness,
        onBrightness: (v) => setState(() => _brightness = v),
        onChanged: (s) {
          setState(() => _settings = s);
          context.read<AppState>().updateSettings(s);
          _reapplyTheme();
        },
      ),
    );
  }

  void _openToc() {
    final session = _session!;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: _palette.toolbar,
      builder: (ctx) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: ListView.builder(
          itemCount: session.titles.length,
          itemBuilder: (context, i) => ListTile(
            dense: true,
            title: Text(
              session.titles[i],
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: i == _chapter ? _palette.accent : _palette.toolbarText,
                fontWeight: i == _chapter ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            onTap: () {
              Navigator.pop(ctx);
              _gotoChapter(i);
            },
          ),
        ),
      ),
    );
  }

  void _openSearch({String? initialQuery}) {
    final session = _session!;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: _palette.toolbar,
      isScrollControlled: true,
      builder: (ctx) {
        final controller = TextEditingController(text: initialQuery ?? '');
        final results = <(int, int, String)>[];
        if ((initialQuery ?? '').trim().isNotEmpty) {
          results.addAll(_searchInBook(initialQuery!.trim()));
        }
        return StatefulBuilder(
          builder: (ctx, setSheetState) => Padding(
            padding:
                EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: TextField(
                    controller: controller,
                    autofocus: initialQuery == null,
                    style: TextStyle(color: _palette.toolbarText),
                    decoration: InputDecoration(
                      hintText: '全书搜索',
                      hintStyle: TextStyle(color: _palette.subtle),
                      border: const OutlineInputBorder(),
                    ),
                    onSubmitted: (q) {
                      if (q.trim().isEmpty) return;
                      results
                        ..clear()
                        ..addAll(_searchInBook(q.trim()));
                      setSheetState(() {});
                    },
                  ),
                ),
                if (results.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text('输入关键词后回车搜索',
                        style: TextStyle(color: _palette.subtle)),
                  )
                else
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: results.length,
                      itemBuilder: (context, i) {
                        final r = results[i];
                        return ListTile(
                          dense: true,
                          title: Text(
                            '${session.titles[r.$1]}  ·  ${r.$3.length > 30 ? r.$3.substring(0, 30) : r.$3}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: _palette.toolbarText),
                          ),
                          onTap: () {
                            Navigator.pop(ctx);
                            _gotoChapter(r.$1);
                            if (_scrollMode) {
                              _scrollKey.currentState
                                  ?.jumpToChapter(r.$1, charPos: r.$2);
                            } else {
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                final body = _pageKeys[r.$1].currentState
                                    as _ChapterBodyState?;
                                body?.scrollToChar(r.$2);
                              });
                            }
                          },
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  List<(int, int, String)> _searchInBook(String q) {
    final session = _session!;
    final res = <(int, int, String)>[];
    final lower = q.toLowerCase();
    for (var c = 0; c < session.texts.length && res.length < 200; c++) {
      final text = session.texts[c];
      var idx = text.toLowerCase().indexOf(lower);
      while (idx != -1 && res.length < 200) {
        res.add((c, idx, text.substring(idx, (idx + 40).clamp(0, text.length))));
        idx = text.toLowerCase().indexOf(lower, idx + 1);
      }
    }
    return res;
  }

  Future<void> _toggleBookmark() async {
    final state = context.read<AppState>();
    final body = _pageKeys[_chapter].currentState as _ChapterBodyState?;
    final pos = body?.charOffset ?? 0;
    final text = _session!.texts[_chapter];
    final snippet = text.length > 40
        ? text.substring(pos, (pos + 40).clamp(0, text.length))
        : text;
    await state.bookmarkRepo.add(Bookmark(
      bookId: widget.book.id!,
      chapterIdx: _chapter,
      position: pos,
      text: snippet,
      createdAt: DateTime.now(),
    ));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('已添加书签'),
          backgroundColor: _palette.accent,
        ),
      );
    }
  }

  Future<void> _openNoteDialog() async {
    final state = context.read<AppState>();
    final body = _pageKeys[_chapter].currentState as _ChapterBodyState?;
    final pos = body?.charOffset ?? 0;
    final text = _session!.texts[_chapter];
    final snippet = text.length > 40
        ? text.substring(pos, (pos + 40).clamp(0, text.length))
        : text;
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _palette.toolbar,
        title: Text('添加笔记', style: TextStyle(color: _palette.toolbarText)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _palette.background,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(snippet,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: _palette.text, fontSize: 13)),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              maxLines: 3,
              style: TextStyle(color: _palette.toolbarText),
              decoration: const InputDecoration(hintText: '写下你的想法…'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (result != null && result.trim().isNotEmpty) {
      await state.noteRepo.add(Note(
        bookId: widget.book.id!,
        chapterIdx: _chapter,
        position: pos,
        text: result.trim(),
        createdAt: DateTime.now(),
      ));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('笔记已保存')),
        );
      }
    }
  }
}

class _TopBar extends StatelessWidget {
  final Book book;
  final String chapterTitle;
  final ReaderPalette palette;
  final VoidCallback onBack;
  final VoidCallback onSettings;
  final VoidCallback onToc;
  const _TopBar({
    required this.book,
    required this.chapterTitle,
    required this.palette,
    required this.onBack,
    required this.onSettings,
    required this.onToc,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: palette.toolbar.withValues(alpha: 0.96),
      padding:
          EdgeInsets.only(top: MediaQuery.of(context).padding.top + 4, bottom: 4),
      child: Row(
        children: [
          IconButton(
            icon: Icon(Icons.arrow_back, color: palette.toolbarText),
            onPressed: onBack,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(book.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: palette.toolbarText,
                        fontSize: 15,
                        fontWeight: FontWeight.bold)),
                Text(chapterTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: palette.subtle, fontSize: 12)),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.list, color: palette.toolbarText),
            onPressed: onToc,
            tooltip: '目录',
          ),
          IconButton(
            icon: Icon(Icons.text_fields, color: palette.toolbarText),
            onPressed: onSettings,
            tooltip: '排版',
          ),
        ],
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  final ReaderPalette palette;
  final int chapter;
  final int total;
  final bool scrollMode;
  final double scrollOverall;
  final bool isTtsPlaying;
  final bool isSleepActive;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;
  final VoidCallback onSearch;
  final VoidCallback onBookmark;
  final VoidCallback onNote;
  final VoidCallback onTts;
  final VoidCallback onSleep;
  final ValueChanged<double> onSliderChanged;
  const _BottomBar({
    required this.palette,
    required this.chapter,
    required this.total,
    required this.scrollMode,
    required this.scrollOverall,
    required this.isTtsPlaying,
    required this.isSleepActive,
    required this.onPrev,
    required this.onNext,
    required this.onSearch,
    required this.onBookmark,
    required this.onNote,
    required this.onTts,
    required this.onSleep,
    required this.onSliderChanged,
  });

  @override
  Widget build(BuildContext context) {
    final c = palette.toolbarText;
    return Container(
      color: palette.toolbar.withValues(alpha: 0.96),
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom + 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Slider(
            value: total == 0
                ? 0
                : (scrollMode ? scrollOverall : (chapter + 1) / total)
                    .clamp(0.0, 1.0),
            onChanged: onSliderChanged,
            activeColor: palette.accent,
            inactiveColor: palette.divider,
          ),
          Row(
            children: [
              IconButton(
                icon: Icon(Icons.skip_previous, color: c),
                onPressed: onPrev,
                tooltip: '上一章',
              ),
              IconButton(
                icon: Icon(Icons.search, color: c),
                onPressed: onSearch,
                tooltip: '搜索',
              ),
              IconButton(
                icon: Icon(Icons.bookmark_add_outlined, color: c),
                onPressed: onBookmark,
                tooltip: '加书签',
              ),
              IconButton(
                icon: Icon(Icons.edit_note, color: c),
                onPressed: onNote,
                tooltip: '笔记',
              ),
              IconButton(
                icon: Icon(
                  isTtsPlaying
                      ? Icons.record_voice_over
                      : Icons.play_circle_outline,
                  color: isTtsPlaying ? palette.accent : c,
                ),
                onPressed: onTts,
                tooltip: '朗读',
              ),
              IconButton(
                icon: Icon(
                  Icons.bedtime_outlined,
                  color: isSleepActive ? palette.accent : c,
                ),
                onPressed: onSleep,
                tooltip: '定时关闭',
              ),
              IconButton(
                icon: Icon(Icons.skip_next, color: c),
                onPressed: onNext,
                tooltip: '下一章',
              ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Text('${chapter + 1}/$total',
                    style: TextStyle(color: palette.subtle, fontSize: 12)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ChapterBody extends StatefulWidget {
  final String text;
  final TextStyle style;
  final ReaderPalette palette;
  final EditableTextContextMenuBuilder? contextMenuBuilder;
  final VoidCallback onScroll;
  const _ChapterBody({
    super.key,
    required this.text,
    required this.style,
    required this.palette,
    this.contextMenuBuilder,
    required this.onScroll,
  });

  @override
  State<_ChapterBody> createState() => _ChapterBodyState();
}

class _ChapterBodyState extends State<_ChapterBody> {
  static const double _padL = 18;
  static const double _padR = 18;
  static const double _padT = 12;

  final ScrollController _controller = ScrollController();
  TextPainter? _painter;
  double _width = 0;

  @override
  void initState() {
    super.initState();
    _controller.addListener(widget.onScroll);
  }

  @override
  void dispose() {
    _controller.removeListener(widget.onScroll);
    _controller.dispose();
    super.dispose();
  }

  /// 文本实际排版宽度 = 可用宽度 - 左右 padding。
  double get _textWidth =>
      (_width - _padL - _padR).clamp(0.0, double.infinity);

  int get charOffset {
    final tp = _painter;
    if (tp == null) return 0;
    // 可见区顶部对应文本内的 dy = 滚动偏移 - 顶部 padding
    final dy = (_controller.offset - _padT).clamp(0.0, double.infinity);
    final pos = tp.getPositionForOffset(Offset(0, dy));
    return pos.offset.clamp(0, widget.text.length);
  }

  /// 滚动到朗读位置所在行，跟随阅读。
  void scrollToPosition(int pos) {
    final tp = _painter;
    if (tp == null || !mounted) return;
    final bounded = pos.clamp(0, widget.text.length);
    final dy =
        tp.getOffsetForCaret(TextPosition(offset: bounded), Rect.zero).dy;
    final target =
        (dy + _padT).clamp(0.0, _controller.position.maxScrollExtent);
    _controller.jumpTo(target);
  }

  void scrollToChar(int offset) {
    final tp = _painter;
    if (tp == null || offset <= 0) return;
    final dy =
        tp.getOffsetForCaret(TextPosition(offset: offset), Rect.zero).dy;
    final target = (dy + _padT)
        .clamp(0.0, _controller.position.maxScrollExtent);
    _controller.jumpTo(target);
  }

  void scrollToTop() {
    if (_controller.hasClients) _controller.jumpTo(0);
  }

  void _layoutPainter() {
    final textStyle = widget.style;
    _painter = TextPainter(
      text: TextSpan(text: widget.text, style: textStyle),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: _textWidth);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _width = constraints.maxWidth;
        _layoutPainter();
        return SingleChildScrollView(
          controller: _controller,
          padding: EdgeInsets.fromLTRB(_padL, _padT, _padR, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SelectableText(
                widget.text,
                style: widget.style,
                contextMenuBuilder: widget.contextMenuBuilder,
                textScaler: TextScaler.linear(1),
              ),
              const SizedBox(height: 40),
            ],
          ),
        );
      },
    );
  }
}

class _FontSettingsSheet extends StatefulWidget {
  final ReaderSettings settings;
  final ReaderPalette palette;
  final double brightness;
  final ValueChanged<double> onBrightness;
  final ValueChanged<ReaderSettings> onChanged;
  const _FontSettingsSheet({
    required this.settings,
    required this.palette,
    required this.brightness,
    required this.onBrightness,
    required this.onChanged,
  });

  @override
  State<_FontSettingsSheet> createState() => _FontSettingsSheetState();
}

class _FontSettingsSheetState extends State<_FontSettingsSheet> {
  late double _fontSize;
  late double _lineHeight;
  late ReaderThemeMode _mode;
  late String _fontFamily;
  late bool _themeAuto;
  late ReaderPageMode _pageMode;
  late double _brightness;

  @override
  void initState() {
    super.initState();
    _fontSize = widget.settings.fontSize;
    _lineHeight = widget.settings.lineHeight;
    _mode = widget.settings.themeMode;
    _fontFamily = widget.settings.fontFamily;
    _themeAuto = widget.settings.themeAuto;
    _pageMode = widget.settings.pageMode;
    _brightness = widget.brightness;
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.palette.toolbarText;
    void emit() {
      widget.onChanged(widget.settings.copyWith(
        fontSize: _fontSize,
        lineHeight: _lineHeight,
        themeMode: _mode,
        fontFamily: _fontFamily,
        themeAuto: _themeAuto,
        pageMode: _pageMode,
      ));
    }

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('排版设置',
                style: TextStyle(color: c, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Row(
              children: [
                Text('字号', style: TextStyle(color: c)),
                Expanded(
                  child: Slider(
                    value: _fontSize,
                    min: 12,
                    max: 30,
                    onChanged: (v) => setState(() {
                      _fontSize = v;
                      emit();
                    }),
                    activeColor: widget.palette.accent,
                  ),
                ),
                Text('${_fontSize.round()}', style: TextStyle(color: c)),
              ],
            ),
            Row(
              children: [
                Text('行距', style: TextStyle(color: c)),
                Expanded(
                  child: Slider(
                    value: _lineHeight,
                    min: 1.2,
                    max: 2.6,
                    onChanged: (v) => setState(() {
                      _lineHeight = v;
                      emit();
                    }),
                    activeColor: widget.palette.accent,
                  ),
                ),
                Text(_lineHeight.toStringAsFixed(1),
                    style: TextStyle(color: c)),
              ],
            ),
            Row(
              children: [
                Text('亮度', style: TextStyle(color: c)),
                Expanded(
                  child: Slider(
                    value: _brightness,
                    min: 0,
                    max: 0.8,
                    onChanged: (v) => setState(() {
                      _brightness = v;
                      widget.onBrightness(v);
                    }),
                    activeColor: widget.palette.accent,
                  ),
                ),
                Text('${(_brightness * 100).round()}%',
                    style: TextStyle(color: c)),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text('主题', style: TextStyle(color: c)),
                const SizedBox(width: 12),
                SegmentedButton<ReaderThemeMode>(
                  segments: const [
                    ButtonSegment(
                        value: ReaderThemeMode.light,
                        icon: Icon(Icons.light_mode),
                        label: Text('日')),
                    ButtonSegment(
                        value: ReaderThemeMode.sepia,
                        icon: Icon(Icons.wb_sunny),
                        label: Text('护眼')),
                    ButtonSegment(
                        value: ReaderThemeMode.dark,
                        icon: Icon(Icons.dark_mode),
                        label: Text('夜')),
                  ],
                  selected: {_mode},
                  showSelectedIcon: false,
                  onSelectionChanged: (s) => setState(() {
                    _mode = s.first;
                    _themeAuto = false;
                    emit();
                  }),
                ),
              ],
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('按时段自动切换主题', style: TextStyle(color: c)),
              subtitle: Text('18点后护眼，23点后夜间',
                  style: TextStyle(color: widget.palette.subtle, fontSize: 12)),
              value: _themeAuto,
              activeTrackColor: widget.palette.accent,
              onChanged: (v) => setState(() {
                _themeAuto = v;
                emit();
              }),
            ),
            Row(
              children: [
                Text('翻页', style: TextStyle(color: c)),
                const SizedBox(width: 12),
                SegmentedButton<ReaderPageMode>(
                  segments: const [
                    ButtonSegment(
                        value: ReaderPageMode.paged,
                        icon: Icon(Icons.auto_stories),
                        label: Text('分章')),
                    ButtonSegment(
                        value: ReaderPageMode.scroll,
                        icon: Icon(Icons.view_agenda),
                        label: Text('整本滚动')),
                  ],
                  selected: {_pageMode},
                  showSelectedIcon: false,
                  onSelectionChanged: (s) => setState(() {
                    _pageMode = s.first;
                    emit();
                  }),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Text('字体', style: TextStyle(color: c)),
                const SizedBox(width: 12),
                DropdownButton<String>(
                  value: _fontFamily,
                  dropdownColor: widget.palette.toolbar,
                  style: TextStyle(color: c),
                  items: const [
                    DropdownMenuItem(value: '', child: Text('系统默认')),
                    DropdownMenuItem(value: 'serif', child: Text('衬线')),
                    DropdownMenuItem(value: 'monospace', child: Text('等宽')),
                  ],
                  onChanged: (v) => setState(() {
                    _fontFamily = v ?? '';
                    emit();
                  }),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
