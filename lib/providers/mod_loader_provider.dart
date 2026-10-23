import 'package:flutter/foundation.dart';

import '../models/download_source.dart';
import '../services/mod_loader_service.dart';

class ModLoaderProvider extends ChangeNotifier {
  ModLoaderProvider({ModLoaderService? service})
      : _service = service ?? ModLoaderService();

  final ModLoaderService _service;

  bool _busy = false;
  String? _status;
  String? _error;
  int _errorTicket = 0;

  bool get busy => _busy;
  String? get status => _status;
  String? get error => _error;
  int get errorTicket => _errorTicket;

  /// Queries Forge builds; network failures are routed to the error
  /// dialog channel and an empty list is returned.
  Future<List<ForgeBuild>> forgeBuilds(
    String gameVersion,
    DownloadSource source,
  ) async {
    try {
      return await _service.forgeBuilds(gameVersion);
    } catch (e) {
      _error = e.toString();
      _errorTicket++;
      notifyListeners();
      return const [];
    }
  }

  Future<List<FabricLoaderInfo>> fabricLoaders(
    String gameVersion,
    DownloadSource source,
  ) async {
    try {
      return await _service.fabricLoaders(gameVersion, source);
    } catch (e) {
      _error = e.toString();
      _errorTicket++;
      notifyListeners();
      return const [];
    }
  }

  Future<String?> installFabric({
    required String gameVersion,
    required String loaderVersion,
    required DownloadSource source,
  }) async {
    return _run(() async {
      final id = await _service.installFabric(
        gameVersion: gameVersion,
        loaderVersion: loaderVersion,
        source: source,
        onStatus: (s) {
          _status = s;
          notifyListeners();
        },
      );
      return id;
    });
  }

  Future<String?> installForge({
    required String gameVersion,
    required ForgeBuild build,
    required String javaPath,
    required String gameRoot,
    required DownloadSource source,
  }) async {
    return _run(() {
      return _service.installForge(
        gameVersion: gameVersion,
        build: build,
        javaPath: javaPath,
        gameRoot: gameRoot,
        source: source,
        onLog: (line) {
          _status = line;
          notifyListeners();
        },
      );
    });
  }

  Future<String?> _run(Future<String?> Function() action) async {
    if (_busy) return null;
    _busy = true;
    _error = null;
    _status = 'Preparing…';
    notifyListeners();
    try {
      final result = await action();
      _status ??= 'Done';
      return result;
    } catch (e) {
      _error = e.toString();
      _errorTicket++;
      return null;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}
