import 'package:flutter_test/flutter_test.dart';
import 'package:minecraft_launcher/models/download_source.dart';
import 'package:minecraft_launcher/models/launcher_settings.dart';
import 'package:minecraft_launcher/services/download_service.dart';
import 'package:minecraft_launcher/services/download_source_registry.dart';

void main() {
  test('official source keeps URLs untouched', () {
    const url = 'https://piston-data.mojang.com/v1/objects/abc/client.jar';
    expect(
      DownloadSourceRegistry.candidatesFor(url, DownloadSource.official),
      [url],
    );
  });

  test('china source mirrors mojang hosts and falls back to official', () {
    expect(
      DownloadSourceRegistry.candidatesFor(
        'https://launchermeta.mojang.com/mc/game/version_manifest_v2.json',
        DownloadSource.china,
      ),
      [
        'https://bmclapi2.bangbang93.com/mc/game/version_manifest_v2.json',
        'https://launchermeta.mojang.com/mc/game/version_manifest_v2.json',
      ],
    );
    expect(
      DownloadSourceRegistry.toMirror(
        'https://piston-data.mojang.com/v1/objects/abc/client.jar',
      ),
      'https://bmclapi2.bangbang93.com/v1/objects/abc/client.jar',
    );
    expect(
      DownloadSourceRegistry.toMirror(
        'https://libraries.minecraft.net/net/example/1.0/example-1.0.jar',
      ),
      'https://bmclapi2.bangbang93.com/maven/net/example/1.0/example-1.0.jar',
    );
    expect(
      DownloadSourceRegistry.toMirror(
        'https://resources.download.minecraft.net/ab/abcdef',
      ),
      'https://bmclapi2.bangbang93.com/assets/ab/abcdef',
    );
  });

  test('unknown hosts are used as-is with single candidate', () {
    const url = 'https://example.com/file.jar';
    expect(
      DownloadSourceRegistry.candidatesFor(url, DownloadSource.china),
      [url],
    );
  });

  test('settings roundtrip persists download source', () {
    final s = const LauncherSettings().copyWith(
      downloadSource: DownloadSource.china,
    );
    final json = s.toJson();
    expect(json['downloadSource'], 'china');
    expect(
      LauncherSettings.fromJson(json).downloadSource,
      DownloadSource.china,
    );
  });

  test('natives-only libraries are not given a synthesized artifact', () {
    const lib = <String, dynamic>{
      'name': 'org.lwjgl.lwjgl:lwjgl-platform:2.9.1',
      'downloads': {
        'classifiers': {
          'natives-windows': {
            'path':
                'org/lwjgl/lwjgl/lwjgl-platform/2.9.1/lwjgl-platform-2.9.1-natives-windows.jar',
            'url': 'https://libraries.minecraft.net/org/lwjgl/lwjgl/'
                'lwjgl-platform/2.9.1/lwjgl-platform-2.9.1-natives-windows.jar',
          },
        },
      },
      'natives': {'windows': 'natives-windows'},
    };
    expect(DownloadService.artifactDownloadForTest(lib), isNull);
  });

  test('libraries with an artifact block keep their metadata', () {
    const lib = <String, dynamic>{
      'name': 'com.mojang:brigadier:1.0.18',
      'downloads': {
        'artifact': {
          'path': 'com/mojang/brigadier/1.0.18/brigadier-1.0.18.jar',
          'url':
              'https://libraries.minecraft.net/com/mojang/brigadier/1.0.18/brigadier-1.0.18.jar',
          'sha1': 'abc123',
        },
      },
    };
    final artifact = DownloadService.artifactDownloadForTest(lib);
    expect(artifact, isNotNull);
    expect(artifact!['sha1'], 'abc123');
    expect(artifact['url'], contains('brigadier-1.0.18.jar'));
  });

  test('legacy libraries synthesize a canonical maven path', () {
    const lib = <String, dynamic>{
      'name': 'net.java.jinput:jinput:2.0.5',
    };
    final artifact = DownloadService.artifactDownloadForTest(lib);
    expect(artifact, isNotNull);
    expect(
      artifact!['path'],
      'net/java/jinput/jinput/2.0.5/jinput-2.0.5.jar',
    );
  });

  test('library candidates end with a Maven Central fallback', () {
    final candidates = DownloadSourceRegistry.libraryCandidates(
      'https://libraries.minecraft.net/org/example/foo/1.0/foo-1.0.jar',
      'org/example/foo/1.0/foo-1.0.jar',
      DownloadSource.official,
    );
    expect(candidates.last, 'https://repo1.maven.org/maven2/org/example/foo/1.0/foo-1.0.jar');
  });

  test('forge installer candidates respect source order', () {
    final rel = '1.21.4-54.1.18/forge-1.21.4-54.1.18-installer.jar';
    expect(
      DownloadSourceRegistry.forgeInstallerCandidates(rel, DownloadSource.china)
          .first,
      'https://bmclapi2.bangbang93.com/maven/net/minecraftforge/forge/$rel',
    );
    expect(
      DownloadSourceRegistry.forgeInstallerCandidates(
              rel, DownloadSource.official)
          .first,
      'https://maven.minecraftforge.net/net/minecraftforge/forge/$rel',
    );
  });

  test('fabric meta candidates respect source order', () {
    const path = '/v2/versions/loader/1.21.4';
    expect(
      DownloadSourceRegistry.fabricMetaCandidates(path, DownloadSource.china)
          .first,
      'https://bmclapi2.bangbang93.com/fabric-meta$path',
    );
    expect(
      DownloadSourceRegistry.fabricMetaCandidates(path, DownloadSource.official)
          .first,
      'https://meta.fabricmc.net$path',
    );
  });
}
