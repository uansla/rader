import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../../services/text_content_service.dart';

/// 整本连续滚动阅读视图。
/// 章节懒加载构建，通过逐章测量高度把滚动位置换算成 全局字符偏移 / 进度，
/// 与分章翻页模式共用同一套进度字段，可在两种模式间无缝续读。
class ScrollReaderView extends StatefulWidget {
  final BookSession session;
  final TextStyle style;
  final ReaderPalette palette;
  final EditableTextContextMenuBuilder? contextMenuBuilder;
  final double initialProgress;
  final ValueChanged<(int chapter, int charPos, double progress)> onProgress;
  final void Function() onScrolled;

  const ScrollReaderView({
    super.key,
    required this.session,
    required this.style,
    required this.palette,
    this.contextMenuBuilder,
    required this.initialProgress,
    required this.onProgress,
    required this.onScrolled,
  });

  @override
  State<ScrollReaderView> createState() => ScrollReaderViewState();
}

class ScrollReaderViewState extends State<ScrollReaderView> {
  final ScrollController _controller = ScrollController();
  final List<GlobalKey> _keys = [];
  final List<double> _heights = [];
  bool _heightsDirty = true;
  double? _avgCache;
  bool _restored = false;

  List<String> get _texts => widget.session.texts;
  List<String> get _titles => widget.session.titles;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onScroll);
    _keys.addAll(List.generate(_texts.length, (_) => GlobalKey()));
    _heights.addAll(List.filled(_texts.length, 0));
  }

  @override
  void dispose() {
    _controller.removeListener(_onScroll);
    _controller.dispose();
    super.dispose();
  }

  double _avgHeightPerChar() {
    if (!_heightsDirty && _avgCache != null) return _avgCache!;
    var chars = 0;
    var px = 0.0;
    for (var i = 0; i < _texts.length; i++) {
      if (_heights[i] > 0) {
        chars += _texts[i].length;
        px += _heights[i];
      }
    }
    _avgCache = chars > 0 ? px / chars : 0;
    _heightsDirty = false;
    return _avgCache!;
  }

  int get _totalChars {
    var sum = 0;
    for (final t in _texts) {
      sum += t.length;
    }
    return sum;
  }

  double get _maxScroll =>
      _controller.hasClients ? _controller.position.maxScrollExtent : 0;

  void _onScroll() {
    if (!_controller.hasClients) return;
    final offset = _controller.offset;
    final ratio = _maxScroll <= 0
        ? 0.0
        : (offset / _maxScroll).clamp(0.0, 1.0);
    final total = _totalChars;
    // 优先用已测量高度精确定位可见章节
    var chapter = _detectChapterMeasured(offset);
    if (chapter < 0) {
      // 快速滚动时中间章节尚未构建测量 → 用字符占比兜底，
      // 保证章节指示单调、不会错误跳到最后一章。
      chapter = _detectChapterByChar(ratio, total);
    }
    final charPos = (ratio * total).round();
    widget.onProgress((chapter, charPos, ratio));
    widget.onScrolled();
  }

  /// 单遍扫描 + 估算，O(n)；避免对每章重复累计（O(n²)/O(n³)）导致大书卡死。
  int _detectChapterMeasured(double offset) {
    final avg = _avgHeightPerChar();
    var acc = 0.0;
    for (var i = 0; i < _texts.length; i++) {
      final h = _heights[i];
      final top = acc;
      acc += h > 0 ? h : (avg <= 0 ? 0 : avg * _texts[i].length);
      if (h > 0 && offset < top + h * 0.8) return i;
    }
    return -1;
  }

  int _detectChapterByChar(double ratio, int total) {
    if (total <= 0 || _texts.isEmpty) return 0;
    final target = ratio * total;
    var acc = 0;
    for (var i = 0; i < _texts.length; i++) {
      acc += _texts[i].length;
      // 用严格大于：当恰好停在章节边界时，归到下一章（该章开头），避免 off-by-one。
      if (acc > target) return i;
    }
    return _texts.length - 1;
  }

  int _charsBefore(int idx) {
    var sum = 0;
    for (var i = 0; i < idx && i < _texts.length; i++) {
      sum += _texts[i].length;
    }
    return sum;
  }

  /// 计算第 idx 章的顶部位置。已测量的章节用实测高度，
  /// 未测量的按「平均每字符高度 × 字符数」估算，保证单调接近真实位置。
  double _cumulativeTop(int idx) {
    final avg = _avgHeightPerChar();
    var acc = 0.0;
    for (var i = 0; i < idx && i < _heights.length; i++) {
      final h = _heights[i];
      if (h > 0) {
        acc += h;
      } else if (avg > 0) {
        acc += avg * _texts[i].length;
      }
    }
    return acc;
  }

  /// 跳到指定章节（可定位到章节内字符位置）。
  /// 优先用实测高度精确定位，避免「字符占比」定位落在上一章内部，
  /// 导致滚动后章节检测又跳回旧章（表现为点击翻页震动、不前进）。
  void jumpToChapter(int idx, {int? charPos}) {
    if (idx < 0 || idx >= _texts.length || !mounted || !_controller.hasClients) {
      return;
    }
    var target = _cumulativeTop(idx);
    if (charPos != null && charPos > 0) {
      final len = _texts[idx].length;
      final h = idx < _heights.length ? _heights[idx] : 0;
      if (len > 0 && h > 0) {
        target += (charPos / len).clamp(0.0, 1.0) * h;
      }
    }
    // 兜底：前置章节完全未测量时按字符占比估算
    if (target <= 0) {
      final total = _totalChars;
      if (total > 0) {
        target = (_charsBefore(idx) / total).clamp(0.0, 1.0) * _maxScroll;
      }
    }
    _controller.animateTo(
      target.clamp(0.0, _maxScroll),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  void scrollToTop() {
    if (_controller.hasClients) _controller.jumpTo(0);
  }

  void _restore() {
    if (_restored || !_controller.hasClients) return;
    _restored = true;
    final target = widget.initialProgress.clamp(0.0, 1.0) * _maxScroll;
    if (target > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _controller.hasClients) {
          _controller.jumpTo(target.clamp(0.0, _maxScroll));
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _restore();
    });
    return ListView.builder(
      controller: _controller,
      itemCount: _texts.length,
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
      itemBuilder: (context, i) {
        // 布局后缓存本章实测高度，供滚动时 O(n) 单遍定位；只在本章高度变化时置脏。
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final ctx = _keys[i].currentContext;
          final h = ctx?.size?.height ?? 0;
          if (_heights[i] != h) {
            _heights[i] = h;
            _heightsDirty = true;
          }
        });
        return Column(
          key: _keys[i],
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (i > 0) ...[
              const SizedBox(height: 28),
              Container(height: 1, color: widget.palette.divider),
              const SizedBox(height: 16),
            ],
            Text(
              _titles[i],
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: widget.palette.accent,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 10),
            SelectableText(
              _texts[i],
              style: widget.style,
              contextMenuBuilder: widget.contextMenuBuilder,
              textScaler: TextScaler.linear(1),
            ),
          ],
        );
      },
    );
  }
}
