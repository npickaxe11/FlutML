import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/download_source.dart';
import '../models/minecraft_version.dart';
import '../providers/account_provider.dart';
import '../providers/launch_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/version_provider.dart';
import '../widgets/error_dialog.dart';
import '../widgets/login_dialog.dart';

class PlayPage extends StatefulWidget {
  const PlayPage({super.key});

  @override
  State<PlayPage> createState() => _PlayPageState();
}

class _PlayPageState extends State<PlayPage> {
  int? _lastErrorTicket;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final launch = context.watch<LaunchProvider>();
    final ticket = launch.errorTicket;
    if (_lastErrorTicket == null) {
      _lastErrorTicket = ticket;
    } else if (ticket != _lastErrorTicket) {
      _lastErrorTicket = ticket;
      final message = launch.error;
      if (message != null && message.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          showErrorDialog(context, title: '游戏出错了 (っ °Д °;)っ', message: message);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final account = context.watch<AccountProvider>();
    final versions = context.watch<VersionProvider>();
    final settings = context.watch<SettingsProvider>();
    final launch = context.watch<LaunchProvider>();
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    final selectedId = settings.settings.selectedVersionId;
    final installed = versions.installed;
    final selected = installed.where((v) => v.id == selectedId).firstOrNull ??
        (installed.isNotEmpty ? installed.first : null);

    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 24, 32, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('欢迎使用', style: text.headlineMedium),
          const SizedBox(height: 8),
          Text(
            '在此启动 Minecraft',
            style: text.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 32),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 3,
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(28),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              CircleAvatar(
                                radius: 28,
                                backgroundColor: scheme.primaryContainer,
                                child: Icon(
                                  Icons.person,
                                  size: 32,
                                  color: scheme.onPrimaryContainer,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      account.isLoggedIn
                                          ? account.account!.username
                                          : '无可用账户',
                                      style: text.titleLarge,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      account.isLoggedIn
                                          ? '${account.account!.type.label}${account.account!.authServerName.isNotEmpty ? ' · ${account.account!.authServerName}' : ''}'
                                          : '登入以游玩',
                                      style: text.bodySmall?.copyWith(
                                        color: scheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (account.isLoggedIn)
                                TextButton.icon(
                                  onPressed: () => account.logout(),
                                  icon: const Icon(Icons.logout),
                                  label: const Text('登出启动器'),
                                )
                              else
                                FilledButton.tonalIcon(
                                  onPressed: () =>
                                      showLoginDialog(context),
                                  icon: const Icon(Icons.login),
                                  label: const Text('登入启动器'),
                                ),
                            ],
                          ),
                          const Spacer(),
                          Text('Version', style: text.titleMedium),
                          const SizedBox(height: 12),
                          if (installed.isEmpty)
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: scheme.surfaceContainerHigh,
                                borderRadius: BorderRadius.circular(12),
                              ),
child: Text(
                              '未安装任何版本,请在下载标签页获取游戏。',
                              style: text.bodyMedium?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                            )
                          else
                            DropdownMenu<String>(
                              key: ValueKey(selected?.id),
                              initialSelection: selected?.id,
                              width: double.infinity,
                              label: const Text('已安装版本'),
                              dropdownMenuEntries: installed
                                  .map(
                                    (v) => DropdownMenuEntry(
                                      value: v.id,
                                      label: v.id,
                                      leadingIcon: Icon(
                                        _iconForType(v.type),
                                        size: 20,
                                      ),
                                    ),
                                  )
                                  .toList(),
                              onSelected: (id) {
                                if (id != null) {
                                  context
                                      .read<SettingsProvider>()
                                      .setSelectedVersion(id);
                                }
                              },
                            ),
                          const SizedBox(height: 28),
                          SizedBox(
                            width: double.infinity,
                            height: 52,
                            child: FilledButton.icon(
                              onPressed: launch.launching ||
                                      !account.isLoggedIn ||
                                      selected == null
                                  ? null
                                  : () => _launch(context, selected.id),
                              icon: launch.launching
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.play_arrow_rounded),
                              label: Text(
                                launch.launching ? 'Launching...' : 'Launch',
                              ),
                            ),
                          ),
                          if (launch.error == null && launch.status != null) ...[
                            const SizedBox(height: 12),
                            Text(
                              launch.status!,
                              style: text.bodySmall?.copyWith(
                                color: scheme.primary,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  flex: 2,
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('FLUTML 配置信息', style: text.titleMedium),
                          const SizedBox(height: 16),
                          _InfoRow(
                            icon: Icons.memory,
                            label: 'RAM',
                            value:
                                '${settings.settings.minMemoryMb} - ${settings.settings.maxMemoryMb} MB',
                          ),
                          _InfoRow(
                            icon: Icons.folder_outlined,
                            label: '游戏路径',
                            value: settings.settings.gameDirectory.isEmpty
                                ? 'Default'
                                : settings.settings.gameDirectory,
                          ),
                          _InfoRow(
                            icon: Icons.aspect_ratio,
                            label: 'Resolution',
                            value: settings.settings.fullscreen
                                ? 'Fullscreen'
                                : '${settings.settings.windowWidth}×${settings.settings.windowHeight}',
                          ),
                          const Spacer(),
                          Text(
                            '${installed.length} version(s) installed',
                            style: text.labelLarge?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _launch(BuildContext context, String versionId) async {
    final accountProvider = context.read<AccountProvider>();
    var account = accountProvider.account;
    if (account == null) {
      await showLoginDialog(context);
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    final settings = context.read<SettingsProvider>().settings;
    final preferChina = settings.downloadSource == DownloadSource.china;

    // Refresh Microsoft tokens when close to expiry.
    account = await accountProvider.ensureValidToken(
      preferChinaMirror: preferChina,
    );
    if (!context.mounted) return;
    if (account == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Session expired, please sign in again')),
      );
      return;
    }

    final ok = await context.read<LaunchProvider>().play(
          account: account,
          versionId: versionId,
          settings: settings.copyWith(selectedVersionId: versionId),
        );
    if (!context.mounted) return;
    if (ok) {
      messenger.showSnackBar(
        SnackBar(content: Text('Launching $versionId')),
      );
    }
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
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: scheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
