import 'download_source.dart';

class LauncherSettings {
const LauncherSettings({
    this.javaPath = '',
    this.gameDirectory = '',
    this.maxMemoryMb = 2048,
    this.minMemoryMb = 512,
    this.jvmArgs = '',
    this.windowWidth = 854,
    this.windowHeight = 480,
    this.fullscreen = false,
    this.selectedVersionId = '',
    this.showSnapshots = false,
    this.showOldVersions = false,
    this.downloadSource = DownloadSource.official,
    this.javaOverrides = const {},
    this.useDiscreteGpu = false,
  });

  final String javaPath;
  final String gameDirectory;
  final int maxMemoryMb;
  final int minMemoryMb;
  final String jvmArgs;
  final int windowWidth;
  final int windowHeight;
  final bool fullscreen;
  final String selectedVersionId;
  final bool showSnapshots;
  final bool showOldVersions;
  final DownloadSource downloadSource;

  /// Whether to attempt using a discrete GPU for game launch.
  final bool useDiscreteGpu;

  /// Per-version Java executable overrides (version id -> java path).
  /// Versions absent from the map use the global [javaPath].
  final Map<String, String> javaOverrides;

  String javaOverrideFor(String versionId) => javaOverrides[versionId] ?? '';

  LauncherSettings copyWith({
    String? javaPath,
    String? gameDirectory,
    int? maxMemoryMb,
    int? minMemoryMb,
    String? jvmArgs,
    int? windowWidth,
    int? windowHeight,
    bool? fullscreen,
    String? selectedVersionId,
    bool? showSnapshots,
    bool? showOldVersions,
    DownloadSource? downloadSource,
    Map<String, String>? javaOverrides,
    bool? useDiscreteGpu,
  }) {
    return LauncherSettings(
      javaPath: javaPath ?? this.javaPath,
      gameDirectory: gameDirectory ?? this.gameDirectory,
      maxMemoryMb: maxMemoryMb ?? this.maxMemoryMb,
      minMemoryMb: minMemoryMb ?? this.minMemoryMb,
      jvmArgs: jvmArgs ?? this.jvmArgs,
      windowWidth: windowWidth ?? this.windowWidth,
      windowHeight: windowHeight ?? this.windowHeight,
      fullscreen: fullscreen ?? this.fullscreen,
      selectedVersionId: selectedVersionId ?? this.selectedVersionId,
      showSnapshots: showSnapshots ?? this.showSnapshots,
      showOldVersions: showOldVersions ?? this.showOldVersions,
      downloadSource: downloadSource ?? this.downloadSource,
      javaOverrides: javaOverrides ?? this.javaOverrides,
      useDiscreteGpu: useDiscreteGpu ?? this.useDiscreteGpu,
    );
  }

  Map<String, dynamic> toJson() => {
        'javaPath': javaPath,
        'gameDirectory': gameDirectory,
        'maxMemoryMb': maxMemoryMb,
        'minMemoryMb': minMemoryMb,
        'jvmArgs': jvmArgs,
        'windowWidth': windowWidth,
        'windowHeight': windowHeight,
        'fullscreen': fullscreen,
        'selectedVersionId': selectedVersionId,
        'showSnapshots': showSnapshots,
        'showOldVersions': showOldVersions,
        'downloadSource': downloadSource.name,
        'javaOverrides': javaOverrides,
        'useDiscreteGpu': useDiscreteGpu,
      };

  factory LauncherSettings.fromJson(Map<String, dynamic> json) {
    return LauncherSettings(
      javaPath: json['javaPath'] as String? ?? '',
      gameDirectory: json['gameDirectory'] as String? ?? '',
      maxMemoryMb: json['maxMemoryMb'] as int? ?? 2048,
      minMemoryMb: json['minMemoryMb'] as int? ?? 512,
      jvmArgs: json['jvmArgs'] as String? ?? '',
      windowWidth: json['windowWidth'] as int? ?? 854,
      windowHeight: json['windowHeight'] as int? ?? 480,
      fullscreen: json['fullscreen'] as bool? ?? false,
      selectedVersionId: json['selectedVersionId'] as String? ?? '',
      showSnapshots: json['showSnapshots'] as bool? ?? false,
      showOldVersions: json['showOldVersions'] as bool? ?? false,
      downloadSource:
          DownloadSource.fromName(json['downloadSource'] as String?),
      javaOverrides: (json['javaOverrides'] as Map<dynamic, dynamic>? ?? {})
          .map((k, v) => MapEntry(k as String, v as String)),
      useDiscreteGpu: json['useDiscreteGpu'] as bool? ?? false,
    );
  }
}
