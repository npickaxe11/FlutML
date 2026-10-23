import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import '../models/modrinth_models.dart';

class ModrinthService {
  ModrinthService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const _host = 'api.modrinth.com';
  static const _userAgent =
      'flut-launcher/1.0.0 (https://gitee.com/npickaxe11/flut-ml)';

  Map<String, String> get _headers => const {
    'User-Agent': _userAgent,
    'Accept': 'application/json',
  };

  Future<ModrinthSearchResult> search({
    String query = '',
    ResourceType type = ResourceType.mod,
    String gameVersion = '',
    String loader = '',
    ResourceSort sort = ResourceSort.relevance,
    int limit = 20,
    int offset = 0,
  }) async {
    final facets = <List<String>>[
      ['project_type:${type.slug}'],
      if (gameVersion.trim().isNotEmpty) ['versions:${gameVersion.trim()}'],
      if (loader.isNotEmpty && type.supportsLoader) ['categories:$loader'],
    ];
    final params = <String, String>{
      'query': query.trim(),
      'index': sort.value,
      'limit': '$limit',
      'offset': '$offset',
    };
    if (facets.isNotEmpty) {
      params['facets'] = jsonEncode(facets);
    }

    final json = await _getJson(Uri.https(_host, '/v2/search', params));
    return ModrinthSearchResult.fromJson(json);
  }

  Future<ModrinthProject> fetchProject(String idOrSlug) async {
    final json = await _getJson(
      Uri.https(_host, '/v2/project/${Uri.encodeComponent(idOrSlug)}'),
    );
    return ModrinthProject.fromJson(json);
  }

  Future<List<ModrinthVersion>> fetchVersions(
    String idOrSlug, {
    String gameVersion = '',
    String loader = '',
    ResourceType? type,
  }) async {
    final params = <String, String>{};
    if (gameVersion.trim().isNotEmpty) {
      params['game_versions'] = jsonEncode([gameVersion.trim()]);
    }
    if (loader.isNotEmpty && (type?.supportsLoader ?? true)) {
      params['loaders'] = jsonEncode([loader]);
    }

    final response = await _get(
      Uri.https(
        _host,
        '/v2/project/${Uri.encodeComponent(idOrSlug)}/version',
        params.isEmpty ? null : params,
      ),
    );
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! List) {
      throw const FormatException('Unexpected Modrinth version response');
    }

    final versions = decoded
        .whereType<Map<String, dynamic>>()
        .map(ModrinthVersion.fromJson)
        .toList();

    // The API already filters, but older mirrors may ignore query params.
    final wantedVersion = gameVersion.trim();
    return versions.where((version) {
      if (wantedVersion.isNotEmpty &&
          !version.gameVersions.contains(wantedVersion)) {
        return false;
      }
      if (loader.isNotEmpty &&
          (type?.supportsLoader ?? true) &&
          !version.loaders.contains(loader)) {
        return false;
      }
      return true;
    }).toList()..sort((a, b) {
      final at = a.published ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bt = b.published ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bt.compareTo(at);
    });
  }

  Future<void> downloadFile({
    required String url,
    required String destination,
    String? expectedSha1,
    void Function(int received, int total)? onProgress,
  }) async {
    final file = File(destination);
    await file.parent.create(recursive: true);

    final request = http.Request('GET', Uri.parse(url));
    request.headers['User-Agent'] = _userAgent;
    final response = await _client
        .send(request)
        .timeout(
          const Duration(seconds: 60),
          onTimeout: () => throw TimeoutException('Connect timeout: $url'),
        );
    if (response.statusCode != 200) {
      await response.stream.drain<void>().catchError((_) {});
      throw HttpException('Download failed (${response.statusCode}): $url');
    }

    final total = response.contentLength ?? 0;
    final sink = file.openWrite();
    var received = 0;

    try {
      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(received, total);
      }
      await sink.flush();
      await sink.close();

      if (expectedSha1 != null && expectedSha1.isNotEmpty) {
        final actual = sha1.convert(await file.readAsBytes()).toString();
        if (actual.toLowerCase() != expectedSha1.toLowerCase()) {
          await file.delete();
          throw StateError(
            'SHA1 mismatch for $destination '
            '(expected $expectedSha1, got $actual)',
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

  Future<Map<String, dynamic>> _getJson(Uri uri) async {
    final response = await _get(uri);
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Unexpected Modrinth response');
    }
    return decoded;
  }

  Future<http.Response> _get(Uri uri) async {
    final response = await _client
        .get(uri, headers: _headers)
        .timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      throw HttpException(
        'Modrinth request failed (${response.statusCode}): $uri',
      );
    }
    return response;
  }
}
