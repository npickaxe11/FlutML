import 'package:flutter/foundation.dart';

import '../models/download_progress.dart';
import '../models/download_source.dart';
import '../models/minecraft_version.dart';
import '../services/download_service.dart';
import '../services/version_service.dart';
import 'download_manager_provider.dart';

class VersionProvider extends ChangeNotifier {
  VersionProvider({
    VersionService? versionService,
    DownloadService? downloadService,
    DownloadManagerProvider? downloadManager,
  }) : this._internal(
         versionService ?? VersionService(),
         downloadService ?? DownloadService(),
         downloadManager,
       );

  VersionProvider._internal(
    this._versions,
    this._downloads,
    this._downloadManager,
  );

  final VersionService _versions;
  final DownloadService _downloads;
  final DownloadManagerProvider? _downloadManager;

  DownloadSource _source = DownloadSource.official;
  VersionManifest? _manifest;
  List<InstalledVersion> _installed = [];
  bool _loadingManifest = false;
  bool _loadingInstalled = false;
  bool _downloading = false;
  DownloadProgress? _progress;
  String? _error;
  int _errorTicket = 0;
  String _search = '';

  DownloadSource get source => _source;
  VersionManifest? get manifest => _manifest;
  List<InstalledVersion> get installed => _installed;
  bool get loadingManifest => _loadingManifest;
  bool get loadingInstalled => _loadingInstalled;
  bool get downloading => _downloading;
  DownloadProgress? get progress => _progress;
  String? get error => _error;
  int get errorTicket => _errorTicket;
  String get search => _search;

  Set<String> get installedIds => _installed.map((e) => e.id).toSet();

  List<ManifestVersion> remoteVersions({
    required bool showSnapshots,
    required bool showOldVersions,
  }) {
    if (_manifest == null) return [];
    var list = _versions.filterManifest(
      _manifest!,
      showSnapshots: showSnapshots,
      showOldVersions: showOldVersions,
    );
    if (_search.trim().isNotEmpty) {
      final q = _search.trim().toLowerCase();
      list = list.where((v) => v.id.toLowerCase().contains(q)).toList();
    }
    return list;
  }

  void setSearch(String value) {
    _search = value;
    notifyListeners();
  }

  Future<void> init({DownloadSource source = DownloadSource.official}) async {
    _source = source;
    await Future.wait([refreshInstalled(), refreshManifest()]);
  }

  Future<void> changeSource(DownloadSource source) async {
    if (_source == source) return;
    _source = source;
    await refreshManifest(force: true);
  }

  Future<void> refreshManifest({bool force = false}) async {
    _loadingManifest = true;
    _error = null;
    notifyListeners();
    try {
      _manifest = await _versions.fetchManifest(force: force, source: _source);
    } catch (e) {
      _error = e.toString();
      _errorTicket++;
    } finally {
      _loadingManifest = false;
      notifyListeners();
    }
  }

  Future<void> refreshInstalled() async {
    _loadingInstalled = true;
    notifyListeners();
    try {
      _installed = await _versions.listInstalled();
    } catch (e) {
      _error = e.toString();
      _errorTicket++;
    } finally {
      _loadingInstalled = false;
      notifyListeners();
    }
  }

  Future<void> download(ManifestVersion version) async {
    if (_downloading) return;
    _downloading = true;
    _progress = DownloadProgress(
      stage: 'Starting',
      current: 0,
      total: 1,
      currentFile: version.id,
    );
    _error = null;
    final taskId = _downloadManager?.createTask(
      title: 'Minecraft ${version.id}',
      subtitle: '游戏版本下载',
      kind: 'version',
      stage: '准备下载…',
    );
    notifyListeners();

    try {
      await _downloads.downloadVersion(
        version,
        source: _source,
        onProgress: (p) {
          _progress = p;
          if (taskId != null) {
            if (p.error != null) {
              _downloadManager?.failTask(taskId, p.error!);
            } else {
              _downloadManager?.updateTask(
                taskId,
                stage: p.stage,
                received: p.current,
                total: p.total,
              );
            }
          }
          notifyListeners();
        },
      );
      await refreshInstalled();
      if (taskId != null) {
        _downloadManager?.completeTask(taskId, stage: '安装完成');
      }
    } catch (e) {
      _error = e.toString();
      _errorTicket++;
      _progress = _progress?.copyWith(done: true, error: e.toString());
      if (taskId != null) {
        _downloadManager?.failTask(taskId, e);
      }
    } finally {
      _downloading = false;
      notifyListeners();
    }
  }

  Future<void> deleteVersion(String id) async {
    await _versions.deleteVersion(id);
    await refreshInstalled();
  }

  bool isInstalled(String id) => installedIds.contains(id);
}
