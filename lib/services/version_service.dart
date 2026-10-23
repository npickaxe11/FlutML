import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../models/download_source.dart';
import '../models/minecraft_version.dart';
import 'download_source_registry.dart';
import 'mc_java_requirements.dart';
import 'path_service.dart';

/// A version JSON fully resolved through its `inheritsFrom` chain,
/// plus the id of the ancestor that owns the actual client jar and the
/// Java major version required to run it.
class ResolvedVersion {
  const ResolvedVersion({
    required this.json,
    required this.clientJarVersionId,
    required this.requiredJavaMajor,
  });

  final Map<String, dynamic> json;
  final String clientJarVersionId;
  final int requiredJavaMajor;
}

class VersionService {
  VersionService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  VersionManifest? _cachedManifest;
  DownloadSource? _cachedSource;

  Future<Map<String, dynamic>> readVersionJson(String versionId) async {
    final file = File(await PathService.instance.versionJsonPath(versionId));
    if (!await file.exists()) {
      throw StateError('Version $versionId is not installed');
    }
    return jsonDecode(await file.readAsString()) as Map<String, dynamic>;
  }

  /// Loads [versionId] and merges every `inheritsFrom` ancestor so the
  /// result can be launched directly (libraries concatenated, child wins
  /// for scalars, arguments appended). Needed for Fabric / Forge profiles.
  Future<ResolvedVersion> resolveEffectiveVersion(String versionId) async {
    final versionsRoot = await PathService.instance.versionsDir();

    Future<Map<String, dynamic>> load(String id) async {
      final file = File(p.join(versionsRoot, id, '$id.json'));
      if (!await file.exists()) {
        throw StateError('Version $id is not installed');
      }
      return jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    }

    final ids = <String>[];
    final maps = <Map<String, dynamic>>[];
    final seen = <String>{};
    var cursor = versionId;
    while (seen.add(cursor)) {
      final map = await load(cursor);
      maps.add(map);
      ids.add(cursor);
      final parent = map['inheritsFrom'] as String?;
      if (parent == null || parent.isEmpty) break;
      cursor = parent;
    }

    // Fold from the oldest ancestor down to the requested version.
    var merged = maps.last;
    var clientJarId = ids.last;
    for (var i = ids.length - 2; i >= 0; i--) {
      merged = _mergeInherited(merged, ids[i], maps[i], ids[i]);
    }
    // The client jar belongs to the nearest ancestor exposing downloads.client.
    for (var i = ids.length - 1; i >= 0; i--) {
      final downloads =
          (maps[i]['downloads'] as Map<String, dynamic>?)?['client']
              as Map<String, dynamic>?;
      if (maps[i]['clientJarOverride'] == true) continue;
      if (downloads != null || File(p.join(versionsRoot, ids[i], '${ids[i]}.jar')).existsSync()) {
        clientJarId = ids[i];
        break;
      }
    }

    // Java requirement: prefer the JSON's javaVersion, else infer from id.
    int requiredJavaMajor = 0;
    final javaVersionBlock =
        merged['javaVersion'] as Map<String, dynamic>?;
    final jsonMajor = javaVersionBlock?['majorVersion'];
    if (jsonMajor is int) requiredJavaMajor = jsonMajor;
    if (requiredJavaMajor <= 0) {
      requiredJavaMajor = McJavaRequirements.requiredMajor(versionId);
    }

    return ResolvedVersion(
      json: merged,
      clientJarVersionId: clientJarId,
      requiredJavaMajor: requiredJavaMajor,
    );
  }

  Map<String, dynamic> _mergeInherited(
    Map<String, dynamic> parentJson,
    String parentId,
    Map<String, dynamic> childJson,
    String childId,
  ) =>
      mergeInheritedForTest(parentJson, parentId, childJson, childId);

  @visibleForTesting
  static Map<String, dynamic> mergeInheritedForTest(
    Map<String, dynamic> parentJson,
    String parentId,
    Map<String, dynamic> childJson,
    String childId,
  ) {
    final merged = jsonDecode(jsonEncode(parentJson))
        as Map<String, dynamic>; // deep copy

    final parentLibs =
        ((merged['libraries'] as List<dynamic>?) ?? [])
            .whereType<Map<String, dynamic>>()
            .toList();
    final childLibs =
        ((childJson['libraries'] as List<dynamic>?) ?? [])
            .whereType<Map<String, dynamic>>()
            .toList();
    parentLibs.removeWhere(
      (pl) => pl['name'] != null &&
          childLibs.any((cl) => cl['name'] == pl['name']),
    );
    merged['libraries'] = [...parentLibs, ...childLibs];

    final childArgs = childJson['arguments'];
    if (childArgs is Map<String, dynamic>) {
      final parentArgs = merged['arguments'];
      final pm = parentArgs is Map<String, dynamic>
          ? parentArgs
          : <String, dynamic>{};
      merged['arguments'] = {
        'jvm': [
          ...((pm['jvm'] as List<dynamic>?) ?? []),
          ...((childArgs['jvm'] as List<dynamic>?) ?? []),
        ],
        'game': [
          ...((pm['game'] as List<dynamic>?) ?? []),
          ...((childArgs['game'] as List<dynamic>?) ?? []),
        ],
      };
    }

    for (final key in const [
      'mainClass',
      'minecraftArguments',
      'assetIndex',
      'assets',
      'downloads',
      'logging',
      'javaVersion',
      'type',
      'releaseTime',
      'time',
    ]) {
      if (childJson[key] != null) merged[key] = childJson[key];
    }
    merged['id'] = childJson['id'] ?? childId;
    merged.remove('inheritsFrom');
    return merged;
  }

  Future<VersionManifest> fetchManifest({
    bool force = false,
    DownloadSource source = DownloadSource.official,
  }) async {
    if (!force && _cachedManifest != null && _cachedSource == source) {
      return _cachedManifest!;
    }
    Object? lastError;
    for (final url in DownloadSourceRegistry.manifestCandidates(source)) {
      try {
        final response = await _client
            .get(Uri.parse(url))
            .timeout(const Duration(seconds: 30));
        if (response.statusCode == 200) {
          final manifest = VersionManifest.fromJson(
            jsonDecode(response.body) as Map<String, dynamic>,
          );
          _cachedManifest = manifest;
          _cachedSource = source;
          return manifest;
        }
        lastError = HttpException(
          'Failed to fetch version manifest (${response.statusCode}) from $url',
        );
      } catch (e) {
        lastError = e;
      }
    }
    throw lastError ??
        HttpException('Failed to fetch version manifest from any source');
  }

  Future<List<InstalledVersion>> listInstalled() async {
    final versionsRoot = Directory(await PathService.instance.versionsDir());
    if (!await versionsRoot.exists()) return [];

    final installed = <InstalledVersion>[];
    await for (final entity in versionsRoot.list()) {
      if (entity is! Directory) continue;
      final id = p.basename(entity.path);
      final jsonFile = File(p.join(entity.path, '$id.json'));
      if (!await jsonFile.exists()) continue;
      final jarFile = File(p.join(entity.path, '$id.jar'));

      VersionType type = VersionType.release;
      DateTime? releaseTime;
      var inherits = false;
      try {
        final data =
            jsonDecode(await jsonFile.readAsString()) as Map<String, dynamic>;
        type = versionTypeFromString(data['type'] as String? ?? 'release');
        final rt = data['releaseTime'] as String?;
        if (rt != null) releaseTime = DateTime.tryParse(rt);
        inherits = data['inheritsFrom'] is String &&
            (data['inheritsFrom'] as String).isNotEmpty;
      } catch (_) {}

      // Inherited profiles (Fabric / Forge) ship no client jar of their own.
      if (!await jarFile.exists() && !inherits) continue;

      installed.add(
        InstalledVersion(
          id: id,
          type: type,
          directory: entity.path,
          releaseTime: releaseTime,
        ),
      );
    }

    installed.sort((a, b) {
      final at = a.releaseTime ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bt = b.releaseTime ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bt.compareTo(at);
    });
    return installed;
  }

  Future<bool> isInstalled(String versionId) async {
    final json = File(await PathService.instance.versionJsonPath(versionId));
    if (!await json.exists()) return false;
    final jar = File(await PathService.instance.versionJarPath(versionId));
    if (await jar.exists()) return true;
    try {
      // Inherited profiles (Fabric / Forge) have no own client jar.
      final data = jsonDecode(await json.readAsString()) as Map<String, dynamic>;
      return data['inheritsFrom'] is String;
    } catch (_) {
      return false;
    }
  }

  Future<void> deleteVersion(String versionId) async {
    final dir = Directory(
      p.join(await PathService.instance.versionsDir(), versionId),
    );
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }

  List<ManifestVersion> filterManifest(
    VersionManifest manifest, {
    required bool showSnapshots,
    required bool showOldVersions,
  }) {
    return manifest.versions.where((v) {
      switch (v.type) {
        case VersionType.release:
          return true;
        case VersionType.snapshot:
          return showSnapshots;
        case VersionType.oldBeta:
        case VersionType.oldAlpha:
          return showOldVersions;
      }
    }).toList();
  }
}
