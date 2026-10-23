import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../models/download_progress.dart';
import '../models/download_source.dart';
import '../models/minecraft_version.dart';
import 'download_source_registry.dart';
import 'path_service.dart';

typedef ProgressCallback = void Function(DownloadProgress progress);

class DownloadService {
  DownloadService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<void> downloadVersion(
    ManifestVersion version, {
    required DownloadSource source,
    ProgressCallback? onProgress,
  }) async {
    void report({
      required String stage,
      required int current,
      required int total,
      String currentFile = '',
      bool done = false,
      String? error,
    }) {
      onProgress?.call(
        DownloadProgress(
          stage: stage,
          current: current,
          total: total,
          currentFile: currentFile,
          done: done,
          error: error,
        ),
      );
    }

    try {
      report(stage: 'Fetching version metadata', current: 0, total: 1);

      final metaRes = await _fetchAny(
        DownloadSourceRegistry.candidatesFor(version.url, source),
      );
      if (metaRes.statusCode != 200) {
        throw HttpException(
          'Failed to fetch version JSON (${metaRes.statusCode})',
        );
      }
      final versionJson =
          jsonDecode(utf8.decode(metaRes.bodyBytes)) as Map<String, dynamic>;

      final versionDir = Directory(
        p.join(await PathService.instance.versionsDir(), version.id),
      );
      await versionDir.create(recursive: true);

      final jsonPath =
          await PathService.instance.versionJsonPath(version.id);
      await File(jsonPath).writeAsString(
        const JsonEncoder.withIndent('  ').convert(versionJson),
      );

      // Client jar
      final downloads = versionJson['downloads'] as Map<String, dynamic>?;
      final client = downloads?['client'] as Map<String, dynamic>?;
      if (client == null) {
        throw StateError('Version ${version.id} has no client download');
      }
      report(stage: 'Downloading client', current: 0, total: 1, currentFile: '${version.id}.jar');
      await _downloadFile(
        urls: DownloadSourceRegistry.candidatesFor(
          client['url'] as String,
          source,
        ),
        dest: await PathService.instance.versionJarPath(version.id),
        expectedSha1: client['sha1'] as String?,
        onBytes: (received, total) {
          report(
            stage: 'Downloading client',
            current: received,
            total: total <= 0 ? 1 : total,
            currentFile: '${version.id}.jar',
          );
        },
      );

      // Libraries
      await downloadLibraries(
        libraries: (versionJson['libraries'] as List<dynamic>? ?? []),
        source: source,
        extractNativesFor: version.id,
        onProgress: (current, total, fileName) {
          report(
            stage: 'Downloading libraries',
            current: current,
            total: total,
            currentFile: fileName,
          );
        },
      );

      // Assets
      final assetIndexInfo =
          versionJson['assetIndex'] as Map<String, dynamic>?;
      if (assetIndexInfo != null) {
        final assetsRoot = await PathService.instance.assetsDir();
        final indexesDir = Directory(p.join(assetsRoot, 'indexes'));
        await indexesDir.create(recursive: true);
        final indexId = assetIndexInfo['id'] as String;
        final indexPath = p.join(indexesDir.path, '$indexId.json');

        report(stage: 'Downloading asset index', current: 0, total: 1, currentFile: '$indexId.json');
        await _downloadFile(
          urls: DownloadSourceRegistry.candidatesFor(
            assetIndexInfo['url'] as String,
            source,
          ),
          dest: indexPath,
          expectedSha1: assetIndexInfo['sha1'] as String?,
        );

        final indexJson =
            jsonDecode(await File(indexPath).readAsString())
                as Map<String, dynamic>;
        final objects =
            (indexJson['objects'] as Map<String, dynamic>? ?? {});
        final entries = objects.entries.toList();
        final objectsDir = Directory(p.join(assetsRoot, 'objects'));
        await objectsDir.create(recursive: true);

        var assetDone = 0;
        for (final entry in entries) {
          assetDone++;
          final obj = entry.value as Map<String, dynamic>;
          final hash = obj['hash'] as String;
          final prefix = hash.substring(0, 2);
          final dest = p.join(objectsDir.path, prefix, hash);
          if (await File(dest).exists()) {
            if (assetDone % 50 == 0 || assetDone == entries.length) {
              report(
                stage: 'Downloading assets',
                current: assetDone,
                total: entries.length,
                currentFile: entry.key,
              );
            }
            continue;
          }
          report(
            stage: 'Downloading assets',
            current: assetDone,
            total: entries.length,
            currentFile: entry.key,
          );
          final url =
              'https://resources.download.minecraft.net/$prefix/$hash';
          await _downloadFile(
            urls: DownloadSourceRegistry.candidatesFor(url, source),
            dest: dest,
            expectedSha1: hash,
          );
        }

        // Pre-1.6 style versions read resources from flat layouts
        // ("virtual" dir or the game's resources folder).
        await ensureLegacyAssetLayouts(indexId);
      }

      // Logging config (optional)
      final logging = versionJson['logging'] as Map<String, dynamic>?;
      final clientLog = logging?['client'] as Map<String, dynamic>?;
      final logFile = clientLog?['file'] as Map<String, dynamic>?;
      if (logFile != null) {
        final logId = logFile['id'] as String;
        final logDest = p.join(
          await PathService.instance.assetsDir(),
          'log_configs',
          logId,
        );
        await _downloadFile(
          urls: DownloadSourceRegistry.candidatesFor(
            logFile['url'] as String,
            source,
          ),
          dest: logDest,
          expectedSha1: logFile['sha1'] as String?,
        );
      }

      report(
        stage: 'Complete',
        current: 1,
        total: 1,
        done: true,
        currentFile: version.id,
      );
    } catch (e) {
      report(
        stage: 'Error',
        current: 0,
        total: 1,
        done: true,
        error: e.toString(),
      );
      rethrow;
    }
  }

  /// Downloads every allowed library (and extracts natives). Reused by
  /// vanilla downloads and by Fabric profile installation.
  Future<void> downloadLibraries({
    required Iterable<dynamic> libraries,
    required DownloadSource source,
    String? extractNativesFor,
    void Function(int current, int total, String fileName)? onProgress,
  }) async {
    final libs = libraries
        .whereType<Map<String, dynamic>>()
        .where(_libraryAllowed)
        .toList();
    final libsDir = await PathService.instance.librariesDir();
    await Directory(libsDir).create(recursive: true);

    var index = 0;
    for (final lib in libs) {
      index++;
      final artifact = _artifactDownload(lib);
      if (artifact != null) {
        final path =
            artifact['path'] as String? ?? _mavenPath(lib['name'] as String);
        final dest = p.join(libsDir, path);
        onProgress?.call(index, libs.length, p.basename(path));
        if (!await File(dest).exists()) {
          await _downloadFile(
            urls: DownloadSourceRegistry.libraryCandidates(
              artifact['url'] as String,
              path,
              source,
            ),
            dest: dest,
            expectedSha1:
                artifact['sha1'] as String? ?? lib['sha1'] as String?,
          );
        }
      }

      final native = _nativeDownload(lib);
      if (native != null) {
        final path = native['path'] as String? ??
            _mavenPath(
              lib['name'] as String,
              classifier: native['classifier'] as String?,
            );
        final dest = p.join(libsDir, path);
        if (!await File(dest).exists()) {
          await _downloadFile(
            urls: DownloadSourceRegistry.candidatesFor(
              native['url'] as String,
              source,
            ),
            dest: dest,
            expectedSha1: native['sha1'] as String?,
          );
        }
        if (extractNativesFor != null) {
          await _extractNatives(dest, extractNativesFor, lib);
        }
      }
    }
  }

  /// Builds the flat asset layouts used by pre-1.6 versions:
  /// - `virtual: true` (or the `legacy` index) -> `<assets>/virtual/<id>/`
  /// - `map_to_resources: true`              -> `<gameDir>/resources/`
  /// Files are copied from the hashed object store; existing files are
  /// skipped so repeated launches stay cheap.
  Future<void> ensureLegacyAssetLayouts(String indexId) async {
    final assetsRoot = await PathService.instance.assetsDir();
    final indexFile = File(p.join(assetsRoot, 'indexes', '$indexId.json'));
    if (!await indexFile.exists()) return;

    Map<String, dynamic> index;
    try {
      index =
          jsonDecode(await indexFile.readAsString()) as Map<String, dynamic>;
    } catch (_) {
      return;
    }

    final objects = index['objects'] as Map<String, dynamic>? ?? {};
    if (objects.isEmpty) return;

    final targets = <Directory>[
      if (index['virtual'] == true || indexId == 'legacy')
        Directory(p.join(assetsRoot, 'virtual', indexId)),
      if (index['map_to_resources'] == true)
        Directory(p.join(await PathService.instance.gameDirectory(), 'resources')),
    ];
    if (targets.isEmpty) return;

    for (final target in targets) {
      await target.create(recursive: true);
      for (final entry in objects.entries) {
        final obj = entry.value as Map<String, dynamic>;
        final hash = obj['hash'] as String?;
        if (hash == null || hash.length < 2) continue;

        final segments = entry.key.split('/');
        if (segments.any((s) => s == '..' || s.isEmpty)) continue;

        final dest = File(p.joinAll([target.path, ...segments]));
        if (await dest.exists()) continue;

        final src = File(p.join(objectsRoot(assetsRoot), hash.substring(0, 2), hash));
        if (!await src.exists()) continue;
        try {
          await dest.parent.create(recursive: true);
          await src.copy(dest.path);
        } catch (_) {}
      }
    }
  }

  static String objectsRoot(String assetsRoot) => p.join(assetsRoot, 'objects');

  bool _libraryAllowed(Map<String, dynamic> lib) {
    final rules = lib['rules'] as List<dynamic>?;
    if (rules == null || rules.isEmpty) return true;

    var allowed = false;
    for (final rule in rules) {
      final map = rule as Map<String, dynamic>;
      final action = map['action'] as String? ?? 'allow';
      final os = map['os'] as Map<String, dynamic>?;
      final matchesOs = os == null || _osMatches(os);
      if (matchesOs) {
        allowed = action == 'allow';
      }
    }
    return allowed;
  }

  bool _osMatches(Map<String, dynamic> os) {
    final name = os['name'] as String?;
    if (name == null) return true;
    if (Platform.isWindows) return name == 'windows';
    if (Platform.isLinux) return name == 'linux';
    if (Platform.isMacOS) return name == 'osx';
    return false;
  }

  Map<String, dynamic>? _artifactDownload(Map<String, dynamic> lib) =>
      artifactDownloadForTest(lib);

  @visibleForTesting
  static Map<String, dynamic>? artifactDownloadForTest(
    Map<String, dynamic> lib,
  ) {
    final downloads = lib['downloads'] as Map<String, dynamic>?;
    final artifact = downloads?['artifact'] as Map<String, dynamic>?;
    if (artifact != null && artifact['url'] != null) {
      return {
        'url': artifact['url'],
        'path': artifact['path'],
        'sha1': artifact['sha1'],
      };
    }
    // Natives-only libraries (e.g. lwjgl-platform) expose classifiers but no
    // main artifact; downloading a synthesized jar would just hit 404.
    if (downloads?['classifiers'] is Map<String, dynamic>) {
      return null;
    }
    final name = lib['name'] as String?;
    if (name == null) return null;
    final urlBase = lib['url'] as String? ?? 'https://libraries.minecraft.net/';
    final path = mavenPathForTest(name);
    return {
      'url': '$urlBase$path',
      'path': path,
      'sha1': null,
    };
  }

  Map<String, dynamic>? _nativeDownload(Map<String, dynamic> lib) {
    final natives = lib['natives'] as Map<String, dynamic>?;
    if (natives == null) return null;

    String? classifierKey;
    if (Platform.isWindows) {
      classifierKey = natives['windows'] as String?;
    } else if (Platform.isLinux) {
      classifierKey = natives['linux'] as String?;
    } else if (Platform.isMacOS) {
      classifierKey = natives['osx'] as String?;
    }
    if (classifierKey == null) return null;
    classifierKey = classifierKey.replaceAll(
      '\${arch}',
      _archToken(),
    );

    final downloads = lib['downloads'] as Map<String, dynamic>?;
    final classifiers = downloads?['classifiers'] as Map<String, dynamic>?;
    final native = classifiers?[classifierKey] as Map<String, dynamic>?;
    if (native != null && native['url'] != null) {
      return {
        'url': native['url'],
        'path': native['path'],
        'sha1': native['sha1'],
        'classifier': classifierKey,
      };
    }
    return null;
  }

  String _archToken() {
    final arch = Platform.version; // fallback
    // Prefer environment / process arch
    if (Platform.isWindows) {
      final proc = Platform.environment['PROCESSOR_ARCHITECTURE'] ?? '';
      if (proc.toUpperCase().contains('ARM')) return 'arm64';
      return 'x86'; // historical natives use x86 even on x64 for some jars
    }
    return arch.contains('arm') ? 'arm64' : 'x64';
  }

  String _mavenPath(String name, {String? classifier}) =>
      mavenPathForTest(name, classifier: classifier);

  @visibleForTesting
  static String mavenPathForTest(String name, {String? classifier}) {
    final parts = name.split(':');
    if (parts.length < 3) return name.replaceAll(':', '/');
    final group = parts[0].replaceAll('.', '/');
    final artifact = parts[1];
    final version = parts[2];
    final classifierSuffix =
        classifier != null ? '-$classifier' : '';
    final extension = parts.length > 3 ? parts[3] : 'jar';
    return '$group/$artifact/$version/$artifact-$version$classifierSuffix.$extension';
  }

  Future<void> _extractNatives(
    String jarPath,
    String versionId,
    Map<String, dynamic> lib,
  ) async {
    final nativesDir =
        Directory(await PathService.instance.nativesDir(versionId));
    await nativesDir.create(recursive: true);

    final bytes = await File(jarPath).readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);

    final extract = lib['extract'] as Map<String, dynamic>?;
    final exclude =
        (extract?['exclude'] as List<dynamic>? ?? []).cast<String>();

    for (final file in archive) {
      final name = file.name;
      if (exclude.any((e) => name.startsWith(e))) continue;
      if (name.endsWith('/')) continue;
      final outPath = p.join(nativesDir.path, name);
      final outFile = File(outPath);
      await outFile.parent.create(recursive: true);
      await outFile.writeAsBytes(file.content);
    }
  }

  Future<http.Response> _fetchAny(List<String> urls) async {
    Object? lastError;
    for (final url in urls) {
      try {
        final response = await _client
            .get(Uri.parse(url))
            .timeout(const Duration(seconds: 60));
        if (response.statusCode == 200) return response;
        lastError = HttpException(
          'Request failed (${response.statusCode}): $url',
        );
      } catch (e) {
        lastError = e;
      }
    }
    throw lastError ?? HttpException('Request failed: $urls');
  }

  Future<void> _downloadFile({
    required List<String> urls,
    required String dest,
    String? expectedSha1,
    void Function(int received, int total)? onBytes,
  }) async {
    if (urls.isEmpty) throw ArgumentError('No download URLs provided');
    Object? lastError;
    for (final url in urls) {
      try {
        await _downloadSingle(
          url: url,
          dest: dest,
          expectedSha1: expectedSha1,
          onBytes: onBytes,
        );
        return;
      } catch (e) {
        lastError = e;
      }
    }
    throw lastError!;
  }

  Future<void> _downloadSingle({
    required String url,
    required String dest,
    String? expectedSha1,
    void Function(int received, int total)? onBytes,
  }) async {
    final file = File(dest);
    await file.parent.create(recursive: true);

    final request = http.Request('GET', Uri.parse(url));
    final response = await _client.send(request).timeout(
          const Duration(seconds: 60),
          onTimeout: () => throw TimeoutException('Connect timeout: $url'),
        );
    if (response.statusCode != 200) {
      await response.stream.drain<void>().catchError((_) {});
      throw HttpException(
        'Download failed (${response.statusCode}): $url',
      );
    }

    final total = response.contentLength ?? 0;
    final sink = file.openWrite();
    var received = 0;

    try {
      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        onBytes?.call(received, total);
      }
      await sink.flush();
      await sink.close();

      if (expectedSha1 != null && expectedSha1.isNotEmpty) {
        final actual = sha1.convert(await file.readAsBytes()).toString();
        if (actual.toLowerCase() != expectedSha1.toLowerCase()) {
          await file.delete();
          throw StateError(
            'SHA1 mismatch for $dest (expected $expectedSha1, got $actual)',
          );
        }
      }
    } catch (e) {
      try {
        await sink.close();
      } catch (_) {}
      if (await file.exists()) {
        try {
          await file.delete();
        } catch (_) {}
      }
      rethrow;
    }
  }
}
