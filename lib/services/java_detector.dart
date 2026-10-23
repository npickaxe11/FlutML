import 'dart:io';

import 'package:path/path.dart' as p;

class JavaInstall {
  const JavaInstall({required this.path, this.version});

  final String path;
  final String? version;

  /// Java 8 and older report legacy versions like `1.8.0_51`, where the
  /// actual major is the second component.
  int get major {
    final v = version;
    if (v == null) return 0;
    final parts = v.split('.');
    if (parts.isNotEmpty && parts.first == '1' && parts.length >= 2) {
      final second = int.tryParse(parts[1].split('_').first);
      if (second != null) return second;
    }
    return int.tryParse(v.split(RegExp(r'[._]')).first) ?? 0;
  }

  String get label => version == null ? path : 'Java $version';
}

/// Scans the system for installed Java runtimes and reads their versions.
///
/// Sources: JAVA_HOME, PATH, vendor registry trees (Oracle / Adoptium /
/// Microsoft / Azul), Program Files (+ x86, + LOCALAPPDATA), and every
/// fixed drive's top-level directories that look like Java installations
/// (portable JDKs on D:\\, E:\\, ...).
class JavaDetector {
  JavaDetector._();

  static final _dirNamePattern = RegExp(
    r'jdk|jre|java|temurin|adoptium|zulu|corretto|graal|liberica|'
        r'dragonwell|semeru|jbr|bellsoft',
    caseSensitive: false,
  );

  static const _registryKeys = [
    r'HKLM\SOFTWARE\JavaSoft',
    r'HKLM\SOFTWARE\WOW6432Node\JavaSoft',
    r'HKCU\Software\JavaSoft',
    r'HKLM\SOFTWARE\Eclipse Adoptium',
    r'HKCU\Software\Eclipse Adoptium',
    r'HKLM\SOFTWARE\Microsoft\JDK',
    r'HKLM\SOFTWARE\Azul Systems',
  ];

  static Future<List<JavaInstall>> detect() async {
    final executables = <String>{};

    await _fromEnvironment(executables);
    await _fromRegistry(executables);
    await _fromProgramDirs(executables);
    await _fromDriveRoots(executables);
    await _fromLauncherRuntimes(executables);

    final installs = <JavaInstall>[];
    for (final exe in executables) {
      if (!await File(exe).exists()) continue;
      installs.add(JavaInstall(path: exe, version: await _readVersion(exe)));
    }

    installs.sort((a, b) => b.major.compareTo(a.major));
    return installs;
  }

  // ---------- sources ----------

  static Future<void> _fromEnvironment(Set<String> out) async {
    final javaHome = Platform.environment['JAVA_HOME'];
    if (javaHome != null && javaHome.isNotEmpty) {
      _addExecutable(out, p.join(javaHome, 'bin', _javaExe()));
    }

    try {
      final result = await Process.run(
        Platform.isWindows ? 'where' : 'which',
        ['java'],
        runInShell: true,
      ).timeout(const Duration(seconds: 10));
      if (result.exitCode == 0) {
        for (final line in (result.stdout as String).split(RegExp(r'\r?\n'))) {
          if (line.trim().isNotEmpty) {
            _addExecutable(out, line.trim());
          }
        }
      }
    } catch (_) {}
  }

  /// Installer-registered Javas. Parses every absolute path found in the
  /// queried trees so vendor-specific value names all work.
  static Future<void> _fromRegistry(Set<String> out) async {
    if (!Platform.isWindows) return;
    for (final key in _registryKeys) {
      try {
        final result = await Process.run(
          'reg',
          ['query', key, '/s'],
        ).timeout(const Duration(seconds: 15));
        if (result.exitCode != 0) continue;
        final output =
            '${result.stdout}\n${result.stderr}';
        for (final match
            in RegExp(r'[A-Za-z]:\\[^\r\n"*?<>|\t]+').allMatches(output)) {
          final candidate = match.group(0)!.trim();
          if (candidate.toLowerCase().endsWith('\\bin\\${_javaExe()}')) {
            out.add(p.normalize(candidate));
          } else {
            _addExecutable(out, p.join(candidate, 'bin', _javaExe()));
          }
        }
      } catch (_) {}
    }
  }

  static Future<void> _fromProgramDirs(Set<String> out) async {
    final env = Platform.environment;
    final roots = <String>[
      env['ProgramFiles'] ?? r'C:\Program Files',
      env['ProgramFiles(x86)'] ?? r'C:\Program Files (x86)',
      if (env['LOCALAPPDATA'] != null)
        p.join(env['LOCALAPPDATA']!, 'Programs'),
      if (env['ProgramData'] != null) env['ProgramData']!,
    ];

    for (final root in roots) {
      final dir = Directory(root);
      if (!await dir.exists()) continue;
      await for (final entity in dir.list()) {
        if (entity is! Directory) continue;
        // Vendor layouts vary (Java\jdk-x, Eclipse Adoptium\jdk-x,
        // Microsoft\jdk-x, Zulu\zulu-x, ...) so probe every top-level
        // folder a couple of levels deep instead of filtering by name.
        await _probe(out, entity, 2);
      }
    }
  }

  /// Portable JDKs living directly on some drive, e.g. `D:\jdk-17`,
  /// `E:\Java\jdk-8`, `D:\Minecraft\runtimes\...`.
  static Future<void> _fromDriveRoots(Set<String> out) async {
    if (!Platform.isWindows) return;
    for (var code = 67; code <= 90; code++) {
      // C..Z
      final drive = '${String.fromCharCode(code)}:';
      final root = Directory('$drive\\');
      if (!await root.exists()) continue;
      try {
        await for (final entity in root.list()) {
          if (entity is! Directory) continue;
          final name = p.basename(entity.path);
          if (name.isEmpty || name.startsWith(r'$')) continue;
          if (!_dirNamePattern.hasMatch(name)) continue;
          await _probe(out, entity, 3);
        }
      } catch (_) {}
    }
  }

  /// Bundled runtimes of other launchers, e.g. the official Minecraft
  /// launcher keeps Java 8 / 17 / 21 under `.minecraft\runtime`.
  static Future<void> _fromLauncherRuntimes(Set<String> out) async {
    final env = Platform.environment;
    final candidates = <String>[
      if (env['APPDATA'] != null)
        p.join(env['APPDATA']!, '.minecraft', 'runtime'),
      if (env['LOCALAPPDATA'] != null)
        p.join(
          env['LOCALAPPDATA']!,
          'Packages',
          'Microsoft.4297127D64EC6_8wekyb3d8bbwe',
          'LocalCache',
          'Local',
          'runtime',
        ),
      r'C:\Program Files (x86)\Minecraft Launcher\runtime',
    ];
    for (final root in candidates) {
      final dir = Directory(root);
      if (!await dir.exists()) continue;
      // Layout: <name>\<platform>\<name>\bin\java.exe -> depth 4.
      await _probe(out, dir, 4);
    }
  }

  /// Recursively looks for `bin/java.exe` under [dir] up to [depth] levels.
  static Future<void> _probe(Set<String> out, Directory dir, int depth) async {
    try {
      _addExecutable(out, p.join(dir.path, 'bin', _javaExe()));
      if (depth <= 0) return;
      await for (final entity in dir.list()) {
        if (entity is! Directory) continue;
        final name = p.basename(entity.path);
        final lower = name.toLowerCase();
        if (name.startsWith('.') ||
            name.startsWith(r'$') ||
            lower == 'node_modules' ||
            lower == 'windowsapps' ||
            lower == 'common files' ||
            lower == 'system volume information') {
          continue;
        }
        await _probe(out, entity, depth - 1);
      }
    } catch (_) {}
  }

  // ---------- helpers ----------

  static void _addExecutable(Set<String> out, String path) {
    final normalized = p.normalize(path);
    if (!normalized.toLowerCase().endsWith(_javaExe())) return;
    out.add(normalized);
  }

  static String _javaExe() => Platform.isWindows ? 'java.exe' : 'java';

  static Future<String?> _readVersion(String executable) async {
    try {
      final result = await Process.run(executable, ['-version'])
          .timeout(const Duration(seconds: 8));
      final output = '${result.stdout}${result.stderr}';
      final match = RegExp(r'version "([^"]+)"').firstMatch(output);
      return match?.group(1);
    } catch (_) {
      return null;
    }
  }
}
