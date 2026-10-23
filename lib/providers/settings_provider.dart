import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/launcher_settings.dart';
import '../services/auth_service.dart';
import '../services/java_detector.dart';

class SettingsProvider extends ChangeNotifier {
  SettingsProvider({SettingsService? service})
      : _service = service ?? SettingsService();

  final SettingsService _service;
  LauncherSettings _settings = const LauncherSettings();
  bool _loading = true;
  String? _error;
  List<JavaInstall>? _detectedJavas;
  bool _scanningJava = false;

  LauncherSettings get settings => _settings;
  bool get loading => _loading;
  String? get error => _error;
  List<JavaInstall>? get detectedJavas => _detectedJavas;
  bool get scanningJava => _scanningJava;

  Future<void> init() async {
    _loading = true;
    notifyListeners();
    try {
      _settings = await _service.load();
      _error = null;
    } catch (e) {
      _error = e.toString();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> update(LauncherSettings settings) async {
    _settings = settings;
    notifyListeners();
    await _service.save(settings);
  }

  Future<void> setSelectedVersion(String id) async {
    await update(_settings.copyWith(selectedVersionId: id));
  }

  /// Scans the system for Java installations (cached until re-invoked).
  Future<List<JavaInstall>> scanJavas() async {
    if (_scanningJava) return _detectedJavas ?? const [];
    _scanningJava = true;
    notifyListeners();
    try {
      final found = await JavaDetector.detect();
      _detectedJavas = found;
      return found;
    } finally {
      _scanningJava = false;
      notifyListeners();
    }
  }

  /// Sets (or clears with an empty path) the per-version Java override.
  Future<void> setJavaOverride(String versionId, String javaPath) async {
    final map = Map<String, String>.from(_settings.javaOverrides);
    if (javaPath.trim().isEmpty) {
      if (!map.containsKey(versionId)) return;
      map.remove(versionId);
    } else {
      map[versionId] = javaPath.trim();
    }
    await update(_settings.copyWith(javaOverrides: map));
  }

  Future<String?> detectJava() async {
    final installs = await scanJavas();
    if (installs.isNotEmpty) return installs.first.path;
    return _service.detectJava();
  }
}
