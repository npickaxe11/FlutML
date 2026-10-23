import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/download_task.dart';
import '../providers/download_manager_provider.dart';

class DownloadManagerPage extends StatelessWidget {
  const DownloadManagerPage({super.key});

  @override
  Widget build(BuildContext context) {
    final manager = context.watch<DownloadManagerProvider>();
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final active = manager.activeTasks;
    final finished = manager.finishedTasks;

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
                    Text('下载管理', style: text.headlineMedium),
                    const SizedBox(height: 8),
                    Text(
                      '版本与资源的下载都在这里',
                      style: text.bodyLarge?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (finished.isNotEmpty)
                TextButton.icon(
                  onPressed: manager.clearFinished,
                  icon: const Icon(Icons.cleaning_services_outlined),
                  label: const Text('清空已结束'),
                ),
            ],
          ),
          const SizedBox(height: 20),
          if (manager.tasks.isEmpty)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.download_done_outlined,
                      size: 56,
                      color: scheme.outline,
                    ),
                    const SizedBox(height: 16),
                    Text('还没有下载任务', style: text.titleMedium),
                    const SizedBox(height: 8),
                    Text(
                      '去“下载”或“资源”页面获取内容吧',
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
              child: ListView(
                children: [
                  if (active.isNotEmpty) ...[
                    _SectionHeader(title: '进行中', count: active.length),
                    const SizedBox(height: 8),
                    for (final task in active)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _DownloadTaskCard(task: task),
                      ),
                    const SizedBox(height: 12),
                  ],
                  if (finished.isNotEmpty) ...[
                    _SectionHeader(title: '已结束', count: finished.length),
                    const SizedBox(height: 8),
                    for (final task in finished)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _DownloadTaskCard(task: task),
                      ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.count});

  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return Row(
      children: [
        Text(
          title,
          style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: scheme.secondaryContainer,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            '$count',
            style: text.labelSmall?.copyWith(
              color: scheme.onSecondaryContainer,
            ),
          ),
        ),
      ],
    );
  }
}

class _DownloadTaskCard extends StatelessWidget {
  const _DownloadTaskCard({required this.task});

  final DownloadTask task;

  @override
  Widget build(BuildContext context) {
    final manager = context.read<DownloadManagerProvider>();
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    final (icon, color) = switch (task.status) {
      DownloadTaskStatus.queued => (Icons.schedule, scheme.onSurfaceVariant),
      DownloadTaskStatus.downloading => (Icons.downloading, scheme.primary),
      DownloadTaskStatus.completed => (Icons.check_circle, scheme.primary),
      DownloadTaskStatus.failed => (Icons.error_outline, scheme.error),
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: color.withValues(alpha: 0.14),
                  foregroundColor: color,
                  child: Icon(icon),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        task.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        task.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!task.isActive)
                  IconButton(
                    tooltip: '移除记录',
                    onPressed: () => manager.removeTask(task.id),
                    icon: const Icon(Icons.close),
                  ),
              ],
            ),
            if (task.isActive) ...[
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: task.fraction,
                borderRadius: BorderRadius.circular(8),
                minHeight: 8,
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      task.stage,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  if (task.total > 0)
                    Text(
                      '${_formatBytes(task.received)} / '
                      '${_formatBytes(task.total)}',
                      style: text.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ] else ...[
              const SizedBox(height: 8),
              Text(
                task.stage,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: text.bodySmall?.copyWith(
                  color: task.status == DownloadTaskStatus.failed
                      ? scheme.error
                      : scheme.onSurfaceVariant,
                ),
              ),
              if (task.error != null) ...[
                const SizedBox(height: 4),
                SelectableText(
                  task.error!,
                  maxLines: 3,
                  style: text.bodySmall?.copyWith(color: scheme.error),
                ),
              ],
            ],
          ],
        ),
      ),
    );
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
