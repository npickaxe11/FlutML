enum ResourceType {
  mod('mod', '模组'),
  modpack('modpack', '整合包'),
  resourcepack('resourcepack', '资源包'),
  shader('shader', '光影包'),
  datapack('datapack', '数据包');

  const ResourceType(this.slug, this.label);

  final String slug;
  final String label;

  bool get supportsLoader =>
      this == ResourceType.mod || this == ResourceType.modpack;
}

enum ResourceSort {
  relevance('relevance', '相关度'),
  downloads('downloads', '下载量'),
  follows('follows', '关注量'),
  newest('newest', '最新发布'),
  updated('updated', '最近更新');

  const ResourceSort(this.value, this.label);

  final String value;
  final String label;
}

const resourceLoaderLabels = <String, String>{
  'forge': 'Forge',
  'fabric': 'Fabric',
  'neoforge': 'NeoForge',
  'quilt': 'Quilt',
};

String loaderLabel(String loader) {
  if (loader.isEmpty) return '全部';
  return resourceLoaderLabels[loader] ?? loader;
}

class ModrinthSearchResult {
  const ModrinthSearchResult({
    required this.hits,
    required this.totalHits,
    required this.offset,
    required this.limit,
  });

  final List<ModrinthSearchHit> hits;
  final int totalHits;
  final int offset;
  final int limit;

  factory ModrinthSearchResult.fromJson(Map<String, dynamic> json) {
    return ModrinthSearchResult(
      hits: (json['hits'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(ModrinthSearchHit.fromJson)
          .toList(),
      totalHits: (json['total_hits'] as num?)?.toInt() ?? 0,
      offset: (json['offset'] as num?)?.toInt() ?? 0,
      limit: (json['limit'] as num?)?.toInt() ?? 0,
    );
  }
}

class ModrinthSearchHit {
  const ModrinthSearchHit({
    required this.id,
    required this.slug,
    required this.title,
    required this.description,
    required this.projectType,
    required this.iconUrl,
    required this.downloads,
    required this.follows,
    required this.updated,
    required this.categories,
    required this.gameVersions,
  });

  final String id;
  final String slug;
  final String title;
  final String description;
  final String projectType;
  final String? iconUrl;
  final int downloads;
  final int follows;
  final DateTime? updated;
  final List<String> categories;
  final List<String> gameVersions;

  List<String> get loaders =>
      categories.where(resourceLoaderLabels.containsKey).toSet().toList()
        ..sort();

  String get latestGameVersion =>
      gameVersions.isEmpty ? '' : gameVersions.first;

  factory ModrinthSearchHit.fromJson(Map<String, dynamic> json) {
    return ModrinthSearchHit(
      id: json['project_id'] as String? ?? '',
      slug: json['slug'] as String? ?? '',
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      projectType: json['project_type'] as String? ?? 'mod',
      iconUrl: json['icon_url'] as String?,
      downloads: (json['downloads'] as num?)?.toInt() ?? 0,
      follows: (json['follows'] as num?)?.toInt() ?? 0,
      updated: DateTime.tryParse(json['date_modified'] as String? ?? ''),
      categories: (json['categories'] as List<dynamic>? ?? [])
          .whereType<String>()
          .toList(),
      gameVersions: (json['versions'] as List<dynamic>? ?? [])
          .whereType<String>()
          .toList(),
    );
  }
}

class ModrinthProject {
  const ModrinthProject({
    required this.id,
    required this.slug,
    required this.title,
    required this.description,
    required this.body,
    required this.iconUrl,
    required this.downloads,
    required this.followers,
    required this.updated,
    required this.loaders,
    required this.gameVersions,
    required this.projectType,
  });

  final String id;
  final String slug;
  final String title;
  final String description;
  final String body;
  final String? iconUrl;
  final int downloads;
  final int followers;
  final DateTime? updated;
  final List<String> loaders;
  final List<String> gameVersions;
  final String projectType;

  factory ModrinthProject.fromJson(Map<String, dynamic> json) {
    return ModrinthProject(
      id: json['id'] as String? ?? '',
      slug: json['slug'] as String? ?? '',
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      body: json['body'] as String? ?? '',
      iconUrl: json['icon_url'] as String?,
      downloads: (json['downloads'] as num?)?.toInt() ?? 0,
      followers: (json['followers'] as num?)?.toInt() ?? 0,
      updated: DateTime.tryParse(json['updated'] as String? ?? ''),
      loaders: (json['loaders'] as List<dynamic>? ?? [])
          .whereType<String>()
          .toList(),
      gameVersions: (json['game_versions'] as List<dynamic>? ?? [])
          .whereType<String>()
          .toList(),
      projectType: json['project_type'] as String? ?? 'mod',
    );
  }
}

class ModrinthVersion {
  const ModrinthVersion({
    required this.id,
    required this.projectId,
    required this.name,
    required this.versionNumber,
    required this.gameVersions,
    required this.loaders,
    required this.downloads,
    required this.versionType,
    required this.published,
    required this.files,
  });

  final String id;
  final String projectId;
  final String name;
  final String versionNumber;
  final List<String> gameVersions;
  final List<String> loaders;
  final int downloads;
  final String versionType;
  final DateTime? published;
  final List<ModrinthFile> files;

  ModrinthFile? get primaryFile {
    if (files.isEmpty) return null;
    return files.firstWhere((file) => file.primary, orElse: () => files.first);
  }

  factory ModrinthVersion.fromJson(Map<String, dynamic> json) {
    return ModrinthVersion(
      id: json['id'] as String? ?? '',
      projectId: json['project_id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      versionNumber: json['version_number'] as String? ?? '',
      gameVersions: (json['game_versions'] as List<dynamic>? ?? [])
          .whereType<String>()
          .toList(),
      loaders: (json['loaders'] as List<dynamic>? ?? [])
          .whereType<String>()
          .toList(),
      downloads: (json['downloads'] as num?)?.toInt() ?? 0,
      versionType: json['version_type'] as String? ?? 'release',
      published: DateTime.tryParse(json['date_published'] as String? ?? ''),
      files: (json['files'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(ModrinthFile.fromJson)
          .toList(),
    );
  }
}

class ModrinthFile {
  const ModrinthFile({
    required this.url,
    required this.filename,
    required this.primary,
    required this.size,
    required this.hashes,
  });

  final String url;
  final String filename;
  final bool primary;
  final int size;
  final Map<String, String> hashes;

  String? get sha1 => hashes['sha1'];

  factory ModrinthFile.fromJson(Map<String, dynamic> json) {
    return ModrinthFile(
      url: json['url'] as String? ?? '',
      filename: json['filename'] as String? ?? 'download',
      primary: json['primary'] as bool? ?? false,
      size: (json['size'] as num?)?.toInt() ?? 0,
      hashes: (json['hashes'] as Map<dynamic, dynamic>? ?? {}).map(
        (key, value) => MapEntry(key.toString(), value.toString()),
      ),
    );
  }
}
