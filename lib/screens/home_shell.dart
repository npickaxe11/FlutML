import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/account_provider.dart';
import '../screens/download_manager_page.dart';
import '../screens/downloads_page.dart';
import '../screens/play_page.dart';
import '../screens/resources_page.dart';
import '../screens/settings_page.dart';
import '../screens/versions_page.dart';
import '../widgets/login_dialog.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  static const _destinations = [
    NavigationRailDestination(
      icon: Icon(Icons.play_circle_outline),
      selectedIcon: Icon(Icons.play_circle),
      label: Text('游戏'),
    ),
    NavigationRailDestination(
      icon: Icon(Icons.inventory_2_outlined),
      selectedIcon: Icon(Icons.inventory_2),
      label: Text('版本'),
    ),
    NavigationRailDestination(
      icon: Icon(Icons.widgets_outlined),
      selectedIcon: Icon(Icons.widgets),
      label: Text('资源'),
    ),
    NavigationRailDestination(
      icon: Icon(Icons.download_outlined),
      selectedIcon: Icon(Icons.download),
      label: Text('下载'),
    ),
    NavigationRailDestination(
      icon: Icon(Icons.downloading_outlined),
      selectedIcon: Icon(Icons.downloading),
      label: Text('管理'),
    ),
    NavigationRailDestination(
      icon: Icon(Icons.settings_outlined),
      selectedIcon: Icon(Icons.settings),
      label: Text('设置'),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final account = context.watch<AccountProvider>();
    final scheme = Theme.of(context).colorScheme;

    final pages = const [
      PlayPage(),
      VersionsPage(),
      ResourcesPage(),
      DownloadsPage(),
      DownloadManagerPage(),
      SettingsPage(),
    ];

    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _index,
            onDestinationSelected: (i) => setState(() => _index = i),
            labelType: NavigationRailLabelType.all,
            leading: Padding(
              padding: const EdgeInsets.only(top: 16, bottom: 24),
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: scheme.primaryContainer,
                    child: Icon(
                      Icons.sports_esports,
                      color: scheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
            trailing: Expanded(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: IconButton.filledTonal(
                    tooltip: account.isLoggedIn
                        ? account.account!.username
                        : 'Offline login',
                    onPressed: () {
                      if (account.isLoggedIn) {
                        showModalBottomSheet<void>(
                          context: context,
                          showDragHandle: true,
                          builder: (ctx) => Padding(
                            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: const Icon(Icons.person),
                                  title: Text(account.account!.username),
                                  subtitle: Text(account.account!.type.label),
                                ),
                                const SizedBox(height: 8),
                                OutlinedButton.icon(
                                  onPressed: () {
                                    Navigator.pop(ctx);
                                    account.logout();
                                  },
                                  icon: const Icon(Icons.logout),
                                  label: const Text('Logout'),
                                ),
                              ],
                            ),
                          ),
                        );
                      } else {
                        showLoginDialog(context);
                      }
                    },
                    icon: Icon(
                      account.isLoggedIn ? Icons.person : Icons.person_outline,
                    ),
                  ),
                ),
              ),
            ),
            destinations: _destinations,
          ),
          VerticalDivider(
            width: 1,
            thickness: 1,
            color: scheme.outlineVariant.withValues(alpha: 0.5),
          ),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              layoutBuilder: (current, previous) => Stack(
                fit: StackFit.expand,
                children: [...previous, ?current],
              ),
              transitionBuilder: (child, animation) {
                return FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0.015, 0),
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  ),
                );
              },
              child: KeyedSubtree(
                key: ValueKey<int>(_index),
                child: pages[_index],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
