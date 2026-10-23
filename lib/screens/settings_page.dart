import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/download_source.dart';
import '../providers/settings_provider.dart';
import '../providers/version_provider.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late TextEditingController _javaController;
  late TextEditingController _gameDirController;
  late TextEditingController _jvmArgsController;
  late TextEditingController _minMemController;
  late TextEditingController _maxMemController;
  late TextEditingController _widthController;
  late TextEditingController _heightController;
  bool _initialized = false;
  // Per-version Java override controllers
  Map<String, TextEditingController> _javaOverrideControllers = {};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    final s = context.read<SettingsProvider>().settings;
    final versions = context.read<VersionProvider>();
    _javaController = TextEditingController(text: s.javaPath);
    _gameDirController = TextEditingController(text: s.gameDirectory);
    _jvmArgsController = TextEditingController(text: s.jvmArgs);
    _minMemController = TextEditingController(text: '${s.minMemoryMb}');
    _maxMemController = TextEditingController(text: '${s.maxMemoryMb}');
    _widthController = TextEditingController(text: '${s.windowWidth}');
    _heightController = TextEditingController(text: '${s.windowHeight}');
    _initialized = true;
    // 初始化 per-version Java 覆盖控制器映射
    _javaOverrideControllers = {};
    for (final v in versions.installed) {
      final key = v.id;
      if (!_javaOverrideControllers.containsKey(key)) {
        _javaOverrideControllers[key] = TextEditingController(
          text: s.javaOverrides[key] ?? '',
        );
      }
    }
  }

  @override
  void dispose() {
    _javaController.dispose();
    _gameDirController.dispose();
    _jvmArgsController.dispose();
    _minMemController.dispose();
    _maxMemController.dispose();
    _widthController.dispose();
    _heightController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SettingsProvider>();
    final versions = context.watch<VersionProvider>();
    final s = provider.settings;
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 24, 32, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('设置', style: text.headlineMedium),
          const SizedBox(height: 8),
          Text(
            '在此设定你的启动器配置',
            style: text.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 24),
          Expanded(
            child: ListView(
              children: [
                _Section(
                  title: 'Java 配置',
                  child: Column(
                    children: [
                      TextField(
                        controller: _javaController,
                        decoration: InputDecoration(
                          labelText: 'Java 运行时路径',
                          hintText: r'C:\Program Files\Java\...\bin\java.exe',
                          suffixIcon: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: 'Auto detect',
                                onPressed: provider.scanningJava
                                    ? null
                                    : () async {
                                        final found = await provider
                                            .scanJavas();
                                        if (!context.mounted) return;
                                        if (found.isNotEmpty) {
                                          _javaController.text =
                                              found.first.path;
                                        } else {
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            const SnackBar(
                                              content: Text('还没有可用的 Java 运行时'),
                                            ),
                                          );
                                        }
                                      },
                                icon: provider.scanningJava
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.auto_fix_high),
                              ),
                              IconButton(
                                tooltip: 'Browse',
                                onPressed: () async {
                                  final result = await FilePicker.platform
                                      .pickFiles(
                                        type: FileType.custom,
                                        allowedExtensions: ['exe'],
                                      );
                                  if (result != null &&
                                      result.files.single.path != null) {
                                    _javaController.text =
                                        result.files.single.path!;
                                  }
                                },
                                icon: const Icon(Icons.folder_open),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (provider.detectedJavas != null &&
                          provider.detectedJavas!.isNotEmpty) ...[
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            '检测到的安装（点击使用为默认）：',
                            style: text.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final java in provider.detectedJavas!)
                              ActionChip(
                                label: Text(
                                  '${_shortPath(java.path)}'
                                  '${java.version != null ? ' (${java.version})' : ''}',
                                ),
                                avatar: const Icon(Icons.coffee, size: 18),
                                onPressed: () =>
                                    _javaController.text = java.path,
                              ),
                          ],
                        ),
                      ],
                      if ((provider.detectedJavas == null ||
                              provider.detectedJavas!.isEmpty) &&
                          !provider.scanningJava) ...[
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Tip：点击魔法棒可以自动扫描本地已安装的 Java 运行时',
                            style: text.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      TextField(
                        controller: _jvmArgsController,
                        decoration: const InputDecoration(
                          labelText: '额外 JVM 参数',
                          hintText: '-XX:+UseG1GC',
                        ),
                      ),
                    ],
                  ),
                ),
                _Section(
                  title: 'RAM 分配',
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _minMemController,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          decoration: const InputDecoration(
                            labelText: '最小 (MB)',
                            suffixText: 'MB',
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: TextField(
                          controller: _maxMemController,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          decoration: const InputDecoration(
                            labelText: '最大 (MB)',
                            suffixText: 'MB',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                _Section(
                  title: '游戏配置',
                  child: Column(
                    children: [
                      TextField(
                        controller: _gameDirController,
                        decoration: InputDecoration(
                          labelText: '游戏目录',
                          hintText: r'%APPDATA%\.minecraft',
                          suffixIcon: IconButton(
                            tooltip: 'Browse',
                            onPressed: () async {
                              final path = await FilePicker.platform
                                  .getDirectoryPath();
                              if (path != null) {
                                _gameDirController.text = path;
                              }
                            },
                            icon: const Icon(Icons.folder_open),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _widthController,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                              decoration: const InputDecoration(
                                labelText: 'Width',
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextField(
                              controller: _heightController,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                              decoration: const InputDecoration(
                                labelText: 'Height',
                              ),
                            ),
                          ),
                        ],
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Fullscreen'),
                        value: s.fullscreen,
                        onChanged: (v) =>
                            provider.update(s.copyWith(fullscreen: v)),
                      ),
                    ],
                  ),
                ),
                _Section(
                  title: '游戏下载源',
                  child: Column(
                    children: [
                      IgnorePointer(
                        ignoring: versions.downloading,
                        child: RadioGroup<DownloadSource>(
                          groupValue: s.downloadSource,
                          onChanged: (v) => _changeSource(context, v),
                          child: Column(
                            children: [
                              for (final src in DownloadSource.values)
                                RadioListTile<DownloadSource>(
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(src.label),
                                  subtitle: Text(src.description),
                                  value: src,
                                ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Switching the source refreshes the version list. '
                          'If a file is missing on the mirror, the official '
                          'server is used automatically.',
                          style: text.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                _Section(
                  title: '版本列表',
                  child: Column(
                    children: [
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('显示预览版'),
                        subtitle: const Text('在列表中包含预览（测试）版版本'),
                        value: s.showSnapshots,
                        onChanged: (v) =>
                            provider.update(s.copyWith(showSnapshots: v)),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('显示远古版本'),
                        subtitle: const Text('在列表中包含 Beta 及以下版本'),
                        value: s.showOldVersions,
                        onChanged: (v) =>
                            provider.update(s.copyWith(showOldVersions: v)),
                      ),
                    ],
                  ),
                ),

                _Section(
                  title: 'FLUTML 0.1.6',
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.code),
                        title: const Text('GitHub 仓库'),
                        subtitle: SelectableText(
                          'https://github.com/npickaxe11/FlutML',
                        ),
                        // 不添加 onTap，完全静态
                      ),
                      ListTile(
                        leading: const Icon(Icons.code),
                        title: const Text('Gitee 仓库'),
                        subtitle: SelectableText(
                          'https://gitee.com/npickaxe11/flut-ml',
                        ),
                        // 不添加 onTap，完全静态
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    onPressed: () => _save(context),
                    icon: const Icon(Icons.save_outlined),
                    label: const Text('保存配置'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _shortPath(String path, {int max = 42}) {
    if (path.length <= max) return path;
    return '...${path.substring(path.length - max + 3)}';
  }

  Future<void> _changeSource(
    BuildContext context,
    DownloadSource? source,
  ) async {
    if (source == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final provider = context.read<SettingsProvider>();
    final versions = context.read<VersionProvider>();
    await provider.update(provider.settings.copyWith(downloadSource: source));
    await versions.changeSource(source);
    messenger.showSnackBar(
      SnackBar(content: Text('Download source: ${source.label}')),
    );
  }

  Future<void> _save(BuildContext context) async {
    final provider = context.read<SettingsProvider>();
    final current = provider.settings;
    final minMem = int.tryParse(_minMemController.text) ?? 512;
    final maxMem = int.tryParse(_maxMemController.text) ?? 2048;
    final width = int.tryParse(_widthController.text) ?? 854;
    final height = int.tryParse(_heightController.text) ?? 480;

    // 收集所有版本的Java覆盖配置
    final javaOverrides = <String, String>{};
    for (final entry in _javaOverrideControllers.entries) {
      final text = entry.value.text.trim();
      if (text.isNotEmpty) {
        javaOverrides[entry.key] = text;
      }
    }
    // 合并到当前设置
    final updatedSettings = current.copyWith(
      javaPath: _javaController.text.trim(),
      gameDirectory: _gameDirController.text.trim(),
      jvmArgs: _jvmArgsController.text.trim(),
      minMemoryMb: minMem.clamp(256, 65536),
      maxMemoryMb: maxMem.clamp(512, 65536),
      windowWidth: width.clamp(640, 7680),
      windowHeight: height.clamp(480, 4320),
      javaOverrides: javaOverrides.isNotEmpty ? javaOverrides : {},
    );

    await provider.update(updatedSettings);

    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('设置已保存')));
    }
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 16),
              child,
            ],
          ),
        ),
      ),
    );
  }
}
