import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/wallpaper_color_service.dart';

class ThemeProvider extends ChangeNotifier {
  /// 取不到壁纸色时的兜底（与 app_theme.dart 默认一致）
  static const defaultSeed = Color(0xFF2E7D32);

  Color _seedColor = defaultSeed;
  Color get seedColor => _seedColor;

  bool _initialized = false;

  /// 首帧之后调用；只在首次真正取色。
  Future<void> ensureInitialized() async {
    if (_initialized) return;
    _initialized = true;
    await _refresh();
  }

  Future<void> _refresh() async {
    final cached = await _readCache();
    if (cached != null) {
      _seedColor = cached;
      notifyListeners();
    }
    final fresh = await WallpaperColorService.detectSeedColor();
    if (fresh == null || fresh == _seedColor) return;
    _seedColor = fresh;
    notifyListeners();
    await _writeCache(fresh);
  }

  /// 壁纸换了之后（比如从桌面右键换壁纸）调用一下即可。
  /// 不放在 UI 上，靠 lifecycle 自动触发。
  Future<void> refresh() => _refresh();

  // ---------- 缓存（用壁纸文件的 mtime 做失效判断） ----------

  static const _kColor = 'wallpaper_seed_color';
  static const _kStamp = 'wallpaper_seed_stamp';

  Future<Color?> _readCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedStamp = prefs.getString(_kStamp);
      final savedColor = prefs.getInt(_kColor);
      if (savedStamp == null || savedColor == null) return null;
      if (savedStamp != await _wallpaperStamp()) return null;
      return Color(savedColor);
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeCache(Color color) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_kColor, color.toARGB32());
      await prefs.setString(_kStamp, await _wallpaperStamp());
    } catch (_) {}
  }

  /// 用壁纸路径 + 修改时间 + 文件大小拼出一个"指纹"。
  static Future<String> _wallpaperStamp() async {
    if (!Platform.isWindows) return '';
    try {
      final raw = await Process.run('reg', [
        'query',
        r'HKCU\Control Panel\Desktop',
        '/v',
        'WallPaper',
      ]).timeout(const Duration(seconds: 3));
      if (raw.exitCode != 0) return '';
      final match = RegExp(
        r'WallPaper\s+REG_\w+\s+(.+)',
        caseSensitive: false,
      ).firstMatch(raw.stdout.toString());
      final path = match?.group(1)?.trim() ?? '';
      if (path.isEmpty) return '';
      final file = File(path);
      if (!await file.exists()) return path;
      final stat = await file.stat();
      return jsonEncode([
        path,
        stat.modified.millisecondsSinceEpoch,
        stat.size,
      ]);
    } catch (_) {
      return '';
    }
  }
}
