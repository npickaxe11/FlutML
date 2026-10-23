import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/account.dart';
import '../models/download_source.dart';
import '../models/launcher_settings.dart';
import 'authlib_service.dart';
import 'download_service.dart';
import 'java_detector.dart';
import 'mc_java_requirements.dart';
import 'microsoft_auth_service.dart';
import 'path_service.dart';
import 'version_service.dart';

class LaunchService {
  LaunchService({
    VersionService? versionService,
    AuthlibService? authlibService,
    DownloadService? downloadService,
  })  : _versions = versionService ?? VersionService(),
        _authlib = authlibService ?? AuthlibService(),
        _downloads = downloadService ?? DownloadService();

  final VersionService _versions;
  final AuthlibService _authlib;
  final DownloadService _downloads;
  Process? _running;

  bool get isRunning => _running != null;

  Future<Process> launch({
    required Account account,
    required String versionId,
    required LauncherSettings settings,
    void Function(int exitCode, String logTail)? onExit,
  }) async {
    if (_running != null) {
      throw StateError('A game process is already running');
    }

    final resolved =
        await _versions.resolveEffectiveVersion(versionId);

    // Java resolution order:
    //   1. explicit per-version override (user's manual choice),
    //   2. best auto match for this version's required major,
    //   3. the global default from settings.
    final override = settings.javaOverrideFor(versionId).trim();
    String java;
    if (override.isNotEmpty) {
      java = override;
    } else {
      final installs = await JavaDetector.detect();
      final best = McJavaRequirements.pickBest(
        installs,
        resolved.requiredJavaMajor,
      );
      if (best != null) {
        java = best.path;
      } else if (settings.javaPath.trim().isNotEmpty) {
        java = settings.javaPath.trim();
      } else {
        throw StateError(
          'Minecraft ${resolved.json['id'] ?? versionId} requires '
          'Java ${resolved.requiredJavaMajor} but no compatible '
          'installation was found. Install one or pick a Java manually '
          'in the version dialog.',
        );
      }
    }
    final javaFile = File(java);
    if (!await javaFile.exists()) {
      throw StateError('Java executable not found: $java');
    }
    final versionJson = resolved.json;
    final baseGameDir = settings.gameDirectory.isEmpty
        ? await PathService.instance.gameDirectory()
        : settings.gameDirectory;
    // Version isolation: point game_directory at the per-version folder so
    // Fabric/Forge etc. look for mods/, resourcepacks/ under
    // versions/<id>/ instead of the flat .minecraft/ root.
    final gameDir = p.join(baseGameDir, 'versions', versionId);
    await Directory(gameDir).create(recursive: true);

    final nativesDir = await PathService.instance.nativesDir(versionId);
    await Directory(nativesDir).create(recursive: true);

    // Ensure natives extracted (in case of partial install)
    await _ensureNatives(versionJson, versionId);

    // Self-heal partially installed versions: download any missing
    // libraries and extract missing natives before launching.
    try {
      await _downloads.downloadLibraries(
        libraries: versionJson['libraries'] ?? const [],
        source: settings.downloadSource,
        extractNativesFor: versionId,
      );
    } catch (_) {
      // Network hiccups must not block an otherwise complete install.
    }

    final classpath = await _buildClasspath(
      versionJson,
      resolved.clientJarVersionId,
    );
    final mainClass = versionJson['mainClass'] as String;

    final assetsRoot = await PathService.instance.assetsDir();
    final assetsIndexName =
        (versionJson['assetIndex'] as Map<String, dynamic>?)?['id']
                as String? ??
            (versionJson['assets'] as String? ?? 'legacy');
    final accessToken =
        account.accessToken.isEmpty ? '0' : account.accessToken;
    final uuidNoDashes = account.uuid.replaceAll('-', '');

    final vars = <String, String>{
      'auth_player_name': account.username,
      'version_name': versionJson['id'] as String? ?? versionId,
      'game_directory': gameDir,
      'assets_root': assetsRoot,
      'assets_index_name': assetsIndexName,
      'auth_uuid': uuidNoDashes,
      'auth_access_token': accessToken,
      'auth_session': 'token:$accessToken:$uuidNoDashes',
      'game_assets': p.join(assetsRoot, 'virtual', assetsIndexName),
      'clientid': account.type == AccountType.msa
          ? MicrosoftAuthService.clientId
          : '0',
      'auth_xuid': '0',
      'user_type': account.type == AccountType.msa ? 'msa' : 'legacy',
      'version_type': versionJson['type'] as String? ?? 'release',
      'natives_directory': nativesDir,
      'launcher_name': 'minecraft_launcher',
      'launcher_version': '2.0.0',
      'classpath': classpath,
      'resolution_width': '${settings.windowWidth}',
      'resolution_height': '${settings.windowHeight}',
      'library_directory': await PathService.instance.librariesDir(),
      'classpath_separator': Platform.isWindows ? ';' : ':',
      'user_properties': '{}',
    };

    // Old versions read resources from flat layouts (virtual dir or the
    // game's resources folder).
    try {
      await _downloads.ensureLegacyAssetLayouts(assetsIndexName);
    } catch (_) {}

    var jvmArgs = <String>[
      '-Xmx${settings.maxMemoryMb}M',
      '-Xms${settings.minMemoryMb}M',
      '-Djava.library.path=$nativesDir',
      '-Dminecraft.launcher.brand=minecraft_launcher',
      '-Dminecraft.launcher.version=2.0.0',
    ];

    // Third-party skin stations are injected via the authlib-injector agent.
    if (account.type == AccountType.authlib &&
        account.authServerUrl.isNotEmpty) {
      final agentJar = await _authlib.ensureAgentJar(
        preferChinaMirror: settings.downloadSource == DownloadSource.china,
      );
      jvmArgs.add('-javaagent:$agentJar=${account.authServerUrl}');
      jvmArgs.add('-Dauthlibinjector.side=client');
    }

    if (settings.jvmArgs.trim().isNotEmpty) {
      jvmArgs.addAll(_splitArgs(settings.jvmArgs));
    }

    // Quick Play 机制在 1.21+ 中不再允许同时指定两个不同的目标，
    // 如果检测到同时存在 --quickPlaySingleplayer 与 --quickPlayMultiplayer
    // 则保留第一个、自动剔除冲突项，防止游戏参数解析阶段崩溃。
    jvmArgs = _dedupeQuickPlayArgs(jvmArgs);

    final argumentsBlock = versionJson['arguments'] as Map<String, dynamic>?;
    if (argumentsBlock != null) {
      jvmArgs.addAll(
        _resolveArgs(
          argumentsBlock['jvm'] as List<dynamic>? ?? [],
          vars,
          settings,
        ),
      );
    } else {
      jvmArgs.add('-cp');
      jvmArgs.add(classpath);
    }

    final gameArgs = <String>[];
    if (argumentsBlock != null) {
      gameArgs.addAll(
        _resolveArgs(
          argumentsBlock['game'] as List<dynamic>? ?? [],
          vars,
          settings,
        ),
      );
    } else {
      final legacy = versionJson['minecraftArguments'] as String? ?? '';
      gameArgs.addAll(
        _splitArgs(_replaceVars(legacy, vars)),
      );
    }

    // Quick Play 参数在 1.21+ 中不再允许同时指定 Singleplayer 与 Multiplayer，
    // 且可能导致参数冲突导致游戏直接退出，此处统一过滤掉所有 QuickPlay 相关参数，
    // 包括 Singleplayer、Multiplayer 与 Realms，避免游戏启动报错。若需要任选其一，
    // 请在启动器设置中仅勾选其一。
    gameArgs.removeWhere(
      (arg) => arg.toLowerCase().contains('quickplay'),
    );

    if (settings.fullscreen) {
      if (!gameArgs.contains('--fullscreen')) {
        gameArgs.add('--fullscreen');
      }
    }

    final fullArgs = [...jvmArgs, mainClass, ...gameArgs];

    // Normal mode: detachedWithStdio processes do not support exitCode on
    // Windows ("Bad state: Process is detached") and undrained stdio pipes
    // deadlock the JVM once their buffer fills.
    final process = await Process.start(
      java,
      fullArgs,
      workingDirectory: gameDir,
      environment: {
        ...Platform.environment,
        'APPDATA': Platform.environment['APPDATA'] ?? '',
      },
    );
    _running = process;

    final logPath =
        await PathService.instance.launcherOutputLogPath(versionId);
    unawaited(_captureOutput(process, logPath));
    unawaited(
      process.exitCode.then((code) async {
        if (identical(_running, process)) {
          _running = null;
        }
        if (onExit == null) return;
        onExit(code, _readLogTailSync(logPath));
      }),
    );

    return process;
  }

  /// Reads the last lines of the game output log for crash reporting.
  String _readLogTailSync(String logPath, {int maxLines = 40}) {
    try {
      final file = File(logPath);
      if (!file.existsSync()) return '';
      final lines = file.readAsLinesSync();
      if (lines.length <= maxLines) return lines.join('\n');
      return lines.sublist(lines.length - maxLines).join('\n');
    } catch (_) {
      return '';
    }
  }

  Future<void> _captureOutput(Process process, String logPath) async {
    IOSink? sink;
    try {
      final logFile = File(logPath);
      await logFile.parent.create(recursive: true);
      sink = logFile.openWrite(mode: FileMode.writeOnly);
      final decoder = const Utf8Decoder(allowMalformed: true);
      process.stdout
          .cast<List<int>>()
          .transform(decoder)
          .listen(sink.write, cancelOnError: false);
      process.stderr
          .cast<List<int>>()
          .transform(decoder)
          .listen(sink.write, cancelOnError: false);
    } catch (_) {
      // Logging must never break the launch.
    }
  }

  Future<void> stop() async {
    final proc = _running;
    if (proc == null) return;
    try {
      proc.kill();
    } catch (_) {}
  }

  Future<String> _buildClasspath(
    Map<String, dynamic> versionJson,
    String clientJarVersionId,
  ) async {
    final libsDir = await PathService.instance.librariesDir();
    final jars = <String>[];

    final libraries =
        (versionJson['libraries'] as List<dynamic>? ?? [])
            .cast<Map<String, dynamic>>();

    for (final lib in libraries) {
      if (!_libraryAllowed(lib)) continue;
      // Skip pure natives jars from classpath when they only have natives
      final downloads = lib['downloads'] as Map<String, dynamic>?;
      final artifact = downloads?['artifact'] as Map<String, dynamic>?;
      if (artifact != null) {
        final path = artifact['path'] as String;
        jars.add(p.join(libsDir, path));
      } else if (lib['natives'] == null) {
        final name = lib['name'] as String?;
        if (name != null) {
          jars.add(p.join(libsDir, _mavenPath(name)));
        }
      }
    }

    jars.add(await PathService.instance.versionJarPath(clientJarVersionId));
    final sep = Platform.isWindows ? ';' : ':';
    return jars.join(sep);
  }

  Future<void> _ensureNatives(
    Map<String, dynamic> versionJson,
    String versionId,
  ) async {
    // Natives should already be extracted during download.
    // Create directory if missing so -Djava.library.path is valid.
    final dir = Directory(await PathService.instance.nativesDir(versionId));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
  }

  List<String> _resolveArgs(
    List<dynamic> rules,
    Map<String, String> vars,
    LauncherSettings settings,
  ) {
    final out = <String>[];
    for (final item in rules) {
      if (item is String) {
        out.add(_replaceVars(item, vars));
      } else if (item is Map<String, dynamic>) {
        if (!_argAllowed(item, settings)) continue;
        final value = item['value'];
        if (value is String) {
          out.add(_replaceVars(value, vars));
        } else if (value is List) {
          for (final v in value) {
            out.add(_replaceVars(v as String, vars));
          }
        }
      }
    }
    return out;
  }

  bool _argAllowed(Map<String, dynamic> item, LauncherSettings settings) {
    final rules = item['rules'] as List<dynamic>?;
    if (rules == null || rules.isEmpty) return true;

    var allowed = false;
    for (final rule in rules) {
      final map = rule as Map<String, dynamic>;
      final action = map['action'] as String? ?? 'allow';
      final os = map['os'] as Map<String, dynamic>?;
      final features = map['features'] as Map<String, dynamic>?;

      var match = true;
      if (os != null) {
        final name = os['name'] as String?;
        if (name != null) {
          if (Platform.isWindows && name != 'windows') match = false;
          if (Platform.isLinux && name != 'linux') match = false;
          if (Platform.isMacOS && name != 'osx') match = false;
        }
      }
      if (features != null) {
        if (features.containsKey('is_demo_user') &&
            features['is_demo_user'] == true) {
          match = false;
        }
        if (features.containsKey('has_custom_resolution')) {
          // Always provide resolution
          match = match && features['has_custom_resolution'] == true;
        }
      }
      if (match) allowed = action == 'allow';
    }
    return allowed;
  }

  bool _libraryAllowed(Map<String, dynamic> lib) {
    final rules = lib['rules'] as List<dynamic>?;
    if (rules == null || rules.isEmpty) return true;
    var allowed = false;
    for (final rule in rules) {
      final map = rule as Map<String, dynamic>;
      final action = map['action'] as String? ?? 'allow';
      final os = map['os'] as Map<String, dynamic>?;
      final matchesOs = os == null || _osMatches(os);
      if (matchesOs) allowed = action == 'allow';
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

  String _mavenPath(String name) {
    final parts = name.split(':');
    if (parts.length < 3) return name.replaceAll(':', '/');
    final group = parts[0].replaceAll('.', '/');
    final artifact = parts[1];
    final version = parts[2];
    return '$group/$artifact/$version/$artifact-$version.jar';
  }

  String _replaceVars(String input, Map<String, String> vars) {
    var result = input;
    vars.forEach((key, value) {
      result = result.replaceAll('\${$key}', value);
    });
    return result;
  }

  List<String> _splitArgs(String input) {
    final result = <String>[];
    final regex = RegExp(r'''[^\s"']+|"([^"]*)"|'([^']*)''');
    for (final match in regex.allMatches(input.trim())) {
      final token =
          match.group(1) ?? match.group(2) ?? match.group(0) ?? '';
      if (token.isNotEmpty) result.add(token);
    }
    return result;
  }

  /// 去除 QuickPlay 参数冲突：在 1.21+ 中不允许同时指定 Singleplayer 与 Multiplayer，
  // 保留首个出现的，自动剔除另一个，避免游戏启动报错。
  List<String> _dedupeQuickPlayArgs(List<String> args) {
    final quickPlaySeen = <String>{};
    final result = <String>[];
    for (final arg in args) {
      final lower = arg.toLowerCase();
      if (lower.contains('quickplaysingleplayer') || lower.contains('quickplaymultiplayer')) {
        // 只有第一个 QuickPlay 类型参数被保留，后续的被丢弃
        if (quickPlaySeen.isEmpty) {
          quickPlaySeen.add('used');
          result.add(arg);
        }
        // 若已经保留过，则跳过（不添加到 result）
        continue;
      }
      result.add(arg);
    }
    return result;
  }
}