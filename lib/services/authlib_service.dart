import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' show sha256;
import 'package:http/http.dart' as http;

import '../models/account.dart';
import 'auth_models.dart';
import 'path_service.dart';

/// Client for Blessing-Skin style skin servers implementing the
/// authlib-injector authentication protocol.
class AuthlibService {
  AuthlibService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const clientToken = 'minecraft-launcher-flutter';

  /// Resolves a server base URL to its API root, following the
  /// X-Authlib-Injector-API-Location header as required by the spec.
  Future<AuthServerInfo> resolveServer(String inputUrl) async {
    var url = inputUrl.trim();
    if (url.isEmpty) throw const AuthException('Server URL is empty');
    if (!url.startsWith(RegExp(r'https?://'))) url = 'https://$url';
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }

    final first = await _getJson(url);
    final location = first.location;
    if (location == null || location.isEmpty) {
      // The URL itself was the API root.
      return _fromMetadata(first.body, url);
    }
    final apiRoot = Uri.parse(url).resolve(location).toString();
    var trimmed = apiRoot;
    if (trimmed.endsWith('/')) trimmed = trimmed.substring(0, trimmed.length - 1);
    try {
      final apiResponse = await _getJson(trimmed);
      return _fromMetadata(apiResponse.body, trimmed);
    } catch (_) {
      return AuthServerInfo(
        apiRoot: trimmed,
        serverName: Uri.parse(trimmed).host,
      );
    }
  }

  AuthServerInfo _fromMetadata(String body, String apiRoot) {
    final json = jsonDecode(body) as Map<String, dynamic>;
    final meta = json['meta'] as Map<String, dynamic>?;
    return AuthServerInfo(
      apiRoot: apiRoot,
      serverName: meta?['serverName'] as String? ?? Uri.parse(apiRoot).host,
    );
  }

  Future<_HttpResult> _getJson(String url) async {
    final response = await _client
        .get(Uri.parse(url))
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      throw AuthException('Skin server responded ${response.statusCode}');
    }
    try {
      jsonDecode(response.body);
    } catch (_) {
      throw AuthException('Skin server did not return valid metadata');
    }
    return _HttpResult(response.body, response.headers['x-authlib-injector-api-location']);
  }

  /// Authenticates against `{apiRoot}/authserver/authenticate`.
  Future<Account> login({
    required AuthServerInfo server,
    required String username,
    required String password,
  }) async {
    final root = server.apiRoot.endsWith('/')
        ? server.apiRoot.substring(0, server.apiRoot.length - 1)
        : server.apiRoot;
    final response = await _client
        .post(
          Uri.parse('$root/authserver/authenticate'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'username': username,
            'password': password,
            'clientToken': clientToken,
            'agent': {'name': 'Minecraft', 'version': 1},
          }),
        )
        .timeout(const Duration(seconds: 30));

    if (response.statusCode != 200) {
      String message = 'Login failed (${response.statusCode})';
      try {
        final err = jsonDecode(response.body) as Map<String, dynamic>;
        message = err['errorMessage'] as String? ?? message;
      } catch (_) {}
      throw AuthException(message);
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final accessToken = json['accessToken'] as String?;
    final profiles = (json['availableProfiles'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>();
    final selected = json['selectedProfile'] as Map<String, dynamic>? ??
        (profiles.isNotEmpty ? profiles.first : null);

    if (accessToken == null || selected == null) {
      throw const AuthException(
        'No Minecraft profile on this skin-station account',
      );
    }

    return Account(
      username: selected['name'] as String,
      uuid: selected['id'] as String,
      type: AccountType.authlib,
      accessToken: accessToken,
      expiresAtMs:
          DateTime.now().add(const Duration(days: 30)).millisecondsSinceEpoch,
      authServerUrl: root,
      authServerName: server.serverName,
    );
  }

  /// Downloads (and caches) the authlib-injector agent jar; returns its path.
  Future<String> ensureAgentJar({required bool preferChinaMirror}) async {
    const officialLatest =
        'https://authlib-injector.yushi.moe/artifact/latest.json';
    const mirrorLatest =
        'https://bmclapi2.bangbang93.com/mirrors/authlib-injector/artifact/latest.json';
    Object? lastError;
    Map<String, dynamic>? latest;

    for (final candidate in preferChinaMirror
        ? [mirrorLatest, officialLatest]
        : [officialLatest, mirrorLatest]) {
      try {
        final response = await http
            .get(Uri.parse(candidate))
            .timeout(const Duration(seconds: 20));
        if (response.statusCode == 200) {
          latest = jsonDecode(response.body) as Map<String, dynamic>;
          break;
        }
        lastError = StateError('latest.json (${response.statusCode})');
      } catch (e) {
        lastError = e;
      }
    }
    if (latest == null) {
      throw StateError('Failed to fetch authlib-injector metadata: $lastError');
    }

    final version = latest['version'] as String;
    final downloadUrl = latest['download_url'] as String;
    final expectedSha256 =
        (latest['checksums'] as Map<String, dynamic>?)?['sha256'] as String?;

    final configDir = await PathService.instance.launcherConfigDir();
    final jarPath =
        '$configDir${Platform.pathSeparator}authlib-injector-$version.jar';
    final jarFile = File(jarPath);
    if (await jarFile.exists()) {
      if (expectedSha256 == null ||
          _sha256Of(await jarFile.readAsBytes()) == expectedSha256) {
        return jarPath;
      }
      await jarFile.delete();
    }

    final mirrored = downloadUrl.replaceFirst(
      'https://authlib-injector.yushi.moe/artifact/',
      'https://bmclapi2.bangbang93.com/mirrors/authlib-injector/artifact/',
    );
    final urls = preferChinaMirror
        ? [mirrored, downloadUrl]
        : [downloadUrl, mirrored];
    Object? downloadError;
    for (final url in urls) {
      try {
        final response = await http
            .get(Uri.parse(url))
            .timeout(const Duration(minutes: 3));
        if (response.statusCode != 200) {
          downloadError = StateError('HTTP ${response.statusCode}: $url');
          continue;
        }
        final bytes = response.bodyBytes;
        if (expectedSha256 != null && _sha256Of(bytes) != expectedSha256) {
          downloadError = StateError('Checksum mismatch for $url');
          continue;
        }
        await jarFile.writeAsBytes(bytes, flush: true);
        return jarPath;
      } catch (e) {
        downloadError = e;
      }
    }
    throw StateError('Failed to download authlib-injector: $downloadError');
  }

  String _sha256Of(List<int> bytes) => sha256.convert(bytes).toString();
}

class _HttpResult {
  const _HttpResult(this.body, this.location);

  final String body;
  final String? location;
}
