import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/account.dart';
import '../models/launcher_settings.dart';
import '../utils/offline_uuid.dart';
import 'path_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AuthService {
  static const accountStorageKey = 'launcher_account';

  /// Windows 上底层走 DPAPI（CryptProtectData），
  /// 只有当前用户在本机能解密；换个用户 / 换台机器都解不开。
  static final _secure = FlutterSecureStorage();

  Future<Account?> loadAccount() async {
    String? raw;
    try {
      raw = await _secure.read(key: accountStorageKey);
    } catch (_) {
      raw = null;
    }

    // 一次性迁移：旧版本把 token 明文写在 SharedPreferences 里，
    // 读到就搬到安全存储并删掉明文，避免老用户升级后登录状态丢失。
    if (raw == null || raw.isEmpty) {
      final prefs = await SharedPreferences.getInstance();
      final legacy = prefs.getString(accountStorageKey);
      if (legacy != null && legacy.isNotEmpty) {
        try {
          await _secure.write(key: accountStorageKey, value: legacy);
          await prefs.remove(accountStorageKey);
          raw = legacy;
        } catch (_) {
          // 写不进安全存储：宁可暂不迁移也不丢账户
        }
      }
    }

    if (raw == null || raw.isEmpty) return null;
    try {
      return Account.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveAccount(Account account) async {
    await _secure.write(
      key: accountStorageKey,
      value: jsonEncode(account.toJson()),
    );
    // 顺手清掉可能残留的旧明文（例如上次迁移中途失败）
    final prefs = await SharedPreferences.getInstance();
    if (prefs.containsKey(accountStorageKey)) {
      await prefs.remove(accountStorageKey);
    }
  }

  Future<Account> loginOffline(String username) async {
    final trimmed = username.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('Username cannot be empty');
    }
    if (!RegExp(r'^[A-Za-z0-9_]{3,16}$').hasMatch(trimmed)) {
      throw ArgumentError(
        'Username must be 3–16 characters (letters, numbers, underscore)',
      );
    }
    final account = Account(
      username: trimmed,
      uuid: offlinePlayerUuid(trimmed),
      type: AccountType.offline,
    );
    await saveAccount(account);
    return account;
  }

  Future<void> logout() async {
    await _secure.delete(key: accountStorageKey);
    // 清掉旧版可能残留的明文
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(accountStorageKey);
  }
}

class SettingsService {
  static const _settingsKey = 'launcher_settings';

  Future<LauncherSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_settingsKey);
    LauncherSettings settings;
    if (raw == null || raw.isEmpty) {
      settings = const LauncherSettings();
    } else {
      try {
        settings = LauncherSettings.fromJson(
          jsonDecode(raw) as Map<String, dynamic>,
        );
      } catch (_) {
        settings = const LauncherSettings();
      }
    }

    var gameDir = settings.gameDirectory;
    if (gameDir.isEmpty) {
      gameDir = await PathService.instance.defaultGameDirectory();
      settings = settings.copyWith(gameDirectory: gameDir);
    }
    await PathService.instance.setCustomGameDir(gameDir);

    if (settings.javaPath.isEmpty) {
      final detected = await detectJava();
      if (detected != null) {
        settings = settings.copyWith(javaPath: detected);
      }
    }
    return settings;
  }

  Future<void> save(LauncherSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_settingsKey, jsonEncode(settings.toJson()));
    if (settings.gameDirectory.isNotEmpty) {
      await PathService.instance.setCustomGameDir(settings.gameDirectory);
    }
  }

  Future<String?> detectJava() async {
    final javaHome = Platform.environment['JAVA_HOME'];
    if (javaHome != null && javaHome.isNotEmpty) {
      final exe = Platform.isWindows
          ? p.join(javaHome, 'bin', 'java.exe')
          : p.join(javaHome, 'bin', 'java');
      if (await File(exe).exists()) return exe;
    }

    try {
      final result = await Process.run(Platform.isWindows ? 'where' : 'which', [
        'java',
      ], runInShell: true);
      if (result.exitCode == 0) {
        final lines = (result.stdout as String)
            .split(RegExp(r'\r?\n'))
            .where((l) => l.trim().isNotEmpty);
        if (lines.isNotEmpty) return lines.first.trim();
      }
    } catch (_) {}

    if (Platform.isWindows) {
      final candidates = [
        r'C:\Program Files\Java',
        r'C:\Program Files\Eclipse Adoptium',
        r'C:\Program Files\Microsoft',
        r'C:\Program Files\Zulu',
        r'C:\Program Files\Amazon Corretto',
      ];
      for (final root in candidates) {
        final dir = Directory(root);
        if (!await dir.exists()) continue;
        await for (final entity in dir.list()) {
          if (entity is! Directory) continue;
          final exe = p.join(entity.path, 'bin', 'java.exe');
          if (await File(exe).exists()) return exe;
        }
      }
    }
    return null;
  }
}
