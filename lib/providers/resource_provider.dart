import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../models/modrinth_models.dart';
import '../services/modrinth_service.dart';
import '../services/path_service.dart';
import 'download_manager_provider.dart';

class ResourceProvider extends ChangeNotifier {
  ResourceProvider({
    ModrinthService? service,
    DownloadManagerProvider? downloadManager,
  }) : this._internal(service ?? ModrinthService(), downloadManager);

  ResourceProvider._internal(this._service, this._downloadManager);

  static const pageSize = 20;

  final ModrinthService _service;
  final DownloadManagerProvider? _downloadManager;

  ResourceType _type = ResourceType.mod;
  ResourceSort _sort = ResourceSort.relevance;
  String _gameVersion = '';
  String _loader = '';
  String _query = '';

  List<ModrinthSearchHit> _hits = const [];
  int _totalHits = 0;
  bool _loading = false;
  bool _loadingMore = false;
  String? _error;
  int _searchToken = 0;

  ModrinthSearchHit? _selectedHit;
  ModrinthProject? _selectedProject;
  List<ModrinthVersion> _versions = const [];
  bool _loadingDetails = false;
  String? _detailsError;
  int _detailsToken = 0;

  ResourceType get type => _type;
  ResourceSort get sort => _sort;
  String get gameVersion => _gameVersion;
  String get loader => _loader;
  String get query => _query;
  List<ModrinthSearchHit> get hits => _hits;
  int get totalHits => _totalHits;
  bool get loading => _loading;
  bool get loadingMore => _loadingMore;
  String? get error => _error;
  bool get hasMore => _hits.length < _totalHits;

  ModrinthSearchHit? get selectedHit => _selectedHit;
  ModrinthProject? get selectedProject => _selectedProject;
  List<ModrinthVersion> get versions => _versions;
  bool get loadingDetails => _loadingDetails;
  String? get detailsError => _detailsError;

  void setQuery(String value) {
    _query = value;
    notifyListeners();
  }

  Future<void> setType(ResourceType value) async {
    if (_type == value) return;
    _type = value;
    notifyListeners();
    await search();
  }

  Future<void> setSort(ResourceSort value) async {
    if (_sort == value) return;
    _sort = value;
    notifyListeners();
    await search();
  }

  Future<void> setGameVersion(String value) async {
    if (_gameVersion == value) return;
    _gameVersion = value.trim();
    notifyListeners();
    await search();
  }

  Future<void> setLoader(String value) async {
    if (_loader == value) return;
    _loader = value;
    notifyListeners();
    await search();
  }

  Future<void> search({bool append = false}) async {
    final token = ++_searchToken;
    final offset = append ? _hits.length : 0;

    if (append) {
      if (_loading || _loadingMore || !hasMore) return;
      _loadingMore = true;
    } else {
      _loading = true;
      _hits = const [];
      _totalHits = 0;
    }
    _error = null;
    notifyListeners();

    try {
      final result = await _service.search(
        query: _query,
        type: _type,
        gameVersion: _gameVersion,
        loader: _loader,
        sort: _sort,
        limit: pageSize,
        offset: offset,
      );
      if (token != _searchToken) return;
      _hits = append ? [..._hits, ...result.hits] : result.hits;
      _totalHits = result.totalHits;
    } catch (e) {
      if (token != _searchToken) return;
      _error = e.toString();
    } finally {
      if (token == _searchToken) {
        _loading = false;
        _loadingMore = false;
        notifyListeners();
      }
    }
  }

  Future<void> loadMore() => search(append: true);

  Future<void> refresh() async {
    if (_selectedHit != null) {
      await _loadProject(_selectedHit!);
    } else {
      await search();
    }
  }

  Future<bool> openProject(ModrinthSearchHit hit) async {
    _selectedHit = hit;
    _selectedProject = null;
    _versions = const [];
    notifyListeners();
    return _loadProject(hit);
  }

  Future<bool> _loadProject(ModrinthSearchHit hit) async {
    final token = ++_detailsToken;
    _loadingDetails = true;
    _detailsError = null;
    notifyListeners();

    try {
      final results = await Future.wait<Object>([
        _service.fetchProject(hit.id),
        _service.fetchVersions(
          hit.id,
          gameVersion: _gameVersion,
          loader: _loader,
          type: _type,
        ),
      ]);
      if (token != _detailsToken) return false;
      _selectedProject = results[0] as ModrinthProject;
      _versions = results[1] as List<ModrinthVersion>;
      return true;
    } catch (e) {
      if (token != _detailsToken) return false;
      _detailsError = e.toString();
      return false;
    } finally {
      if (token == _detailsToken) {
        _loadingDetails = false;
        notifyListeners();
      }
    }
  }

  Future<bool> retryDetails() async {
    final hit = _selectedHit;
    if (hit == null) return false;
    return _loadProject(hit);
  }

  void closeProject() {
    _detailsToken++;
    _selectedHit = null;
    _selectedProject = null;
    _versions = const [];
    _loadingDetails = false;
    _detailsError = null;
    notifyListeners();
  }

  Future<String> suggestedDirectory(
    ResourceType type,
    String gameVersion,
  ) async {
    final gameRoot = await PathService.instance.gameDirectory();
    final version = gameVersion.trim();
    Directory dir;

    if (version.isEmpty) {
      final folder = switch (type) {
        ResourceType.mod => 'mods',
        ResourceType.resourcepack => 'resourcepacks',
        ResourceType.shader => 'shaderpacks',
        ResourceType.datapack => 'datapacks',
        ResourceType.modpack => 'modpacks',
      };
      dir = Directory(p.join(gameRoot, folder));
    } else {
      dir = switch (type) {
        ResourceType.mod => Directory(
          await PathService.instance.modsDir(version),
        ),
        ResourceType.resourcepack => Directory(
          await PathService.instance.resourcePacksDir(version),
        ),
        ResourceType.shader => Directory(
          await PathService.instance.shaderPacksDir(version),
        ),
        ResourceType.datapack => Directory(p.join(gameRoot, 'datapacks')),
        ResourceType.modpack => Directory(p.join(gameRoot, 'modpacks')),
      };
    }

    await dir.create(recursive: true);
    return dir.path;
  }

  Future<String?> downloadFile({
    required ModrinthProject project,
    required ModrinthVersion version,
    required ModrinthFile file,
    required String destination,
  }) async {
    final taskId = _downloadManager?.createTask(
      title: file.filename,
      subtitle: '${project.title} · ${version.versionNumber}',
      kind: 'resource',
      stage: '开始下载…',
    );

    try {
      await _service.downloadFile(
        url: file.url,
        destination: destination,
        expectedSha1: file.sha1,
        onProgress: (received, total) {
          if (taskId == null) return;
          _downloadManager?.updateTask(
            taskId,
            stage: '下载中',
            received: received,
            total: total,
          );
        },
      );
      if (taskId != null) {
        _downloadManager?.completeTask(
          taskId,
          stage: '已保存到 $destination',
          filePath: destination,
        );
      }
      return null;
    } catch (e) {
      if (taskId != null) {
        _downloadManager?.failTask(taskId, e);
      }
      return e.toString();
    }
  }
}
