import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/minecraft_version.dart';
import '../providers/settings_provider.dart';
import '../providers/version_provider.dart';
import '../services/java_detector.dart';
import '../services/mc_java_requirements.dart';

class VersionsPage extends StatelessWidget {
  const VersionsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final versions = context.watch<VersionProvider>();
    final settings = context.watch<SettingsProvider>();
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final installed = versions.installed;
    final selectedId = settings.settings.selectedVersionId;

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
                    Text('版本管理', style: text.headlineMedium),
                    const SizedBox(height: 8),
                    Text(
                      '管理你已经安装了的游戏版本',
                      style: text.bodyLarge?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton.filledTonal(
                onPressed: versions.loadingInstalled
                    ? null
                    : () => versions.refreshInstalled(),
                icon: versions.loadingInstalled
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh),
                tooltip: 'Refresh',
              ),
            ],
          ),
          const SizedBox(height: 24),
          if (installed.isEmpty)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.inventory_2_outlined,
                      size: 56,
                      color: scheme.outline,
                    ),
                    const SizedBox(height: 16),
                    Text('还没有一个游戏...', style: text.titleMedium),
                    const SizedBox(height: 8),
                    Text(
                      '当然，你可以去下载标签页里获取版本',
                      style: text.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            Expanded(
              child: ListView.separated(
                itemCount: installed.length,
                separatorBuilder: (context, index) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final v = installed[index];
                  final selected = v.id == selectedId;
                  final override = settings.settings.javaOverrideFor(v.id);
                  return Card(
                    color: selected
                        ? scheme.secondaryContainer.withValues(alpha: 0.45)
                        : null,
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 8,
                      ),
                      leading: CircleAvatar(
                        backgroundColor: selected
                            ? scheme.primary
                            : scheme.surfaceContainerHighest,
                        foregroundColor: selected
                            ? scheme.onPrimary
                            : scheme.onSurfaceVariant,
                        child: Icon(_iconForType(v.type)),
                      ),
                      title: Text(v.id),
                      subtitle: Row(
                        children: [
                          Flexible(
                            child: Text(
                              [
                                versionTypeLabel(v.type),
                                if (v.releaseTime != null)
                                  _formatDate(v.releaseTime!),
                              ].join(' · '),
                            ),
                          ),
                          if (override.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            Tooltip(
                              message: override,
                              child: Icon(
                                Icons.coffee,
                                size: 16,
                                color: scheme.primary,
                              ),
                            ),
                          ],
                        ],
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (selected)
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: Chip(
                                label: const Text('已选中版本'),
                                visualDensity: VisualDensity.compact,
                                backgroundColor: scheme.primaryContainer,
                              ),
                            ),
                          if (!selected)
                            TextButton(
                              onPressed: () => context
                                  .read<SettingsProvider>()
                                  .setSelectedVersion(v.id),
                              child: const Text('选择此版本'),
                            ),
                          IconButton(
                            tooltip: 'Delete',
                            onPressed: () => _confirmDelete(context, v.id),
                            icon: Icon(
                              Icons.delete_outline,
                              color: scheme.error,
                            ),
                          ),
                        ],
                      ),
                      onTap: () => _showVersionDetails(context, v),
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

  IconData _iconForType(VersionType type) {
    switch (type) {
      case VersionType.release:
        return Icons.verified_outlined;
      case VersionType.snapshot:
        return Icons.science_outlined;
      case VersionType.oldBeta:
      case VersionType.oldAlpha:
        return Icons.history;
    }
  }

  Future<void> _showVersionDetails(
    BuildContext context,
    InstalledVersion v,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _VersionDetailsDialog(version: v),
    );
  }

  Future<void> _confirmDelete(BuildContext context, String id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('移除此版本？'),
        content: Text('将 $id 从你的电脑移除，此操作不可撤销（真的很久！！）'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('蒜鸟蒜鸟'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('移除此版本'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;

    final versionProvider = context.read<VersionProvider>();
    final settings = context.read<SettingsProvider>();
    await versionProvider.deleteVersion(id);
    if (!context.mounted) return;

    if (settings.settings.selectedVersionId == id) {
      final remaining = versionProvider.installed;
      await settings.setSelectedVersion(
        remaining.isNotEmpty ? remaining.first.id : '',
      );
    }
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('已选中版本 $id')));
  }
}

class _VersionDetailsDialog extends StatefulWidget {
  const _VersionDetailsDialog({required this.version});

  final InstalledVersion version;

  @override
  State<_VersionDetailsDialog> createState() => _VersionDetailsDialogState();
}

class _VersionDetailsDialogState extends State<_VersionDetailsDialog> {
  /// '' = launcher default, otherwise a java executable path.
  late String _choice;
  final _customController = TextEditingController();
  static const _customKey = '__custom__';

  @override
  void initState() {
    super.initState();
    _choice =
        context
            .read<SettingsProvider>()
            .settings
            .javaOverrideFor(widget.version.id)
            .isNotEmpty
        ? context.read<SettingsProvider>().settings.javaOverrideFor(
            widget.version.id,
          )
        : '';
    // Kick off an automatic scan so detected installs appear promptly.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<SettingsProvider>().scanJavas();
    });
  }

  @override
  void dispose() {
    _customController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SettingsProvider>();
    final javas = provider.detectedJavas ?? const <JavaInstall>[];
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final v = widget.version;

    return AlertDialog(
      title: Text(v.id),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              [
                versionTypeLabel(v.type),
                if (v.releaseTime != null) _formatDate(v.releaseTime!),
              ].join(' · '),
              style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 4),
            Text(
              v.directory,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const Divider(height: 24),
            Text('为此版本使用的 Java', style: text.titleSmall),
            const SizedBox(height: 4),
            Text(
              '受支持版本: Java ${McJavaRequirements.requiredMajor(v.id)}',
              style: text.bodySmall?.copyWith(color: scheme.primary),
            ),
            const SizedBox(height: 4),
            Flexible(
              child: SingleChildScrollView(
                child: RadioGroup<String>(
                  groupValue: _choice,
                  onChanged: (v_) => setState(() => _choice = v_ ?? ''),
                  child: Column(
                    children: [
                      RadioListTile<String>(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        value: '',
                        title: const Text('Auto (launcher default)'),
                      ),
                      for (final java in javas)
                        RadioListTile<String>(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          value: java.path,
                          title: Text(java.label),
                          subtitle: Text(_shorten(java.path)),
                        ),
                      RadioListTile<String>(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        value: _customKey,
                        title: const Text('Custom Java path...'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (_choice == _customKey)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: TextField(
                  controller: _customController,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: 'java executable',
                    hintText: r'C:\Program Files\Java\bin\java.exe',
                    suffixIcon: IconButton(
                      tooltip: 'Browse',
                      onPressed: () async {
                        final result = await FilePicker.platform.pickFiles(
                          type: FileType.custom,
                          allowedExtensions: ['exe'],
                        );
                        if (result != null &&
                            result.files.single.path != null) {
                          _customController.text = result.files.single.path!;
                          setState(() {});
                        }
                      },
                      icon: const Icon(Icons.folder_open),
                    ),
                  ),
                ),
              ),
            if (javas.isEmpty && provider.scanningJava)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 8),
                    Text('Scanning for Java installations...'),
                  ],
                ),
              ),
          ],
        ),
      ),
      actions: [
        if (context.read<VersionProvider>().installed.any(
              (e) => e.id == v.id,
            ) &&
            provider.settings.selectedVersionId != v.id)
          TextButton(
            onPressed: () async {
              await provider.setSelectedVersion(v.id);
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('设定档案'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton.icon(
          onPressed: () => _save(provider),
          icon: const Icon(Icons.check),
          label: const Text('保存配置'),
        ),
      ],
    );
  }

  Future<void> _save(SettingsProvider provider) async {
    final messenger = ScaffoldMessenger.of(context);
    String effective = '';
    if (_choice == _customKey) {
      effective = _customController.text.trim();
      if (effective.isEmpty) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Pick a java executable first')),
        );
        return;
      }
    } else {
      effective = _choice;
    }
    await provider.setJavaOverride(widget.version.id, effective);
    if (!mounted) return;
    Navigator.pop(context);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          effective.isEmpty
              ? '${widget.version.id} will use the default Java'
              : 'Java set for ${widget.version.id}',
        ),
      ),
    );
  }

  String _shorten(String path, {int max = 46}) {
    if (path.length <= max) return path;
    return '...${path.substring(path.length - max + 3)}';
  }

  String _formatDate(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }
}
