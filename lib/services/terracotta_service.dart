import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class TerracottaService {
  Process? _process;
  int? _apiPort;
  bool get isRunning => _process != null;

  /// 启动 Terracotta 引擎（采用 HMCL 兼容模式）
  /// 启动 Terracotta 引擎（支持释放 DLL 依赖）
  Future<void> start() async {
    if (_process != null) return;

    final supportDir = await getApplicationSupportDirectory();
    final extractDir = Directory(p.join(supportDir.path, 'terracotta'));
    if (!await extractDir.exists()) {
      await extractDir.create(recursive: true);
    }

    // 1. 需要释放到本地的依赖文件（把需要的 DLL 都列在这里）
    const requiredFiles = ['terracotta.exe', 'VCRUNTIME140.dll'];

    // 2. 循环释放文件
    for (final fileName in requiredFiles) {
      final targetFile = File(p.join(extractDir.path, fileName));
      if (!await targetFile.exists()) {
        try {
          final byteData = await rootBundle.load('assets/terracotta/$fileName');
          await targetFile.writeAsBytes(byteData.buffer.asUint8List());
        } catch (e) {
          // 如果缺文件，直接报错，方便排查
          throw Exception('缺少必要文件 $fileName，请确保它位于 assets/terracotta/ 下');
        }
      }
    }

    // 3. 准备端口文件并启动进程
    final exePath = p.join(extractDir.path, 'terracotta.exe');
    final portFile = File(p.join(extractDir.path, 'terracotta_port.json'));
    if (await portFile.exists()) {
      await portFile.delete();
    }

    _process = await Process.start(
      exePath,
      ['--hmcl', portFile.path],
      workingDirectory: extractDir.path, // 必须指向释放目录，否则找不到 DLL
    );

    // 监听日志（调试用）
    _process!.stdout
        .transform(utf8.decoder)
        .listen((data) => print('TC: $data'));
    _process!.stderr
        .transform(utf8.decoder)
        .listen((data) => print('TC Err: $data'));

    // 4. 轮询等待端口文件生成
    for (int i = 0; i < 20; i++) {
      await Future.delayed(const Duration(milliseconds: 500));
      if (await portFile.exists()) {
        try {
          final content = await portFile.readAsString();
          final json = jsonDecode(content);
          _apiPort = json['port'];
          if (_apiPort != null && _apiPort! > 0) return;
        } catch (_) {}
      }
    }

    // 5. 超时检测，如果进程挂了给出明确提示
    if (_process != null &&
        await _process!.exitCode.timeout(
              const Duration(seconds: 1),
              onTimeout: () => -1,
            ) !=
            -1) {
      _process = null;
      throw Exception('Terracotta 进程崩溃，请检查是否缺失 DLL 或被杀毒软件拦截');
    }
    throw Exception('启动 Terracotta 超时');
  }

  Future<void> stop() async {
    try {
      if (_apiPort != null) {
        // 发送正常的关闭请求
        await http
            .get(Uri.parse('http://127.0.0.1:$_apiPort/panic?peaceful=true'))
            .timeout(const Duration(seconds: 2));
      }
    } catch (_) {}
    _process?.kill();
    _process = null;
    _apiPort = null;
  }

  /// 获取当前状态
  Future<Map<String, dynamic>> getState() async {
    if (_apiPort == null) return {};
    try {
      final res = await http
          .get(Uri.parse('http://127.0.0.1:$_apiPort/state'))
          .timeout(const Duration(seconds: 2));
      if (res.statusCode == 200) {
        return jsonDecode(res.body);
      }
    } catch (_) {}
    return {};
  }

  /// 重置状态 (断开/取消)
  Future<void> setWaiting() async {
    if (_apiPort == null) return;
    try {
      await http.get(Uri.parse('http://127.0.0.1:$_apiPort/state/ide'));
    } catch (_) {}
  }

  /// 房主扫描局域网并开房
  Future<void> setScanning({String? room, String? player}) async {
    if (_apiPort == null) return;
    final params = <String, String>{};
    if (room != null && room.isNotEmpty) params['room'] = room;
    if (player != null && player.isNotEmpty) params['player'] = player;
    final uri = Uri.parse(
      'http://127.0.0.1:$_apiPort/state/scanning',
    ).replace(queryParameters: params);
    try {
      await http.get(uri);
    } catch (_) {}
  }

  /// 客机加入房间
  Future<bool> setGuesting({required String room, String? player}) async {
    if (_apiPort == null) return false;
    final params = <String, String>{'room': room};
    if (player != null && player.isNotEmpty) params['player'] = player;
    final uri = Uri.parse(
      'http://127.0.0.1:$_apiPort/state/guesting',
    ).replace(queryParameters: params);
    try {
      final res = await http.get(uri);
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
