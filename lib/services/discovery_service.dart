import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 局域网设备自动发现（LocalSend 风格，移植自 worker-pay 的 discovery.py）。
/// 每 3 秒广播 beacon；收到 discover 请求则单播 response；
/// 每 10 秒向本机 /24 网段主动探测，绕过路由器/AP 隔离。
class DiscoveryDevice {
  final String id;
  final String name;
  final String host;
  final int port;
  final DateTime lastSeen;

  DiscoveryDevice({
    required this.id,
    required this.name,
    required this.host,
    required this.port,
    required this.lastSeen,
  });
}

class DiscoveryService {
  static const int _port = 20000;
  static const String _app = 'reader-sync';
  static const Duration _beaconInterval = Duration(seconds: 3);
  static const Duration _probeInterval = Duration(seconds: 10);
  static const Duration _expire = Duration(seconds: 60);

  final String name;
  final String deviceId;
  final int Function() portGetter;

  RawDatagramSocket? _socket;
  StreamSubscription<RawSocketEvent>? _sub;
  Timer? _beaconTimer;
  Timer? _probeTimer;
  bool _running = false;
  String _ip = '127.0.0.1';
  final Map<String, DiscoveryDevice> _devices = {};

  DiscoveryService({required this.name, required this.portGetter})
      : deviceId = 'reader-${DateTime.now().millisecondsSinceEpoch}';

  bool get running => _running;

  static const MethodChannel _multicastChannel =
      MethodChannel('reader/multicast');

  /// Android 发送/接收 UDP 广播需要 WifiManager.MulticastLock，
  /// 否则 send 会报 EACCES（Permission denied）。
  Future<void> _acquireMulticastLock() async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        await _multicastChannel.invokeMethod('acquire');
      } catch (_) {}
    }
  }

  Future<void> _releaseMulticastLock() async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        await _multicastChannel.invokeMethod('release');
      } catch (_) {}
    }
  }

  Future<void> start() async {
    if (_running) return;
    // 先绑定 socket，再取 IP：NetworkInterface.list 在部分 Android 上会阻塞，
    // 不能让它挡在绑定前面。
    _socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4, _port, reuseAddress: false);
    _sub = _socket!.listen(_onEvent, onError: (_) {});
    await _acquireMulticastLock();
    _running = true;
    _ip = await _computeIp();
    _beaconTimer = Timer.periodic(_beaconInterval, (_) => _sendBeacon());
    _probeTimer = Timer.periodic(_probeInterval, (_) => _probeSubnet());
    _sendBeacon();
  }

  void stop() {
    _running = false;
    _beaconTimer?.cancel();
    _probeTimer?.cancel();
    _sub?.cancel();
    _socket?.close();
    _socket = null;
    _releaseMulticastLock();
    _devices.clear();
  }

  Future<void> scan() async {
    _sendDiscover();
    await Future<void>.delayed(const Duration(milliseconds: 1200));
  }

  /// TCP/HTTP 子网扫描（可靠兜底）：逐 IP 探测 8765 端口的 /api/info。
  /// UDP 广播在部分 Android 上收不到，TCP 探测能稳定发现接收端。
  Future<void> scanViaHttp() async {
    final parts = _ip.split('.');
    if (parts.length != 4) return;
    final prefix = '${parts[0]}.${parts[1]}.${parts[2]}';
    final targets = <String>[
      for (var i = 1; i < 255; i++) '$prefix.$i'
    ];
    // 控制并发，避免瞬间发起太多连接
    var index = 0;
    Future<void> worker() async {
      while (index < targets.length) {
        final ip = targets[index++];
        try {
          final client = HttpClient()
            ..connectionTimeout = const Duration(milliseconds: 350);
          final req =
              await client.getUrl(Uri.parse('http://$ip:8765/api/info'));
          final resp = await req.close().timeout(const Duration(milliseconds: 800));
          if (resp.statusCode == 200) {
            final body = await resp.transform(utf8.decoder).join();
            client.close();
            try {
              final info = json.decode(body);
              if (info is Map && info['app'] == _app) {
                final id = info['host'] as String? ?? ip;
                final name = info['name'] as String? ?? 'Reader 设备';
                final port = (info['port'] as num?)?.toInt() ?? 8765;
                _devices[id] = DiscoveryDevice(
                  id: id,
                  name: name,
                  host: ip,
                  port: port > 0 ? port : 8765,
                  lastSeen: DateTime.now(),
                );
              }
            } catch (_) {}
          } else {
            client.close();
          }
        } catch (_) {}
      }
    }

    const concurrency = 20;
    await Future.wait(
        List.generate(concurrency, (_) => worker()),
        eagerError: false);
    _devices.removeWhere(
        (_, d) => DateTime.now().difference(d.lastSeen) > _expire);
  }

  List<DiscoveryDevice> get devices {
    final now = DateTime.now();
    return _devices.values
        .where((d) => now.difference(d.lastSeen) < _expire)
        .toList();
  }

  void _onEvent(RawSocketEvent event) {
    final socket = _socket;
    if (socket == null) return;
    if (event == RawSocketEvent.read) {
      final dm = socket.receive();
      if (dm == null) return;
      try {
        final msg = json.decode(utf8.decode(dm.data));
        if (msg is Map && msg['app'] == _app && msg['id'] != deviceId) {
          _handle(msg, dm.address.address);
        }
      } catch (_) {}
    }
  }

  void _handle(Map<dynamic, dynamic> msg, String fromAddr) {
    final id = (msg['id'] as String?) ?? '';
    if (id.isEmpty) return;
    _devices[id] = DiscoveryDevice(
      id: id,
      name: (msg['name'] as String?) ?? '未知设备',
      // 用数据包源地址作为设备地址，比广告的 host 字段更可靠
      host: fromAddr,
      port: (msg['port'] as int?) ?? 0,
      lastSeen: DateTime.now(),
    );
    if (msg['cmd'] == 'discover') {
      _sendResponse(fromAddr);
    }
  }

  Map<String, Object?> _packet(String cmd) {
    return {
      'app': _app,
      'cmd': cmd,
      'name': name,
      'id': deviceId,
      'host': _ip,
      'port': portGetter(),
    };
  }

  void _broadcast(Map<String, Object?> msg) {
    final socket = _socket;
    if (socket == null) return;
    final data = utf8.encode(json.encode(msg));
    for (final addr in _broadcastAddresses()) {
      try {
        socket.send(data, InternetAddress(addr), _port);
      } catch (_) {}
    }
  }

  void _sendTo(String host, Map<String, Object?> msg) {
    final socket = _socket;
    if (socket == null) return;
    try {
      socket.send(utf8.encode(json.encode(msg)), InternetAddress(host), _port);
    } catch (_) {}
  }

  void _sendBeacon() => _broadcast(_packet('beacon'));

  void _sendDiscover() => _broadcast(_packet('discover'));

  void _sendResponse(String host) => _sendTo(host, _packet('response'));

  void _probeSubnet() {
    final parts = _ip.split('.');
    if (parts.length != 4) return;
    final prefix = '${parts[0]}.${parts[1]}.${parts[2]}';
    final data = utf8.encode(json.encode(_packet('discover')));
    final socket = _socket;
    if (socket == null) return;
    for (var i = 1; i < 255; i++) {
      try {
        socket.send(data, InternetAddress('$prefix.$i'), _port);
      } catch (_) {
        break;
      }
    }
  }

  List<String> _broadcastAddresses() {
    final addrs = <String>['255.255.255.255'];
    final parts = _ip.split('.');
    if (parts.length == 4) {
      addrs.add('${parts[0]}.${parts[1]}.${parts[2]}.255');
    }
    return addrs;
  }

  Future<String> _computeIp() async {
    // Android：用 WifiManager 直接取本机 WiFi IP（快速且准确）。
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final ip = await _multicastChannel.invokeMethod<String>('getIp');
        if (ip != null && ip.isNotEmpty && !ip.startsWith('127.')) return ip;
      } catch (_) {}
    }
    // 兜底：NetworkInterface.list（带超时，避免部分 Android 阻塞）
    try {
      final interfaces = await NetworkInterface.list(
              type: InternetAddressType.IPv4, includeLoopback: false)
          .timeout(const Duration(seconds: 3));
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
      for (final i in interfaces) {
        if (i.addresses.isNotEmpty) return i.addresses.first.address;
      }
    } catch (_) {}
    return '127.0.0.1';
  }

  void dispose() => stop();
}
