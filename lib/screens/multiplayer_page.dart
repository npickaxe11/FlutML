import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/account_provider.dart';
import '../providers/terracotta_provider.dart';

class MultiplayerPage extends StatefulWidget {
  const MultiplayerPage({super.key});

  @override
  State<MultiplayerPage> createState() => _MultiplayerPageState();
}

class _MultiplayerPageState extends State<MultiplayerPage> {
  final _roomCodeController = TextEditingController();

  @override
  void dispose() {
    _roomCodeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TerracottaProvider>();
    final account = context.watch<AccountProvider>();
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    final playerName = account.account?.username ?? 'Terracotta Player';

    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 24, 32, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('陶瓦联机 (Terracotta)', style: text.headlineMedium),
          const SizedBox(height: 8),
          Text(
            '基于 EasyTier 的 P2P 联机，低延迟、免公网',
            style: text.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 32),
          if (!provider.isRunning && !provider.starting)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.hub_outlined, size: 64, color: scheme.outline),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: () =>
                          provider.startEngine(playerName: playerName),
                      icon: const Icon(Icons.power_settings_new),
                      label: const Text('启动联机引擎'),
                    ),
                    // 👇 新增这段：把具体的报错写在这里
                    if (provider.errorMessage != null) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: scheme.errorContainer,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          provider.errorMessage!,
                          style: TextStyle(color: scheme.onErrorContainer),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            )
          else if (provider.starting)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 左侧：房间操作面板
                  Expanded(
                    flex: 3,
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.circle,
                                  color: scheme.primary,
                                  size: 12,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '引擎运行中',
                                  style: text.titleMedium?.copyWith(
                                    color: scheme.primary,
                                  ),
                                ),
                                const Spacer(),
                                TextButton(
                                  onPressed: () => provider.shutdown(),
                                  child: const Text('关闭引擎'),
                                ),
                              ],
                            ),
                            const Divider(height: 32),

                            // 根据状态渲染不同面板
                            Expanded(
                              child: _buildStateContent(
                                context,
                                provider,
                                playerName,
                              ),
                            ),

                            if (provider.state == 'host-ok' ||
                                provider.state == 'guest-ok' ||
                                provider.state.startsWith('host-') ||
                                provider.state.startsWith('guest-'))
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton.icon(
                                  onPressed: () => provider.leaveRoom(),
                                  icon: const Icon(Icons.close),
                                  label: const Text('断开连接'),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 20),
                  // 右侧：说明
                  Expanded(
                    flex: 2,
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('如何游玩', style: text.titleMedium),
                            const SizedBox(height: 16),
                            _buildStep(
                              '1. 房主点击「创建房间」，按提示在游戏里「对局域网开放」',
                              scheme,
                              text,
                            ),
                            _buildStep('2. 获取并复制生成的邀请码', scheme, text),
                            _buildStep('3. 好友输入邀请码并「加入房间」', scheme, text),
                            _buildStep('4. 好友在多人游戏中刷新即可看到房间', scheme, text),
                            const Spacer(),
                            Text(
                              'Powered by Terracotta & EasyTier\nAGPL-3.0 License',
                              style: text.labelSmall?.copyWith(
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

  Widget _buildStateContent(
    BuildContext context,
    TerracottaProvider provider,
    String playerName,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    switch (provider.state) {
      case 'waiting':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('创建房间 (房主)', style: text.titleSmall),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: () => provider.createRoom(playerName: playerName),
              icon: const Icon(Icons.add),
              label: const Text('创建房间 / 扫描局域网'),
            ),
            const Divider(height: 32),
            Text('加入房间 (客机)', style: text.titleSmall),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _roomCodeController,
                    decoration: const InputDecoration(
                      labelText: '邀请码',
                      hintText: '例如 U/XXXX-XXXX-XXXX-XXXX',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton(
                  onPressed: () async {
                    final ok = await provider.joinRoom(
                      _roomCodeController.text,
                      playerName: playerName,
                    );
                    if (!ok && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('邀请码格式错误或连接失败')),
                      );
                    }
                  },
                  child: const Text('加入'),
                ),
              ],
            ),
          ],
        );

      case 'host-scanning':
        return Column(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text('正在扫描局域网游戏...', style: text.titleMedium),
            const SizedBox(height: 8),
            Text(
              '请确保你的 Minecraft 已经进入游戏，并点击了「对局域网开放」。',
              style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ],
        );

      case 'host-starting':
        return const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('正在生成虚拟网络和邀请码...'),
            ],
          ),
        );

      case 'host-ok':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '房间已创建',
              style: text.titleMedium?.copyWith(color: scheme.primary),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('邀请码', style: text.labelMedium),
                        SelectableText(
                          provider.roomCode,
                          style: text.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            letterSpacing: 2,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: provider.roomCode));
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(const SnackBar(content: Text('已复制邀请码')));
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text('当前在线: ${provider.profiles.length} 人', style: text.titleSmall),
            ...provider.profiles.map(
              (p) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  p['kind'] == 'HOST' ? Icons.star : Icons.person,
                  color: p['kind'] == 'HOST' ? Colors.amber : scheme.primary,
                ),
                title: Text(p['name'] ?? '未知玩家'),
                subtitle: Text(p['vendor'] ?? ''),
              ),
            ),
          ],
        );

      case 'guest-connecting':
      case 'guest-starting':
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(
                provider.state == 'guest-connecting'
                    ? '正在尝试连接房主...'
                    : '正在建立 P2P 网络 (可能需要几十秒)',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        );

      case 'guest-ok':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '联机成功！',
              style: text.titleMedium?.copyWith(color: scheme.primary),
            ),
            const SizedBox(height: 16),
            Text('请在 Minecraft 多人游戏中添加服务器并连接以下地址：', style: text.bodyMedium),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  SelectableText(
                    provider.guestUrl,
                    style: text.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.copy),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: provider.guestUrl));
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(const SnackBar(content: Text('已复制地址')));
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text('当前在线: ${provider.profiles.length} 人', style: text.titleSmall),
            ...provider.profiles.map(
              (p) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  p['kind'] == 'HOST' ? Icons.star : Icons.person,
                  color: p['kind'] == 'HOST' ? Colors.amber : scheme.primary,
                ),
                title: Text(p['name'] ?? '未知玩家'),
                subtitle: Text(p['vendor'] ?? ''),
              ),
            ),
          ],
        );

      case 'exception':
        String msg = '未知异常';
        switch (provider.exceptionType) {
          case 0:
            msg = '无法连接到房主，请检查网络或邀请码。';
            break;
          case 1:
            msg = '连接被房主拒绝。';
            break;
          case 2:
            msg = '客机 Easytier 核心崩溃。';
            break;
          case 3:
            msg = '房主 Easytier 核心崩溃。';
            break;
          case 4:
            msg = '无法连接到 Minecraft 服务器，请确认房主已开放局域网。';
            break;
          case 5:
            msg = '协议解析错误。';
            break;
          case -99:
            msg = '本地启动失败。';
            break;
        }
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 48, color: scheme.error),
              const SizedBox(height: 16),
              Text(
                msg,
                style: text.titleMedium?.copyWith(color: scheme.error),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton.tonal(
                onPressed: () => provider.leaveRoom(),
                child: const Text('重试'),
              ),
            ],
          ),
        );

      default:
        return const SizedBox();
    }
  }

  Widget _buildStep(String textStr, ColorScheme scheme, TextTheme text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.check_circle_outline, size: 18, color: scheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              textStr,
              style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}
