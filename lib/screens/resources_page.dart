import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/modrinth_models.dart';
import '../providers/resource_provider.dart';

enum _ResourceView { search, detail, files }

class ResourcesPage extends StatefulWidget {
  const ResourcesPage({super.key});

  @override
  State<ResourcesPage> createState() => _ResourcesPageState();
}

class _ResourcesPageState extends State<ResourcesPage> {
  final _searchController = TextEditingController();
  final _gameVersionController = TextEditingController();

  Timer? _queryDebounce;
  Timer? _versionDebounce;

  _ResourceView _view = _ResourceView.search;
  ModrinthVersion? _selectedVersion;
  bool _bootstrapped = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  @override
  void dispose() {
    _queryDebounce?.cancel();
    _versionDebounce?.cancel();
    _searchController.dispose();
    _gameVersionController.dispose();
    super.dispose();
  }

  void _bootstrap() {
    if (_bootstrapped || !mounted) return;
    _bootstrapped = true;
    final provider = context.read<ResourceProvider>();
    _searchController.text = provider.query;
    _gameVersionController.text = provider.gameVersion;

    if (provider.hits.isEmpty && !provider.loading && provider.error == null) {
      provider.search();
    }
  }

  void _onQueryChanged(String value) {
    _queryDebounce?.cancel();
    _queryDebounce = Timer(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      final provider = context.read<ResourceProvider>();
      provider.setQuery(value);
      provider.search();
    });
  }

  void _onVersionChanged(String value) {
    _versionDebounce?.cancel();
    _versionDebounce = Timer(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      context.read<ResourceProvider>().setGameVersion(value.trim());
    });
  }

  Future<void> _openProject(ModrinthSearchHit hit) async {
    final provider = context.read<ResourceProvider>();
    setState(() {
      _view = _ResourceView.detail;
      _selectedVersion = null;
    });
    await provider.openProject(hit);
  }

  void _backToSearch() {
    context.read<ResourceProvider>().closeProject();
    setState(() {
      _view = _ResourceView.search;
      _selectedVersion = null;
    });
  }

  void _backToDetail() {
    setState(() {
      _view = _ResourceView.detail;
      _selectedVersion = null;
    });
  }

  void _selectVersion(ModrinthVersion version) {
    setState(() {
      _selectedVersion = version;
      _view = _ResourceView.files;
    });
  }

  Future<void> _saveFile(ModrinthFile file) async {
    final provider = context.read<ResourceProvider>();
    final project = provider.selectedProject;
    final version = _selectedVersion;
    if (project == null || version == null) return;

    final directory = await provider.suggestedDirectory(
      provider.type,
      provider.gameVersion,
    );
    if (!mounted) return;

    final path = await FilePicker.platform.saveFile(
      dialogTitle: '保存到...',
      fileName: file.filename,
      initialDirectory: directory,
      lockParentWindow: true,
    );
    if (path == null || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(SnackBar(content: Text('开始下载 ${file.filename}')));

    final error = await provider.downloadFile(
      project: project,
      version: version,
      file: file,
      destination: path,
    );
    if (!mounted) return;

    if (error != null) {
      messenger.showSnackBar(SnackBar(content: Text('下载失败：$error')));
    } else {
      messenger.showSnackBar(SnackBar(content: Text('已保存到 $path')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final child = switch (_view) {
      _ResourceView.search => KeyedSubtree(
        key: const ValueKey('resource-search'),
        child: _buildSearch(context),
      ),
      _ResourceView.detail => KeyedSubtree(
        key: const ValueKey('resource-detail'),
        child: _buildDetail(context),
      ),
      _ResourceView.files => KeyedSubtree(
        key: const ValueKey('resource-files'),
        child: _buildFiles(context),
      ),
    };

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 280),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      layoutBuilder: (current, previous) =>
          Stack(fit: StackFit.expand, children: [...previous, ?current]),
      transitionBuilder: (child, animation) {
        final position = Tween<Offset>(
          begin: const Offset(0.025, 0),
          end: Offset.zero,
        ).animate(animation);
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(position: position, child: child),
        );
      },
      child: child,
    );
  }

  Widget _buildSearch(BuildContext context) {
    final provider = context.watch<ResourceProvider>();
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 24, 32, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('获取资源', style: text.headlineMedium),
                    const SizedBox(height: 8),
                    Text(
                      '下载源于 Modrinth',
                      style: text.bodyLarge?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton.filledTonal(
                onPressed: provider.loading || provider.loadingDetails
                    ? null
                    : () => provider.refresh(),
                icon: provider.loading || provider.loadingDetails
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.cloud_sync_outlined),
                tooltip: '刷新一下...',
              ),
            ],
          ),
          const SizedBox(height: 16),
          SearchBar(
            controller: _searchController,
            hintText: '搜索...',
            leading: const Icon(Icons.search),
            onChanged: _onQueryChanged,
            onSubmitted: (value) {
              _queryDebounce?.cancel();
              provider.setQuery(value);
              provider.search();
            },
            elevation: const WidgetStatePropertyAll(0),
            backgroundColor: WidgetStatePropertyAll(
              scheme.surfaceContainerHigh,
            ),
          ),
          const SizedBox(height: 12),
          _SearchSettingsCard(
            gameVersionController: _gameVersionController,
            onVersionChanged: _onVersionChanged,
          ),
          const SizedBox(height: 12),
          Expanded(child: _buildResults(context, provider)),
        ],
      ),
    );
  }

  Widget _buildResults(BuildContext context, ResourceProvider provider) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    if (provider.loading && provider.hits.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (provider.error != null && provider.hits.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off, size: 48, color: scheme.error),
            const SizedBox(height: 12),
            Text('获取失败', style: text.titleMedium),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Text(
                provider.error!,
                textAlign: TextAlign.center,
                style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.tonal(
              onPressed: () => provider.search(),
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }

    if (provider.hits.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off, size: 56, color: scheme.outline),
            const SizedBox(height: 16),
            Text('没有找到资源 (￣▽￣)"', style: text.titleMedium),
            const SizedBox(height: 8),
            Text(
              '试着换个关键词，或者调整搜索设置',
              style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      );
    }

    return Card(
      clipBehavior: Clip.antiAlias,
      child: ListView.separated(
        padding: EdgeInsets.zero,
        itemCount: provider.hits.length + (provider.hasMore ? 1 : 0),
        separatorBuilder: (context, index) => const Divider(height: 1),
        itemBuilder: (context, index) {
          if (index >= provider.hits.length) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: provider.loadingMore
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : FilledButton.tonal(
                        onPressed: provider.loadMore,
                        child: const Text('加载更多'),
                      ),
              ),
            );
          }

          final hit = provider.hits[index];
          return ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 8,
            ),
            leading: _ResourceIcon(iconUrl: hit.iconUrl, size: 56),
            title: Text(
              hit.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Wrap(
                spacing: 14,
                runSpacing: 4,
                children: [
                  _Meta(
                    label: '加载器',
                    value: hit.loaders.isEmpty
                        ? '—'
                        : hit.loaders.map(loaderLabel).join('/'),
                  ),
                  _Meta(
                    label: '版本',
                    value: hit.latestGameVersion.isEmpty
                        ? '—'
                        : hit.latestGameVersion,
                  ),
                  _Meta(label: '下载量', value: _formatCount(hit.downloads)),
                  _Meta(label: '最后更新', value: _formatDate(hit.updated)),
                ],
              ),
            ),
            trailing: Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
            onTap: () => _openProject(hit),
          );
        },
      ),
    );
  }

  Widget _buildDetail(BuildContext context) {
    final provider = context.watch<ResourceProvider>();
    final hit = provider.selectedHit;
    final project = provider.selectedProject;
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 24, 32, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                onPressed: _backToSearch,
                tooltip: '返回',
                icon: const Icon(Icons.arrow_back),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      project?.title ?? hit?.title ?? '资源详情',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '资源详情 · Modrinth',
                      style: text.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(child: _buildDetailBody(context, provider, project)),
        ],
      ),
    );
  }

  Widget _buildDetailBody(
    BuildContext context,
    ResourceProvider provider,
    ModrinthProject? project,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    if (provider.loadingDetails && project == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (project == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off, size: 48, color: scheme.error),
            const SizedBox(height: 12),
            Text('获取资源信息失败', style: text.titleMedium),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Text(
                provider.detailsError ?? '未知错误',
                textAlign: TextAlign.center,
                style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.tonal(
              onPressed: provider.retryDetails,
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ResourceIcon(iconUrl: project.iconUrl, size: 76),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        project.title,
                        style: text.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        project.description,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: text.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 14,
                        runSpacing: 6,
                        children: [
                          _Meta(
                            label: '加载器',
                            value: project.loaders.isEmpty
                                ? '—'
                                : project.loaders.map(loaderLabel).join('/'),
                          ),
                          _Meta(
                            label: '下载量',
                            value: _formatCount(project.downloads),
                          ),
                          _Meta(
                            label: '最后更新',
                            value: _formatDate(project.updated),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Text(
              '兼容版本',
              style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(width: 8),
            Text(
              provider.gameVersion.isEmpty
                  ? '全部游戏版本'
                  : '${provider.gameVersion} · ${loaderLabel(provider.loader)}',
              style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const Spacer(),
            Text(
              '${provider.versions.length} 个',
              style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(
          child: provider.versions.isEmpty
              ? Center(
                  child: Text(
                    '没有找到兼容版本 (￣▽￣)"',
                    style: text.bodyLarge?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                )
              : Card(
                  clipBehavior: Clip.antiAlias,
                  child: ListView.separated(
                    padding: EdgeInsets.zero,
                    itemCount: provider.versions.length,
                    separatorBuilder: (context, index) =>
                        const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final version = provider.versions[index];
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 6,
                        ),
                        leading: CircleAvatar(
                          backgroundColor: scheme.primaryContainer,
                          foregroundColor: scheme.onPrimaryContainer,
                          child: const Icon(Icons.inventory_2_outlined),
                        ),
                        title: Text(
                          version.versionNumber,
                          style: text.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        subtitle: Text(
                          [
                            version.gameVersions.join(', '),
                            version.loaders.isEmpty
                                ? null
                                : version.loaders.map(loaderLabel).join('/'),
                            _formatDate(version.published),
                          ].whereType<String>().join(' · '),
                        ),
                        trailing: FilledButton.tonal(
                          onPressed: () => _selectVersion(version),
                          child: const Text('选择'),
                        ),
                        onTap: () => _selectVersion(version),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildFiles(BuildContext context) {
    final provider = context.watch<ResourceProvider>();
    final project = provider.selectedProject;
    final version = _selectedVersion;
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 24, 32, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                onPressed: _backToDetail,
                tooltip: '返回',
                icon: const Icon(Icons.arrow_back),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      version?.versionNumber ?? '选择文件',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${project?.title ?? ''} · 选择要下载的文件',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: version == null || version.files.isEmpty
                ? Center(
                    child: Text(
                      '这个版本没有可下载的文件',
                      style: text.bodyLarge?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  )
                : Card(
                    clipBehavior: Clip.antiAlias,
                    child: ListView.separated(
                      padding: EdgeInsets.zero,
                      itemCount: version.files.length,
                      separatorBuilder: (context, index) =>
                          const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final file = version.files[index];
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          leading: CircleAvatar(
                            backgroundColor: scheme.surfaceContainerHighest,
                            foregroundColor: scheme.onSurfaceVariant,
                            child: const Icon(Icons.insert_drive_file_outlined),
                          ),
                          title: Text(
                            file.filename,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: text.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          subtitle: Text(
                            [
                              _formatBytes(file.size),
                              if (file.primary) '主文件',
                            ].join(' · '),
                          ),
                          trailing: FilledButton.tonal(
                            onPressed: () => _saveFile(file),
                            child: const Text('保存并下载'),
                          ),
                          onTap: () => _saveFile(file),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  static String _formatDate(DateTime? date) {
    if (date == null) return '—';
    final local = date.toLocal();
    return '${local.year}-'
        '${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')}';
  }

  static String _formatCount(int value) {
    if (value >= 100000000) {
      return '${(value / 100000000).toStringAsFixed(1)}亿';
    }
    if (value >= 10000) {
      return '${(value / 10000).toStringAsFixed(1)}万';
    }
    return '$value';
  }

  static String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
    }
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
    }
    if (bytes >= 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '$bytes B';
  }
}

class _SearchSettingsCard extends StatelessWidget {
  const _SearchSettingsCard({
    required this.gameVersionController,
    required this.onVersionChanged,
  });

  final TextEditingController gameVersionController;
  final ValueChanged<String> onVersionChanged;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ResourceProvider>();
    final text = Theme.of(context).textTheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('搜索设置', style: text.titleMedium),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: DropdownButtonFormField<ResourceType>(
                    key: ValueKey('resource-type-${provider.type.name}'),
                    initialValue: provider.type,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: '类型'),
                    items: [
                      for (final type in ResourceType.values)
                        DropdownMenuItem(value: type, child: Text(type.label)),
                    ],
                    onChanged: provider.loading
                        ? null
                        : (value) {
                            if (value != null) provider.setType(value);
                          },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: gameVersionController,
                    decoration: const InputDecoration(
                      labelText: '版本',
                      hintText: '例如 1.20.1',
                    ),
                    onChanged: onVersionChanged,
                    onSubmitted: onVersionChanged,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    key: ValueKey('resource-loader-${provider.loader}'),
                    initialValue: provider.loader,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: '加载器'),
                    items: const [
                      DropdownMenuItem(value: '', child: Text('全部')),
                      DropdownMenuItem(value: 'forge', child: Text('Forge')),
                      DropdownMenuItem(value: 'fabric', child: Text('Fabric')),
                    ],
                    onChanged: provider.loading
                        ? null
                        : (value) {
                            if (value != null) provider.setLoader(value);
                          },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<ResourceSort>(
                    key: ValueKey('resource-sort-${provider.sort.name}'),
                    initialValue: provider.sort,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: '排序方式'),
                    items: [
                      for (final sort in ResourceSort.values)
                        DropdownMenuItem(value: sort, child: Text(sort.label)),
                    ],
                    onChanged: provider.loading
                        ? null
                        : (value) {
                            if (value != null) provider.setSort(value);
                          },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ResourceIcon extends StatelessWidget {
  const _ResourceIcon({required this.iconUrl, required this.size});

  final String? iconUrl;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fallback = ColoredBox(
      color: scheme.surfaceContainerHighest,
      child: Icon(
        Icons.extension_outlined,
        size: size * 0.45,
        color: scheme.onSurfaceVariant,
      ),
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox.square(
        dimension: size,
        child: iconUrl == null || iconUrl!.isEmpty
            ? fallback
            : Image.network(
                iconUrl!,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => fallback,
              ),
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '$label · ',
            style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
          TextSpan(
            text: value,
            style: text.bodySmall?.copyWith(
              color: scheme.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
