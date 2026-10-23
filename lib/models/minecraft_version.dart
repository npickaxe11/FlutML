enum VersionType { release, snapshot, oldBeta, oldAlpha }

VersionType versionTypeFromString(String value) {
  switch (value) {
    case 'snapshot':
      return VersionType.snapshot;
    case 'old_beta':
      return VersionType.oldBeta;
    case 'old_alpha':
      return VersionType.oldAlpha;
    default:
      return VersionType.release;
  }
}

String versionTypeLabel(VersionType type) {
  switch (type) {
    case VersionType.release:
      return 'Release';
    case VersionType.snapshot:
      return 'Snapshot';
    case VersionType.oldBeta:
      return 'Old Beta';
    case VersionType.oldAlpha:
      return 'Old Alpha';
  }
}

class ManifestVersion {
  const ManifestVersion({
    required this.id,
    required this.type,
    required this.url,
    required this.releaseTime,
    this.sha1,
  });

  final String id;
  final VersionType type;
  final String url;
  final DateTime releaseTime;
  final String? sha1;

  factory ManifestVersion.fromJson(Map<String, dynamic> json) {
    return ManifestVersion(
      id: json['id'] as String,
      type: versionTypeFromString(json['type'] as String? ?? 'release'),
      url: json['url'] as String,
      releaseTime: DateTime.parse(json['releaseTime'] as String),
      sha1: json['sha1'] as String?,
    );
  }
}

class VersionManifest {
  const VersionManifest({
    required this.latestRelease,
    required this.latestSnapshot,
    required this.versions,
  });

  final String latestRelease;
  final String latestSnapshot;
  final List<ManifestVersion> versions;

  factory VersionManifest.fromJson(Map<String, dynamic> json) {
    final latest = json['latest'] as Map<String, dynamic>? ?? {};
    final list = (json['versions'] as List<dynamic>? ?? [])
        .map((e) => ManifestVersion.fromJson(e as Map<String, dynamic>))
        .toList();
    return VersionManifest(
      latestRelease: latest['release'] as String? ?? '',
      latestSnapshot: latest['snapshot'] as String? ?? '',
      versions: list,
    );
  }
}

class InstalledVersion {
  const InstalledVersion({
    required this.id,
    required this.type,
    required this.directory,
    this.releaseTime,
  });

  final String id;
  final VersionType type;
  final String directory;
  final DateTime? releaseTime;
}
