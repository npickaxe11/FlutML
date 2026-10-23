import 'package:flutter_test/flutter_test.dart';
import 'package:minecraft_launcher/models/account.dart';
import 'package:minecraft_launcher/models/launcher_settings.dart';
import 'package:minecraft_launcher/services/version_service.dart';

void main() {
  group('Account model', () {
    test('offline roundtrip', () {
      const account = Account(username: 'Steve', uuid: 'abc');
      final restored = Account.fromJson(account.toJson());
      expect(restored.username, 'Steve');
      expect(restored.type, AccountType.offline);
      expect(restored.isOffline, isTrue);
    });

    test('microsoft roundtrip keeps tokens', () {
      const account = Account(
        username: 'Alex',
        uuid: 'uuid-1',
        type: AccountType.msa,
        accessToken: 'at',
        refreshToken: 'rt',
        expiresAtMs: 123456789,
      );
      final restored = Account.fromJson(account.toJson());
      expect(restored.type, AccountType.msa);
      expect(restored.accessToken, 'at');
      expect(restored.refreshToken, 'rt');
      expect(restored.expiresAtMs, 123456789);
      expect(restored.isOffline, isFalse);
    });

    test('skin server roundtrip keeps server info', () {
      const account = Account(
        username: 'SkinUser',
        uuid: 'u2',
        type: AccountType.authlib,
        accessToken: 'tok',
        authServerUrl: 'https://skin.example.com/api/yggdrasil',
        authServerName: 'ExampleSkin',
      );
      final restored = Account.fromJson(account.toJson());
      expect(restored.type, AccountType.authlib);
      expect(restored.authServerUrl, 'https://skin.example.com/api/yggdrasil');
      expect(restored.authServerName, 'ExampleSkin');
    });

    test('legacy json without type falls back to offline', () {
      final restored =
          Account.fromJson({'username': 'Old', 'uuid': 'u3'});
      expect(restored.type, AccountType.offline);
    });

    test('token expiry detection with 5 minute buffer', () {
      final now = DateTime.now().millisecondsSinceEpoch;
      final fresh = Account(
        username: 'a',
        uuid: 'b',
        type: AccountType.msa,
        accessToken: 't',
        expiresAtMs: now + 3600 * 1000,
      );
      final stale = Account(
        username: 'a',
        uuid: 'b',
        type: AccountType.msa,
        accessToken: 't',
        expiresAtMs: now + 60 * 1000, // within the 5 min buffer
      );
      expect(fresh.tokenExpired, isFalse);
      expect(stale.tokenExpired, isTrue);
    });
  });

  group('Per-version Java overrides', () {
    test('override lookup and clearing', () {
      var settings = const LauncherSettings().copyWith(
        javaOverrides: {'1.21.4': r'C:\Java\17\bin\java.exe'},
      );
      expect(settings.javaOverrideFor('1.21.4'), r'C:\Java\17\bin\java.exe');
      expect(settings.javaOverrideFor('1.7.10'), '');

      // Simulate clearing by writing an empty path.
      final map = Map<String, String>.from(settings.javaOverrides);
      map.remove('1.21.4');
      settings = settings.copyWith(javaOverrides: map);
      expect(settings.javaOverrideFor('1.21.4'), '');
    });

    test('overrides persist through json roundtrip', () {
      const settings = LauncherSettings(
        javaPath: r'C:\default\java.exe',
        javaOverrides: {
          '1.21.4-fabric': r'C:\Java\21\bin\java.exe',
          'b1.7.3': r'C:\Java\8\bin\java.exe',
        },
      );
      final restored = LauncherSettings.fromJson(settings.toJson());
      expect(restored.javaPath, r'C:\default\java.exe');
      expect(restored.javaOverrideFor('1.21.4-fabric'),
          r'C:\Java\21\bin\java.exe');
      expect(restored.javaOverrideFor('b1.7.3'), r'C:\Java\8\bin\java.exe');
      expect(restored.javaOverrideFor('missing'), '');
    });
  });

  group('Version inheritance merge (Fabric/Forge profiles)', () {
    test('child overrides mainClass and appends arguments', () {
      final parent = <String, dynamic>{
        'id': '1.21.4',
        'mainClass': 'net.minecraft.client.main.Main',
        'arguments': {
          'game': ['--gameDir', '\${game_directory}'],
          'jvm': ['-Djava.library.path=\${natives_directory}'],
        },
        'assetIndex': {'id': '17'},
        'downloads': {
          'client': {'url': 'https://example.com/client.jar'},
        },
        'libraries': [
          {'name': 'com.mojang:brigadier:1.0.18'},
        ],
      };
      final child = <String, dynamic>{
        'id': 'fabric-loader-0.16.14-1.21.4',
        'inheritsFrom': '1.21.4',
        'mainClass': 'net.fabricmc.loader.impl.launch.knot.KnotClient',
        'arguments': {
          'game': ['--fpack'],
          'jvm': ['-Dfabric.game=ok'],
        },
        'libraries': [
          {'name': 'org.ow2.asm:asm:9.8'},
        ],
      };

      final merged = VersionService.mergeInheritedForTest(
        parent,
        '1.21.4',
        child,
        'fabric-loader-0.16.14-1.21.4',
      );

      expect(merged['id'], 'fabric-loader-0.16.14-1.21.4');
      expect(merged['mainClass'], contains('knot'));
      // Parent args kept, child args appended.
      expect((merged['arguments']['game'] as List).length, 3);
      expect((merged['arguments']['jvm'] as List).length, 2);
      // Parent-only keys survive for launching.
      expect((merged['assetIndex'] as Map)['id'], '17');
      expect(((merged['downloads'] as Map)['client'] as Map), isNotEmpty);
      // Libraries concatenated.
      expect((merged['libraries'] as List).length, 2);
      expect(merged.containsKey('inheritsFrom'), isFalse);
    });

    test('child library with same name replaces parent one', () {
      final parent = <String, dynamic>{
        'libraries': [
          {
            'name': 'org.ow2.asm:asm:9.8',
            'url': 'https://old.example/',
          },
          {'name': 'other:lib:1.0'},
        ],
      };
      final child = <String, dynamic>{
        'libraries': [
          {'name': 'org.ow2.asm:asm:9.8'},
        ],
      };

      final merged = VersionService.mergeInheritedForTest(
        parent,
        'p',
        child,
        'c',
      );

      final libs = merged['libraries'] as List;
      expect(libs.length, 2);
      expect(
        libs.where((l) => (l as Map)['name'] == 'org.ow2.asm:asm:9.8').length,
        1,
      );
    });

    test('parent map is not mutated by merge', () {
      final parent = <String, dynamic>{
        'mainClass': 'parent.Main',
        'libraries': [
          {'name': 'a:b:1.0'},
        ],
      };
      final child = <String, dynamic>{
        'mainClass': 'child.Main',
        'libraries': [
          {'name': 'c:d:2.0'},
        ],
      };

      VersionService.mergeInheritedForTest(parent, 'p', child, 'c');

      expect(parent['mainClass'], 'parent.Main');
      expect((parent['libraries'] as List).length, 1);
    });
  });
}
