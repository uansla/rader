import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../app_state.dart';
import '../services/discovery_service.dart';
import '../services/format_detector.dart';

class LanSyncScreen extends StatefulWidget {
  const LanSyncScreen({super.key});

  @override
  State<LanSyncScreen> createState() => _LanSyncScreenState();
}

class _LanSyncScreenState extends State<LanSyncScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;
  HttpServer? _server;
  String? _ip;
  final List<String> _received = [];
  bool _hosting = false;
  String? _hostError;
  bool _sending = false;
  String? _sendResult;

  DiscoveryService? _discovery;
  Timer? _pollTimer;
  Timer? _httpScanTimer;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _startDiscovery();
    _pollTimer = Timer.periodic(const Duration(milliseconds: 1500), (_) {
      if (mounted) setState(() {});
    });
    // TCP/HTTP 可靠发现：周期扫描子网接收端
    _httpScanTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      _discovery?.scanViaHttp();
    });
    _discovery?.scanViaHttp();
  }

  Future<void> _startDiscovery() async {
    final discovery = DiscoveryService(
      name: await _deviceName(),
      portGetter: () => _server?.port ?? 0,
    );
    _discovery = discovery;
    await discovery.start();
  }

  Future<String> _deviceName() async {
    // Android 上 Platform.localHostname 常返回 localhost，改用原生 Build.MODEL
    if (!kIsWeb && Platform.isAndroid) {
      try {
        const ch = MethodChannel('reader/multicast');
        final model = await ch.invokeMethod<String>('getDeviceName');
        if (model != null && model.isNotEmpty) return 'Reader-$model';
      } catch (_) {}
    }
    final hostname = Platform.localHostname;
    return 'Reader-${hostname.isNotEmpty ? hostname : '设备'}';
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _httpScanTimer?.cancel();
    _discovery?.dispose();
    _server?.close();
    _tab.dispose();
    super.dispose();
  }

  // ---------- HTTP 接收 ----------
  Future<void> _startServer() async {
    try {
      _ip = await _getLocalIp();
      _server = await HttpServer.bind(InternetAddress.anyIPv4, 8765);
      _server!.listen(_handleRequest);
      setState(() {
        _hosting = true;
        _hostError = null;
      });
    } catch (e) {
      setState(() => _hostError = '启动失败：$e');
    }
  }

  Future<void> _stopServer() async {
    await _server?.close();
    setState(() {
      _hosting = false;
      _server = null;
    });
  }

  Future<String?> _getLocalIp() async {
    try {
      final interfaces = await NetworkInterface.list(
          type: InternetAddressType.IPv4, includeLoopback: false);
      for (final i in interfaces) {
        for (final addr in i.addresses) {
          final s = addr.address;
          if (s.startsWith('192.168.') ||
              s.startsWith('10.') ||
              s.startsWith('172.')) {
            return s;
          }
        }
      }
      if (interfaces.isNotEmpty && interfaces.first.addresses.isNotEmpty) {
        return interfaces.first.addresses.first.address;
      }
    } catch (_) {}
    return null;
  }

  Future<void> _handleRequest(HttpRequest req) async {
    try {
      if (req.method == 'PUT' && req.uri.path == '/upload') {
        final rawName = req.headers.value('X-Filename') ?? 'file.dat';
        final name = Uri.decodeComponent(rawName);
        final safeName =
            p.basename(name).replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
        final state = context.read<AppState>();
        final dir = await state.getBooksDirectory();
        final dest = p.join(dir.path, safeName);
        final builder = BytesBuilder();
        await for (final chunk in req) {
          builder.add(chunk);
        }
        await File(dest).writeAsBytes(builder.takeBytes());
        req.response.statusCode = 200;
        req.response.headers.contentType = ContentType.text;
        req.response.write('ok');
        await req.response.close();
        if (mounted) {
          setState(() => _received.add(safeName));
          state.scan(dirs: [dir.path]);
        }
      } else if (req.method == 'GET' && req.uri.path == '/api/info') {
        // 供局域网发现：返回设备信息 JSON
        final name = await _deviceName();
        req.response.headers.contentType = ContentType.json;
        req.response.write(
            '{"app":"reader-sync","name":${jsonEncode(name)},'
            '"host":"${_ip ?? ''}","port":${_server?.port ?? 0}}');
        await req.response.close();
      } else if (req.method == 'GET' && req.uri.path == '/') {
        req.response.headers.contentType = ContentType.html;
        req.response.write('''
          <html><head><meta charset="utf-8"><title>Reader 传书</title></head>
          <body style="font-family:sans-serif;text-align:center;margin-top:80px">
            <h2>Reader 局域网传书</h2>
            <p>接收端已就绪。请使用另一台设备的 Reader 客户端发送书籍。</p>
          </body></html>
        ''');
        await req.response.close();
      } else {
        req.response.statusCode = 404;
        await req.response.close();
      }
    } catch (_) {
      try {
        req.response.statusCode = 500;
        await req.response.close();
      } catch (_) {}
    }
  }

  // ---------- 发送 ----------
  Future<void> _pickAndSend({String? host, int? port}) async {
    String base;
    if (host != null && port != null) {
      base = '$host:$port';
    } else {
      final controller = TextEditingController();
      final input = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('输入接收端地址'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
                hintText: '例如 192.168.1.5:8765'),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, controller.text.trim()),
                child: const Text('下一步')),
          ],
        ),
      );
      if (input == null || input.isEmpty) return;
      base = input;
    }

    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: const [
        'txt', 'epub', 'mobi', 'azw3', 'html', 'htm', 'md', 'markdown', 'fb2',
        'mp3', 'm4a', 'aac', 'wav', 'flac', 'ogg', 'opus', 'm4b', 'amr',
      ],
    );
    if (result == null || result.files.isEmpty) return;
    final files = result.files
        .map((f) => f.path)
        .whereType<String>()
        .where((e) => FormatDetector.detectFormat(e) != null)
        .toList();
    if (files.isEmpty) return;

    setState(() {
      _sending = true;
      _sendResult = null;
    });
    final uriHost = base.contains('://') ? base : 'http://$base';
    final uri = Uri.parse('$uriHost/upload');
    var ok = 0;
    var fail = 0;
    for (final f in files) {
      try {
        final client = HttpClient()
          ..connectionTimeout = const Duration(seconds: 10);
        final req = await client.putUrl(uri);
        req.headers.set('X-Filename', Uri.encodeComponent(p.basename(f)));
        await req.addStream(File(f).openRead());
        final resp = await req.close();
        await resp.drain<void>();
        client.close();
        ok++;
      } catch (_) {
        fail++;
      }
    }
    if (mounted) {
      setState(() {
        _sending = false;
        _sendResult = '发送完成：成功 $ok，失败 $fail';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('局域网传书'),
        bottom: TabBar(controller: _tab, tabs: const [
          Tab(text: '接收'),
          Tab(text: '发送'),
        ]),
      ),
      body: TabBarView(
        controller: _tab,
        children: [_buildReceive(), _buildSend()],
      ),
    );
  }

  Widget _buildReceive() {
    final url = (_ip == null) ? null : 'http://$_ip:8765';
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (!_hosting)
          Center(
            child: FilledButton.icon(
              icon: const Icon(Icons.play_arrow),
              label: const Text('开始接收'),
              onPressed: _startServer,
            ),
          )
        else ...[
          Center(
            child: Column(
              children: [
                if (url != null)
                  QrImageView(
                    data: url,
                    size: 200,
                    backgroundColor: Colors.white,
                  ),
                const SizedBox(height: 12),
                Text('在另一台设备输入以下地址发送：',
                    style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 4),
                SelectableText(
                  url ?? '无法获取本机 IP',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontFamily: 'monospace', fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                FilledButton.tonalIcon(
                  icon: const Icon(Icons.stop),
                  label: const Text('停止接收'),
                  onPressed: _stopServer,
                ),
              ],
            ),
          ),
          const Divider(height: 32),
          Text('已接收', style: Theme.of(context).textTheme.titleSmall),
          if (_received.isEmpty)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text('暂无接收记录'),
            )
          else
            ..._received.map((f) => ListTile(
                  dense: true,
                  leading: const Icon(Icons.check_circle, color: Colors.green),
                  title: Text(f),
                )),
        ],
        if (_hostError != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(_hostError!,
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
      ],
    );
  }

  Widget _buildSend() {
    final devices = _discovery?.devices ?? [];
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Card(
          child: Padding(
            padding: EdgeInsets.all(12),
            child: Text('把手机上的书籍传到电脑（或反过来）：\n'
                '1. 接收端点「开始接收」\n'
                '2. 这里会自动发现同一 WiFi 下的设备，点「发送」即可；'
                '也可手动输入地址'),
          ),
        ),
        const SizedBox(height: 12),
        Text('自动发现的设备',
            style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 4),
        if (devices.isEmpty)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text('正在自动发现设备…（两端需连同一 WiFi，接收端需点「开始接收」）',
                style: Theme.of(context).textTheme.bodySmall),
          )
        else
          Card(
            child: Column(
              children: [
                for (final d in devices)
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.devices),
                    title: Text(d.name,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(
                      '${d.host}${d.port > 0 ? ':${d.port}' : '（未开启接收）'}',
                    ),
                    trailing: d.port > 0
                        ? FilledButton.tonal(
                            onPressed: _sending
                                ? null
                                : () => _pickAndSend(host: d.host, port: d.port),
                            child: const Text('发送'),
                          )
                        : null,
                  ),
              ],
            ),
          ),
        const Divider(height: 24),
        const SizedBox(height: 8),
        Center(
          child: FilledButton.icon(
            icon: const Icon(Icons.send),
            label: Text(_sending ? '发送中…' : '选择文件手动发送'),
            onPressed: _sending ? null : _pickAndSend,
          ),
        ),
        if (_sendResult != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Center(child: Text(_sendResult!)),
          ),
      ],
    );
  }
}
