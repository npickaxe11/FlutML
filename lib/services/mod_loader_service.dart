import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data' show BytesBuilder;

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../models/download_source.dart';
import 'download_service.dart';
import 'download_source_registry.dart';
import 'path_service.dart';

class FabricLoaderInfo {
  const FabricLoaderInfo({required this.version, required this.stable});

  final String version;
  final bool stable;
}

class ForgeBuild {
  const ForgeBuild({required this.mcVersion, required this.forgeVersion});

  final String mcVersion;
  final String forgeVersion;

  String get installerRelativePath {
    final dir = '$mcVersion-$forgeVersion';
    return '$dir/forge-$dir-installer.jar';
  }

  /// Forge's own installed version name, e.g. `1.21.4-forge-54.1.18`.
  /// Old branches (<=1.12) use a different scheme, so installs detect the
  /// actual folder by diffing the versions directory.
  String get predictedVersionId => '$mcVersion-forge-$forgeVersion';
}

/// Installs Fabric / Forge / Fabric API on top of vanilla versions.
class ModLoaderService {
  ModLoaderService({
    http.Client? client,
    DownloadService? downloadService,
  })  : _client = client ?? http.Client(),
      _downloads = downloadService ?? DownloadService();

  final http.Client _client;
  final DownloadService _downloads;

  // ---------- Fabric ----------

  Future<List<FabricLoaderInfo>> fabricLoaders(
    String gameVersion,
    DownloadSource source,
  ) async {
    final candidates = DownloadSourceRegistry.fabricMetaCandidates(
      '/v2/versions/loader/$gameVersion',
      source,
    );
    Object? lastError;
    for (final url in candidates) {
      try {
        final response =
            await _client.get(Uri.parse(url)).timeout(const Duration(seconds: 30));
        if (response.statusCode != 200) {
          lastError = HttpException('Fabric meta ${response.statusCode}');
          continue;
        }
        final list = jsonDecode(utf8.decode(response.bodyBytes)) as List<dynamic>;
        return list
            .whereType<Map<String, dynamic>>()
            .map((e) => e['loader'] as Map<String, dynamic>?)
            .whereType<Map<String, dynamic>>()
            .map((l) => FabricLoaderInfo(
                  version: l['version'] as String,
                  stable: l['stable'] as bool? ?? false,
                ))
            .toList();
      } catch (e) {
        lastError = e;
      }
    }
    throw StateError('Failed to query Fabric loaders: $lastError');
  }

  /// Installs a fabric profile (json + its libraries) and returns its id.
  Future<String> installFabric({
    required String gameVersion,
    required String loaderVersion,
    required DownloadSource source,
    void Function(String status)? onStatus,
  }) async {
    onStatus?.call('Fetching Fabric profile…');
    final path = '/v2/versions/loader/$gameVersion/$loaderVersion/profile/json';
    Object? lastError;
    for (final url
        in DownloadSourceRegistry.fabricMetaCandidates(path, source)) {
      try {
        final response = await _client
            .get(Uri.parse(url))
            .timeout(const Duration(seconds: 30));
        if (response.statusCode != 200) {
          lastError = HttpException('Fabric profile ${response.statusCode}');
          continue;
        }
        final profile =
            jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
        final id = profile['id'] as String;

        final versionsRoot = await PathService.instance.versionsDir();
        final versionDir = Directory(p.join(versionsRoot, id));
        await versionDir.create(recursive: true);
        await File(p.join(versionDir.path, '$id.json')).writeAsString(
          const JsonEncoder.withIndent('  ').convert(profile),
        );

        onStatus?.call('Downloading Fabric libraries…');
        await _downloads.downloadLibraries(
          libraries: (profile['libraries'] as List<dynamic>? ?? []),
          source: source,
        );
        return id;
      } catch (e) {
        lastError = e;
      }
    }
    throw StateError('Failed to install Fabric: $lastError');
  }

  // ---------- Forge ----------

  Future<List<ForgeBuild>> forgeBuilds(String gameVersion) async {
    const promosUrl =
        'https://files.minecraftforge.net/net/minecraftforge/forge/promotions_slim.json';
    final response =
        await _client.get(Uri.parse(promosUrl)).timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      throw HttpException('Forge promotions (${response.statusCode})');
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final promos = json['promos'] as Map<String, dynamic>? ?? {};
    final builds = <ForgeBuild>[];
    final seen = <String>{};
    for (final suffix in ['-recommended', '-latest']) {
      final build = promos['$gameVersion$suffix'] as String?;
      if (build == null || !seen.add(build)) continue;
      builds.add(ForgeBuild(mcVersion: gameVersion, forgeVersion: build));
    }
    return builds;
  }

  /// Downloads and runs the official Forge installer headlessly.
  /// Returns the version id of the freshly installed Forge profile.
  Future<String> installForge({
    required String gameVersion,
    required ForgeBuild build,
    required String javaPath,
    required String gameRoot,
    required DownloadSource source,
    void Function(String logLine)? onLog,
  }) async {
    final versionsRoot = Directory(p.join(gameRoot, 'versions'));
    final before = await _listDirNames(versionsRoot);

    final configDir = await PathService.instance.launcherConfigDir();
    final installerPath = '$configDir${Platform.pathSeparator}'
        'forge-${build.mcVersion}-${build.forgeVersion}-installer.jar';

    onLog?.call('Downloading Forge installer…');
    Object? lastError;
    var downloaded = false;
    for (final url in DownloadSourceRegistry.forgeInstallerCandidates(
      build.installerRelativePath,
      source,
    )) {
      try {
        final response = await _client
            .send(http.Request('GET', Uri.parse(url)))
            .timeout(const Duration(minutes: 10));
        if (response.statusCode != 200) {
          lastError = HttpException('${response.statusCode}: $url');
          continue;
        }
        final builder = BytesBuilder(copy: false);
        await for (final chunk in response.stream) {
          builder.add(chunk);
        }
        await File(installerPath).writeAsBytes(builder.takeBytes(), flush: true);
        downloaded = true;
        break;
      } catch (e) {
        lastError = e;
      }
    }
    if (!downloaded) {
      throw StateError('Failed to download Forge installer: $lastError');
    }

    onLog?.call('Running Forge installer (this can take a while)…');
    final process = await Process.start(
      javaPath.trim().isEmpty ? 'java' : javaPath.trim(),
      [
        '-jar',
        installerPath,
        '--installClient',
        gameRoot,
      ],
      workingDirectory: configDir,
    );

    final output = StringBuffer();
    final decoder = const Utf8Decoder(allowMalformed: true);
    void pipe(Stream<List<int>> stream) {
      stream.cast<List<int>>().transform(decoder).listen((line) {
        output.write(line);
        for (final l in line.split(RegExp(r'\r?\n'))) {
          final t = l.trim();
          if (t.isNotEmpty) onLog?.call(t);
        }
      });
    }

    pipe(process.stdout);
    pipe(process.stderr);
    final code = await process.exitCode.timeout(const Duration(minutes: 15));
    try {
      await File(installerPath).delete();
    } catch (_) {}

    if (code != 0) {
      final trimmed = output.toString().trim();
      final tail =
          trimmed.length > 800 ? '…${trimmed.substring(trimmed.length - 800)}' : trimmed;
      throw StateError('Forge installer exited with code $code.\n$tail');
    }

    final after = await _listDirNames(versionsRoot);
    final added = after.difference(before).toList();
    if (added.isEmpty) {
      final predicted = build.predictedVersionId;
      if (after.contains(predicted)) return predicted;
      throw StateError(
        'Forge installer finished but no new version folder was found',
      );
    }
    return added.first;
  }

  Future<Set<String>> _listDirNames(Directory dir) async {
    if (!await dir.exists()) return <String>{};
    final names = <String>{};
    await for (final e in dir.list()) {
      if (e is Directory) names.add(p.basename(e.path));
    }
    return names;
  }
}
