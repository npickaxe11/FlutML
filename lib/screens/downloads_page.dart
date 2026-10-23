import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/minecraft_version.dart';
import '../providers/mod_loader_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/version_provider.dart';
import '../services/path_service.dart';
import '../widgets/error_dialog.dart';

class DownloadsPage extends StatefulWidget {
  const DownloadsPage({super.key});

  @override
  State<DownloadsPage> createState() => _DownloadsPageState();
}

class _DownloadsPageState extends State<DownloadsPage> {
  int? _lastVersionTicket;
  int? _lastModsTicket;

  void _listenErrors() {
    final versions = context.read<VersionProvider>();
    if (_lastVersionTicket == null) {
      _lastVersionTicket = versions.errorTicket;
    } else if (versions.errorTicket != _lastVersionTicket) {
      _lastVersionTicket = versions.errorTicket;
      final message = versions.error;
      if (message != null && message.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          showErrorDialog(context, title: 'Download failed', message: message);
        });
      }
    }

    final mods = context.read<ModLoaderProvider>();
    if (_lastModsTicket == null) {
      _lastModsTicket = mods.errorTicket;
    } else if (mods.errorTicket != _lastModsTicket) {
      _lastModsTicket = mods.errorTicket;
      final message = mods.error;
      if (message != null && message.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          showErrorDialog(
            context,
            title: 'Mod loader install failed',
            message: message,
          );
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    _listenErrors();
    final versions = context.watch<VersionProvider>();
    final mods = context.watch<ModLoaderProvider>();
    final settings = context.watch<SettingsProvider>().settings;
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    final remote = versions.remoteVersions(
      showSnapshots: settings.showSnapshots,
      showOldVersions: settings.showOldVersions,
    );

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
                    Text('下载版本', style: text.headlineMedium),
                    const SizedBox(height: 8),
                    Text(
                      '版本列表源于 ${versions.source.label}',
                      style: text.bodyLarge
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              IconButton.filledTonal(
                onPressed: versions.loadingManifest || versions.downloading
                    ? null
                    : () => versions.refreshManifest(force: true),
                icon: versions.loadingManifest
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
            hintText: '搜索...',
            leading: const Icon(Icons.search),
            onChanged: versions.setSearch,
            elevation: const WidgetStatePropertyAll(0),
            backgroundColor: WidgetStatePropertyAll(scheme.surfaceContainerHigh),
          ),
          const SizedBox(height: 12),
          if (versions.downloading && versions.progress != null) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(versions.progress!.stage, style: text.titleSmall),
                    const SizedBox(height: 4),
                    Text(
                      versions.progress!.currentFile,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 12),
                    LinearProgressIndicator(
                      value: versions.progress!.total > 0
                          ? versions.progress!.fraction
                          : null,
                      borderRadius: BorderRadius.circular(8),
                      minHeight: 8,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${versions.progress!.current} / ${versions.progress!.total}',
                      style: text.labelSmall,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (mods.busy) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        mods.status ?? '工作中...',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: text.bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          Expanded(
            child: versions.loadingManifest && versions.manifest == null
                ? const Center(child: CircularProgressIndicator())
                : remote.isEmpty
                    ? Center(
                        child: Text(
                          '没有找到 (￣▽￣)"',
                          style: text.bodyLarge?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      )
                    : ListView.separated(
                        itemCount: remote.length,
                        separatorBuilder: (context, index) =>
                            const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final v = remote[index];
                          final installed = versions.isInstalled(v.id);
                          final isLatestRelease =
                              versions.manifest?.latestRelease == v.id;
                          return ListTile(
                            leading: Icon(
                              installed
                                  ? Icons.check_circle
                                  : Icons.download_outlined,
                              color: installed
                                  ? scheme.primary
                                  : scheme.onSurfaceVariant,
                            ),
                            title: Row(
                              children: [
                                Text(v.id),
                                if (isLatestRelease) ...[
                                  const SizedBox(width: 8),
                                  Chip(
                                    label: const Text('Latest'),
                                    visualDensity: VisualDensity.compact,
                                    labelStyle: text.labelSmall,
                                    padding: EdgeInsets.zero,
                                  ),
                                ],
                              ],
                            ),
                            subtitle: Text(
                              '${versionTypeLabel(v.type)} · ${_formatDate(v.releaseTime)}',
                            ),
                            trailing: installed
                                ? Text(
                                    '已经安装了',
                                    style: text.labelLarge?.copyWith(
                                      color: scheme.primary,
                                    ),
                                  )
                                : Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      FilledButton.tonal(
                                        onPressed: versions.downloading ||
                                                versions.loadingManifest
                                            ? null
                                            : () => _download(context, v),
                                        child: const Text('下载原版'),
                                      ),
                                      const SizedBox(width: 8),
                                      PopupMenuButton<String>(
                                        tooltip: '安装附带 Mod 加载器的版本',
                                        enabled: !versions.downloading &&
                                            !mods.busy,
                                        onSelected: (kind) =>
                                            _installLoader(context, kind, v),
                                        itemBuilder: (context) => const [
                                          PopupMenuItem(
                                            value: 'forge',
                                            child: ListTile(
                                              dense: true,
                                              contentPadding: EdgeInsets.zero,
                                              leading:
                                                  Icon(Icons.handyman_outlined),
                                              title: Text('安装 Forge 版本'),
                                              subtitle: Text(
                                                  '经典的 Mod 加载器'),
                                            ),
                                          ),
                                          PopupMenuItem(
                                            value: 'fabric',
                                            child: ListTile(
                                              dense: true,
                                              contentPadding: EdgeInsets.zero,
                                              leading: Icon(Icons.extension),
                                              title: Text('安装 Fabric 版本'),
                                              subtitle: Text(
                                                  '新一代 Mod 加载器'),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }

  Future<void> _download(BuildContext context, ManifestVersion v) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(content: Text('Downloading ${v.id}...')),
    );
    await context.read<VersionProvider>().download(v);
    if (!context.mounted) return;
    final err = context.read<VersionProvider>().error;
    if (err == null) {
      messenger.showSnackBar(
        SnackBar(content: Text('${v.id} installed')),
      );
      final settings = context.read<SettingsProvider>();
      if (settings.settings.selectedVersionId.isEmpty) {
        await settings.setSelectedVersion(v.id);
      }
    }
  }

  Future<void> _installLoader(
    BuildContext context,
    String kind,
    ManifestVersion v,
  ) async {
    final versions = context.read<VersionProvider>();
    final settingsProvider = context.read<SettingsProvider>();
    final mods = context.read<ModLoaderProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final settings = settingsProvider.settings;

    if (kind != 'fabric-api' && !versions.isInstalled(v.id)) {
      messenger.showSnackBar(
        SnackBar(content: Text('Downloading vanilla ${v.id} first...')),
      );
      await versions.download(v);
      if (!context.mounted) return;
      // Failures pop the shared error dialog via the error listener.
      if (versions.error != null || !versions.isInstalled(v.id)) return;
    }

    final gameRoot = settings.gameDirectory.isEmpty
        ? await PathService.instance.gameDirectory()
        : settings.gameDirectory;

    String? newId;
    switch (kind) {
      case 'forge':
        final builds = await mods.forgeBuilds(v.id, settings.downloadSource);
        if (!context.mounted) return;
        if (builds.isEmpty) {
          if (mods.error == null) {
            messenger.showSnackBar(SnackBar(
              content: Text('没有可用的 Forge 版本用于 ${v.id}'),
            ));
          }
          return;
        }
        newId = await mods.installForge(
          gameVersion: v.id,
          build: builds.first,
          javaPath: settings.javaPath,
          gameRoot: gameRoot,
          source: settings.downloadSource,
        );
        break;
      case 'fabric':
        final loaders =
            await mods.fabricLoaders(v.id, settings.downloadSource);
        if (!context.mounted) return;
        if (loaders.isEmpty) {
          if (mods.error == null) {
            messenger.showSnackBar(SnackBar(
              content: Text('没有可用的 Fabric 版本用于 ${v.id}'),
            ));
          }
          return;
        }
        final loader =
            loaders.firstWhere((l) => l.stable, orElse: () => loaders.first);
        newId = await mods.installFabric(
          gameVersion: v.id,
          loaderVersion: loader.version,
          source: settings.downloadSource,
        );
        break;
    }
    if (!context.mounted) return;

    // Install failures pop the shared error dialog via the listener.
    if (mods.error != null) return;
    await versions.refreshInstalled();
    if (newId != null) {
      await settingsProvider.setSelectedVersion(newId);
      messenger.showSnackBar(
        SnackBar(content: Text('$newId installed and selected')),
      );
    } else {
      messenger.showSnackBar(
        SnackBar(content: Text(mods.status ?? '完成')),
      );
    }
  }
}
