import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../core/app_settings.dart';
import '../services/font_manager.dart';
import 'lan_sync_screen.dart';
import 'stats_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final s = state.settings;
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          const _Header('阅读排版'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.format_size),
                  title: Text('默认字号 ${s.fontSize.round()}'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.remove),
                        onPressed: s.fontSize > 12
                            ? () => state.updateSettings(
                                s.copyWith(fontSize: s.fontSize - 1))
                            : null,
                      ),
                      IconButton(
                        icon: const Icon(Icons.add),
                        onPressed: s.fontSize < 30
                            ? () => state.updateSettings(
                                s.copyWith(fontSize: s.fontSize + 1))
                            : null,
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.flag_outlined),
                  title: Text('每日阅读目标 ${s.dailyTarget} 分钟'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.remove),
                        onPressed: s.dailyTarget > 5
                            ? () => state.updateSettings(s.copyWith(
                                dailyTarget: s.dailyTarget - 5))
                            : null,
                      ),
                      IconButton(
                        icon: const Icon(Icons.add),
                        onPressed: s.dailyTarget < 240
                            ? () => state.updateSettings(s.copyWith(
                                dailyTarget: s.dailyTarget + 5))
                            : null,
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  secondary: const Icon(Icons.brightness_medium),
                  title: const Text('跟随系统深色模式'),
                  value: s.followSystemDark,
                  onChanged: (v) =>
                      state.updateSettings(s.copyWith(followSystemDark: v)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          const _Header('朗读'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.speed),
                  title: const Text('朗读语速'),
                  subtitle: Slider(
                    value: s.ttsRate,
                    min: 0.3,
                    max: 0.8,
                    onChanged: (v) =>
                        state.updateSettings(s.copyWith(ttsRate: v)),
                  ),
                  trailing: Text(s.ttsRate.toStringAsFixed(2)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          const _Header('字体'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.font_download_outlined),
                  title: Text('自定义字体'),
                  subtitle: Text(s.customFontFamily.isEmpty
                      ? '未导入'
                      : s.customFontFamily),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.file_upload_outlined),
                        tooltip: '导入字体',
                        onPressed: () => _importFont(context, state, s),
                      ),
                      if (s.customFontFamily.isNotEmpty)
                        IconButton(
                          icon: const Icon(Icons.delete_outline),
                          tooltip: '移除字体',
                          onPressed: () async {
                            await FontManager.removeFont(s.customFontFamily);
                            await state.updateSettings(
                                s.copyWith(customFontFamily: ''));
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('已移除自定义字体')));
                            }
                          },
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          const _Header('统计与同步'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.bar_chart),
                  title: const Text('阅读统计'),
                  subtitle: const Text('热力图 / 每日目标 / 连续打卡'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const StatsScreen())),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.wifi_tethering),
                  title: const Text('局域网传书'),
                  subtitle: const Text('自动发现设备，在手机与电脑之间互传书籍'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const LanSyncScreen()),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.upload_file),
                  title: const Text('导出书架进度'),
                  subtitle: const Text('把阅读进度导出为 JSON 文件'),
                  onTap: () async {
                    final msg = await state.syncService.exportToFile();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context)
                          .showSnackBar(SnackBar(content: Text(msg)));
                    }
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.download),
                  title: const Text('导入进度并合并'),
                  subtitle: const Text('合并另一台设备的进度文件'),
                  onTap: () async {
                    final msg = await state.syncService.importFromFile();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context)
                          .showSnackBar(SnackBar(content: Text(msg)));
                    }
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          const _Header('备份'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.backup_outlined),
                  title: const Text('数据备份'),
                  subtitle: const Text('导出书架数据到文件'),
                  onTap: () => _backup(context, state),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.restore),
                  title: const Text('数据恢复'),
                  subtitle: const Text('从备份文件恢复'),
                  onTap: () => _restore(context, state),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.update),
                  title: const Text('自动备份'),
                  subtitle: const Text('启动时按间隔静默备份到应用目录'),
                  trailing: DropdownButton<int>(
                    value: s.autoBackupIntervalDays,
                    underline: const SizedBox.shrink(),
                    items: const [
                      DropdownMenuItem(value: 0, child: Text('关闭')),
                      DropdownMenuItem(value: 1, child: Text('每天')),
                      DropdownMenuItem(value: 7, child: Text('每周')),
                    ],
                    onChanged: (v) => state.updateSettings(
                        s.copyWith(autoBackupIntervalDays: v ?? 0)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          const _Header('关于'),
          const Card(
            child: ListTile(
              leading: Icon(Icons.info_outline),
              title: Text('Reader'),
              subtitle: Text('本地小说与有声书阅读器 v1.1.0'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _importFont(
      BuildContext context, AppState state, ReaderSettings s) async {
    final result = await FontManager.importFont();
    if (result == null) return;
    if (result == '复制字体失败' || result == '字体注册失败' || result.contains('失败')) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(result)));
      }
      return;
    }
    await state.updateSettings(s.copyWith(customFontFamily: result));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已导入字体「$result」，阅读时自动使用')));
    }
  }

  Future<void> _backup(BuildContext context, AppState state) async {
    final msg = await state.backupDatabase();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  Future<void> _restore(BuildContext context, AppState state) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('恢复数据'),
        content: const Text('恢复后将覆盖当前书架数据，是否继续？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true), child: const Text('恢复')),
        ],
      ),
    );
    if (ok != true) return;
    final msg = await state.restoreDatabase();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }
}

class _Header extends StatelessWidget {
  final String text;
  const _Header(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
            color: Theme.of(context).colorScheme.primary,
            fontWeight: FontWeight.bold),
      ),
    );
  }
}
