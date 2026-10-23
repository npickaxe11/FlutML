import '../models/download_source.dart';

class DownloadSourceRegistry {
  DownloadSourceRegistry._();

  static const officialManifestUrl =
      'https://launchermeta.mojang.com/mc/game/version_manifest_v2.json';
  static const chinaManifestUrl =
      'https://bmclapi2.bangbang93.com/mc/game/version_manifest_v2.json';

  /// Last-resort repository for legacy libraries purged from Mojang's repo.
  static const mavenCentralUrl = 'https://repo1.maven.org/maven2/';

  static const _forgeInstallerBase =
      'https://maven.minecraftforge.net/net/minecraftforge/forge/';
  static const _forgeInstallerMirrorBase =
      'https://bmclapi2.bangbang93.com/maven/net/minecraftforge/forge/';
  static const _fabricMetaBase = 'https://meta.fabricmc.net';
  static const _fabricMetaMirrorBase = 'https://bmclapi2.bangbang93.com/fabric-meta';

  /// Forge installer jar candidates ([relativePath] like
  /// `1.21.4-54.1.18/forge-1.21.4-54.1.18-installer.jar`).
  static List<String> forgeInstallerCandidates(
    String relativePath,
    DownloadSource source,
  ) {
    final official = '$_forgeInstallerBase$relativePath';
    final mirror = '$_forgeInstallerMirrorBase$relativePath';
    return source == DownloadSource.china
        ? [mirror, official]
        : [official, mirror];
  }

  /// Fabric meta API candidates ([path] like
  /// `/v2/versions/loader/1.21.4`).
  static List<String> fabricMetaCandidates(
    String path,
    DownloadSource source,
  ) {
    final official = '$_fabricMetaBase$path';
    final mirror = '$_fabricMetaMirrorBase$path';
    return source == DownloadSource.china
        ? [mirror, official]
        : [official, mirror];
  }

  static List<String> libraryCandidates(
    String url,
    String mavenPath,
    DownloadSource source,
  ) {
    final candidates = candidatesFor(url, source);
    final central = '$mavenCentralUrl$mavenPath';
    return candidates.contains(central) ? candidates : [...candidates, central];
  }

  static String manifestUrl(DownloadSource source) =>
      source == DownloadSource.china ? chinaManifestUrl : officialManifestUrl;

  static List<String> manifestCandidates(DownloadSource source) => source ==
          DownloadSource.china
      ? [chinaManifestUrl, officialManifestUrl]
      : [officialManifestUrl, chinaManifestUrl];

  /// Returns download candidates for [url]: the mirrored URL first when the
  /// China source is selected, then the original official URL as fallback.
  static List<String> candidatesFor(String url, DownloadSource source) {
    if (source == DownloadSource.official) return [url];
    final mirrored = toMirror(url);
    if (mirrored == url) return [url];
    return [mirrored, url];
  }

  /// Rewrites official Mojang URLs onto the BMCLAPI mirror.
  static String toMirror(String url) {
    var u = url;
    u = _replace(u, 'https://resources.download.minecraft.net',
        'https://bmclapi2.bangbang93.com/assets');
    u = _replace(u, 'http://resources.download.minecraft.net',
        'https://bmclapi2.bangbang93.com/assets');
    u = _replace(u, 'https://libraries.minecraft.net',
        'https://bmclapi2.bangbang93.com/maven');
    u = _replace(u, 'http://libraries.minecraft.net',
        'https://bmclapi2.bangbang93.com/maven');
    u = _replace(u, 'https://launchermeta.mojang.com',
        'https://bmclapi2.bangbang93.com');
    u = _replace(
        u, 'https://piston-meta.mojang.com', 'https://bmclapi2.bangbang93.com');
    u = _replace(
        u, 'https://piston-data.mojang.com', 'https://bmclapi2.bangbang93.com');
    u = _replace(
        u, 'https://launcher.mojang.com', 'https://bmclapi2.bangbang93.com');
    u = _replace(
        u, 'http://launchermeta.mojang.com', 'https://bmclapi2.bangbang93.com');
    u = _replace(
        u, 'http://launcher.mojang.com', 'https://bmclapi2.bangbang93.com');
    return u;
  }

  static String _replace(String url, String from, String to) {
    if (url.startsWith(from)) {
      return to + url.substring(from.length);
    }
    return url;
  }
}
