import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';

/// 阅读统计页：365 天日历热力图 + 今日/目标/连续打卡汇总。
class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  Map<String, int> _daily = {};
  bool _loading = true;
  int _todayMinutes = 0;
  int _streak = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final state = context.read<AppState>();
    final now = DateTime.now();
    final from = now.subtract(const Duration(days: 364));
    final map = await state.readDailyRepo.range(from, now);
    final today = await state.readDailyRepo.minutesOn(now);
    final streak = await state.readDailyRepo.streak();
    if (!mounted) return;
    setState(() {
      _daily = map;
      _todayMinutes = today;
      _streak = streak;
      _loading = false;
    });
  }

  Color _colorFor(int minutes) {
    final scheme = Theme.of(context).colorScheme;
    if (minutes <= 0) {
      return scheme.surfaceContainerHighest.withValues(alpha: 0.45);
    }
    if (minutes < 15) return scheme.primary.withValues(alpha: 0.3);
    if (minutes < 30) return scheme.primary.withValues(alpha: 0.5);
    if (minutes < 60) return scheme.primary.withValues(alpha: 0.75);
    return scheme.primary;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final target = context.watch<AppState>().settings.dailyTarget;
    return Scaffold(
      appBar: AppBar(title: const Text('阅读统计')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _Stat(
                            value: '$_todayMinutes',
                            label: '今日阅读(分)'),
                        _Stat(
                            value: '$_todayMinutes/$target',
                            label: '每日目标'),
                        _Stat(value: '$_streak', label: '连续打卡(天)'),
                      ],
                    ),
                  ),
                ),
                if (target > 0 && _todayMinutes < target)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '距今日目标还差 ${target - _todayMinutes} 分钟',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: scheme.primary),
                    ),
                  ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('近 365 天阅读热力图',
                            style: Theme.of(context).textTheme.titleSmall),
                        const SizedBox(height: 4),
                        Text('颜色越深读得越久 · 点格子看当天',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: scheme.outline)),
                        const SizedBox(height: 12),
                        _Heatmap(daily: _daily, colorFor: _colorFor),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String value;
  final String label;
  const _Stat({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.primary)),
        const SizedBox(height: 2),
        Text(label,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: Theme.of(context).colorScheme.outline)),
      ],
    );
  }
}

class _Heatmap extends StatelessWidget {
  final Map<String, int> daily;
  final Color Function(int minutes) colorFor;

  const _Heatmap({required this.daily, required this.colorFor});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final end = now;
    final start = now.subtract(const Duration(days: 363));

    // 起始对齐到周一，保证每列固定 7 行
    final startWeekday = start.weekday; // 1=Mon
    final offset = startWeekday - 1;
    final gridStart = start.subtract(Duration(days: offset));

    final days = gridStart.difference(end).inDays.abs() + 1;
    final weeks = (days / 7).ceil();

    final size = 14.0;
    final gap = 3.0;

    return SizedBox(
      height: size * 7 + gap * 6,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var w = 0; w < weeks; w++)
              Padding(
                padding: EdgeInsets.only(right: gap),
                child: Column(
                  children: [
                    for (var d = 0; d < 7; d++)
                      Padding(
                        padding: EdgeInsets.only(bottom: gap),
                        child: _Cell(
                          date: gridStart.add(Duration(days: w * 7 + d)),
                          minutes: _minutes(gridStart, w, d),
                          color: colorFor(_minutes(gridStart, w, d)),
                          today: _isToday(gridStart, w, d, end),
                          size: size,
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  int _minutes(DateTime gridStart, int w, int d) {
    final date = gridStart.add(Duration(days: w * 7 + d));
    final key = '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
    return daily[key] ?? 0;
  }

  bool _isToday(DateTime gridStart, int w, int d, DateTime end) {
    final date = gridStart.add(Duration(days: w * 7 + d));
    return date.year == end.year &&
        date.month == end.month &&
        date.day == end.day;
  }
}

class _Cell extends StatelessWidget {
  final DateTime date;
  final int minutes;
  final Color color;
  final bool today;
  final double size;

  const _Cell({
    required this.date,
    required this.minutes,
    required this.color,
    required this.today,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '${date.year}-${date.month.toString().padLeft(2, '0')}-'
          '${date.day.toString().padLeft(2, '0')}\n'
          '${minutes > 0 ? '读了 $minutes 分钟' : '没有阅读'}',
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(3),
          border: today ? Border.all(color: Colors.white, width: 1.5) : null,
        ),
      ),
    );
  }
}
