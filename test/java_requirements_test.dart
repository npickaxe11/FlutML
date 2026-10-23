import 'package:flutter_test/flutter_test.dart';
import 'package:minecraft_launcher/services/java_detector.dart';
import 'package:minecraft_launcher/services/mc_java_requirements.dart';

void main() {
  group('extractMinecraftVersion', () {
    test('vanilla ids', () {
      expect(McJavaRequirements.extractMinecraftVersion('1.8.9'), '1.8.9');
      expect(
        McJavaRequirements.extractMinecraftVersion('1.20.4'),
        '1.20.4',
      );
    });

    test('loader-flavoured ids', () {
      expect(
        McJavaRequirements.extractMinecraftVersion(
          'fabric-loader-0.16.14-1.21.4',
        ),
        '1.21.4',
      );
      expect(
        McJavaRequirements.extractMinecraftVersion('1.20.1-forge-47.2.0'),
        '1.20.1',
      );
      expect(
        McJavaRequirements.extractMinecraftVersion(
          '1.20.4-neoforge-20.4.80',
        ),
        '1.20.4',
      );
      expect(
        McJavaRequirements.extractMinecraftVersion(
          '1.12.2-OptiFine_HD_U_G5',
        ),
        '1.12.2',
      );
    });
  });

  group('requiredMajor', () {
    void check(String id, int expected) {
      expect(McJavaRequirements.requiredMajor(id), expected, reason: id);
    }

    test('old versions need Java 8', () {
      check('1.8.9', 8);
      check('1.7.10', 8);
      check('b1.7.3', 8);
      check('a1.2.5', 8);
      check('1.12.2', 8);
      check('1.16.5', 8);
    });

    test('modern version ranges', () {
      check('1.17', 16);
      check('1.17.1', 16);
      check('1.18', 17);
      check('1.19.4', 17);
      check('1.20.1', 17);
      check('1.20.4', 17);
      check('1.20.5', 21);
      check('1.21', 21);
      check('1.21.4', 21);
    });

    test('snapshots assumed modern, unknown default to 8', () {
      check('24w14a', 21);
      check('25w03a', 21);
      check('weird-custom-pack', 8);
    });

    test('json javaVersion wins over heuristic', () {
      expect(
        McJavaRequirements.requiredMajor('1.8.9', jsonMajor: 8),
        8,
      );
      expect(
        McJavaRequirements.requiredMajor('custom', jsonMajor: 21),
        21,
      );
    });
  });

  group('pickBest', () {
    final installs = [
      const JavaInstall(path: 'jre8', version: '1.8.0_51'),
      const JavaInstall(path: 'jre17', version: '17.0.15'),
      const JavaInstall(path: 'jre21', version: '21.0.12'),
      const JavaInstall(path: 'jdk25', version: '25.0.2'),
    ];

    test('exact match preferred (1.8.9 gets Java 8, not 21)', () {
      expect(McJavaRequirements.pickBest(installs, 8)!.path, 'jre8');
      expect(McJavaRequirements.pickBest(installs, 17)!.path, 'jre17');
      expect(McJavaRequirements.pickBest(installs, 21)!.path, 'jre21');
    });

    test('close newer beats far newer when no exact match', () {
      final onlyNew = [
        const JavaInstall(path: 'jre21', version: '21'),
        const JavaInstall(path: 'jdk25', version: '25'),
      ];
      // Required 17: 21 is close, 25 too far -> picks 21.
      expect(McJavaRequirements.pickBest(onlyNew, 17)!.path, 'jre21');
    });

    test('returns lowest sufficient when only far-newer exists', () {
      final only21 = [const JavaInstall(path: 'jre21', version: '21')];
      expect(McJavaRequirements.pickBest(only21, 8)!.path, 'jre21');
    });

    test('null when nothing new enough', () {
      final onlyOld = [const JavaInstall(path: 'jre8', version: '1.8')];
      expect(McJavaRequirements.pickBest(onlyOld, 17), isNull);
      expect(McJavaRequirements.pickBest(const [], 8), isNull);
    });
  });
}
