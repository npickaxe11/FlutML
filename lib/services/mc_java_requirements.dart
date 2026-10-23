import 'java_detector.dart';

/// Maps Minecraft versions to the Java major version they require and
/// picks the best installed runtime for launching.
class McJavaRequirements {
  McJavaRequirements._();

  /// Extracts the vanilla version id from loader-flavoured ids such as
  /// `fabric-loader-0.16.14-1.21.4`, `1.20.1-forge-47.2.0` or
  /// `1.12.2-OptiFine_HD_U_G5`.
  static String? extractMinecraftVersion(String versionId) {
    var s = versionId.trim();
    if (s.startsWith('fabric-loader-')) {
      final parts = s.split('-');
      if (parts.length >= 4) s = parts.last;
    } else if (s.contains('-forge-') || s.contains('-neoforge-')) {
      s = s.split(RegExp(r'-neo?forge-')).first;
    } else if (s.contains('-OptiFine')) {
      s = s.split('-OptiFine').first;
    }
    final match = RegExp(r'(\d+)\.(\d+)(?:\.(\d+))?').firstMatch(s);
    if (match == null) return null;
    return '${match.group(1)}.${match.group(2)}.${match.group(3) ?? '0'}';
  }

  static bool _looksLikeSnapshot(String id) =>
      RegExp(r'^\d{2}w\d{2}').hasMatch(id.trim());

  /// Required Java major for [versionId].
  ///
  /// Prefers the `javaVersion.majorVersion` field present in modern
  /// version JSONs; falls back to well-known per-release requirements:
  /// - 1.20.5+ -> Java 21
  /// - 1.18+   -> Java 17
  /// - 1.17.x  -> Java 16
  /// - older   -> Java 8
  static int requiredMajor(String versionId, {int? jsonMajor}) {
    if (jsonMajor != null && jsonMajor > 0) return jsonMajor;

    final mc = extractMinecraftVersion(versionId);
    if (mc == null) {
      return _looksLikeSnapshot(versionId) ? 21 : 8;
    }
    final parts = mc.split('.').map(int.parse).toList();
    final major = parts[0];
    final minor = parts[1];
    final patch = parts.length > 2 ? parts[2] : 0;

    int compareTo(int reqMinor, int reqPatch) {
      if (major != 1) return major > 1 ? 1 : -1;
      if (minor != reqMinor) return minor.compareTo(reqMinor);
      return patch.compareTo(reqPatch);
    }

    if (compareTo(20, 5) >= 0) return 21;
    if (compareTo(18, 0) >= 0) return 17;
    if (compareTo(17, 0) >= 0) return 16;
    return 8;
  }

  /// Chooses the best installed runtime for [required]:
  /// 1. an exact major match,
  /// 2. slightly newer (older games tolerate a few majors up),
  /// 3. otherwise the lowest still-newer installation,
  /// 4. `null` when nothing new enough exists.
  static JavaInstall? pickBest(List<JavaInstall> installs, int required) {
    final candidates =
        installs.where((j) => j.major >= required).toList()
          ..sort((a, b) => a.major.compareTo(b.major));

    // Exact match wins (e.g. Java 8 for 1.8.9).
    for (final j in candidates) {
      if (j.major == required) return j;
    }
    // Old games only tolerate a small step up; prefer staying close.
    final closeLimit = required <= 8 ? 11 : (required <= 17 ? 21 : 30);
    for (final j in candidates) {
      if (j.major > required && j.major <= closeLimit) return j;
    }
    // Last resort: newest available that is at least new enough.
    return candidates.isEmpty ? null : candidates.last;
  }
}
