import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import 'providers/account_provider.dart';
import 'providers/download_manager_provider.dart';
import 'providers/launch_provider.dart';
import 'providers/mod_loader_provider.dart';
import 'providers/resource_provider.dart';
import 'providers/settings_provider.dart';
import 'providers/theme_provider.dart';
import 'providers/version_provider.dart';
import 'screens/home_shell.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await windowManager.ensureInitialized();
  const windowOptions = WindowOptions(
    size: Size(1100, 720),
    minimumSize: Size(900, 600),
    center: true,
    title: 'FLUT Launcher',
  );
  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  final accountProvider = AccountProvider();
  final settingsProvider = SettingsProvider();
  final downloadManagerProvider = DownloadManagerProvider();
  final versionProvider = VersionProvider(
    downloadManager: downloadManagerProvider,
  );
  final launchProvider = LaunchProvider();
  final modLoaderProvider = ModLoaderProvider();
  final resourceProvider = ResourceProvider(
    downloadManager: downloadManagerProvider,
  );
  final themeProvider = ThemeProvider();

  await Future.wait([accountProvider.init(), settingsProvider.init()]);
  await versionProvider.init(source: settingsProvider.settings.downloadSource);

  final selected = settingsProvider.settings.selectedVersionId;
  if (selected.isEmpty && versionProvider.installed.isNotEmpty) {
    await settingsProvider.setSelectedVersion(
      versionProvider.installed.first.id,
    );
  }

  // ★ 这里必须是 MultiProvider 包住 MinecraftLauncherApp
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: accountProvider),
        ChangeNotifierProvider.value(value: settingsProvider),
        ChangeNotifierProvider.value(value: versionProvider),
        ChangeNotifierProvider.value(value: launchProvider),
        ChangeNotifierProvider.value(value: modLoaderProvider),
        ChangeNotifierProvider.value(value: downloadManagerProvider),
        ChangeNotifierProvider.value(value: resourceProvider),
        ChangeNotifierProvider.value(value: themeProvider),
      ],
      child: const MinecraftLauncherApp(),
    ),
  );
}

class MinecraftLauncherApp extends StatefulWidget {
  const MinecraftLauncherApp({super.key});

  @override
  State<MinecraftLauncherApp> createState() => _MinecraftLauncherAppState();
}

class _MinecraftLauncherAppState extends State<MinecraftLauncherApp>
    with WidgetsBindingObserver {
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _boot());
  }

  Future<void> _boot() async {
    final theme = context.read<ThemeProvider>();
    try {
      await theme.ensureInitialized().timeout(const Duration(seconds: 1));
    } catch (_) {}
    if (!mounted) return;
    setState(() => _ready = true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      context.read<ThemeProvider>().refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>();
    return MaterialApp(
      title: 'FLUT Launcher',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(
        brightness: Brightness.light,
        seedColor: theme.seedColor,
      ),
      darkTheme: buildAppTheme(
        brightness: Brightness.dark,
        seedColor: theme.seedColor,
      ),
      themeMode: ThemeMode.system,
      themeAnimationDuration: const Duration(milliseconds: 600),
      themeAnimationCurve: Curves.easeInOut,
      home: AnimatedSwitcher(
        duration: const Duration(milliseconds: 450),
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        layoutBuilder: (current, previous) =>
            Stack(fit: StackFit.expand, children: [...previous, ?current]),
        child: _ready
            ? const HomeShell(key: ValueKey('home'))
            : const _BootSplash(key: ValueKey('splash')),
      ),
    );
  }
}

class _BootSplash extends StatelessWidget {
  const _BootSplash({super.key});

  @override
  Widget build(BuildContext context) {
    final brightness = MediaQuery.platformBrightnessOf(context);
    final bg = brightness == Brightness.dark
        ? const Color(0xFF141414)
        : const Color(0xFFF8F8F8);
    return Scaffold(backgroundColor: bg, body: const SizedBox.expand());
  }
}
