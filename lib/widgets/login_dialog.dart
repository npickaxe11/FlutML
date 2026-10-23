import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../providers/account_provider.dart';
import '../models/download_source.dart';
import '../providers/settings_provider.dart';

Future<void> showLoginDialog(BuildContext context) async {
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const _LoginDialog(),
  );
}

enum _LoginMode { offline, microsoft, skinServer }

class _LoginDialog extends StatefulWidget {
  const _LoginDialog();

  @override
  State<_LoginDialog> createState() => _LoginDialogState();
}

class _LoginDialogState extends State<_LoginDialog> {
  _LoginMode _mode = _LoginMode.offline;

  final _offlineName = TextEditingController();
  final _serverUrl = TextEditingController();
  final _skinUser = TextEditingController();
  final _skinPass = TextEditingController();
  final _offlineForm = GlobalKey<FormState>();
  final _skinForm = GlobalKey<FormState>();

  String? _msaStatus;

  @override
  void dispose() {
    _offlineName.dispose();
    _serverUrl.dispose();
    _skinUser.dispose();
    _skinPass.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final account = context.watch<AccountProvider>();
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return AlertDialog(
      title: const Text('Add account'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedButton<_LoginMode>(
              segments: const [
                ButtonSegment(
                  value: _LoginMode.offline,
                  icon: Icon(Icons.person_outline)
                ),
                ButtonSegment(
                  value: _LoginMode.microsoft,
                  icon: Icon(Icons.verified_user_outlined)
                ),
                ButtonSegment(
                  value: _LoginMode.skinServer,
                  icon: Icon(Icons.dns_outlined)
                ),
              ],
              selected: {_mode},
              onSelectionChanged: (s) => setState(() => _mode = s.first),
            ),
            const SizedBox(height: 16),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 150),
              child: switch (_mode) {
                _LoginMode.offline => Form(
                    key: _offlineForm,
                    child: TextFormField(
                      controller: _offlineName,
                      autofocus: true,
                      decoration: const InputDecoration(
                        labelText: 'Username',
                        hintText: 'Steve',
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                      validator: (value) {
                        final v = value?.trim() ?? '';
                        if (v.length < 3 || v.length > 16) {
                          return '3–16 characters required';
                        }
                        if (!RegExp(r'^[A-Za-z0-9_]+$').hasMatch(v)) {
                          return 'Letters, numbers, underscore only';
                        }
                        return null;
                      },
                      onFieldSubmitted: (_) => _loginOffline(),
                    ),
                  ),
                _LoginMode.microsoft => _buildMicrosoftTab(account, text, scheme),
                _LoginMode.skinServer => Form(
                    key: _skinForm,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextFormField(
                          controller: _serverUrl,
                          decoration: const InputDecoration(
                            labelText: 'Authlib-injector server URL',
                            hintText: 'https://littleskin.cn/api/yggdrasil',
                            prefixIcon: Icon(Icons.dns_outlined),
                          ),
                          validator: (v) =>
                              (v?.trim().isEmpty ?? true) ? 'Required' : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _skinUser,
                          decoration: const InputDecoration(
                            labelText: 'Email or username',
                            prefixIcon: Icon(Icons.alternate_email_outlined),
                          ),
                          validator: (v) =>
                              (v?.trim().isEmpty ?? true) ? 'Required' : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _skinPass,
                          obscureText: true,
                          decoration: const InputDecoration(
                            labelText: 'Password',
                            prefixIcon: Icon(Icons.password_outlined),
                          ),
                          validator: (v) =>
                              (v == null || v.isEmpty) ? 'Required' : null,
                          onFieldSubmitted: (_) => _loginSkinServer(),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Works with Blessing Skin / authlib-injector servers '
                          '(e.g. LittleSkin). Skins are applied in game.',
                          style: text.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
              },
            ),
            if (account.error != null) ...[
              const SizedBox(height: 12),
              Text(
                account.error!,
                style:
                    text.bodySmall?.copyWith(color: scheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: _actionsFor(account),
    );
  }

  Widget _buildMicrosoftTab(
    AccountProvider account,
    TextTheme text,
    ColorScheme scheme,
  ) {
    final code = account.deviceCode;
    if (code == null && !account.msaBusy) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Sign in with your Microsoft account that owns Minecraft. '
            'A device code will be shown to confirm in your browser.',
            style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      );
    }
    if (code != null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('1. Open', style: text.labelLarge),
          const SizedBox(height: 4),
          SelectableText(code.verificationUri,
              style: text.bodyLarge?.copyWith(color: scheme.primary)),
          const SizedBox(height: 12),
          Text('2. Enter code', style: text.labelLarge),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                SelectableText(
                  code.userCode,
                  style: text.headlineSmall
                      ?.copyWith(letterSpacing: 2, fontWeight: FontWeight.bold),
                ),
                IconButton.outlined(
                  tooltip: 'Copy',
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: code.userCode));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Code copied')),
                    );
                  },
                  icon: const Icon(Icons.copy, size: 18),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _msaStatus ?? 'Waiting for sign-in…',
                  style: text.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ],
      );
    }
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(8),
        child: CircularProgressIndicator(),
      ),
    );
  }

  List<Widget> _actionsFor(AccountProvider account) {
    return switch (_mode) {
      _LoginMode.offline => [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: _loginOffline,
            icon: const Icon(Icons.login),
            label: const Text('Sign in'),
          ),
        ],
      _LoginMode.microsoft => [
          TextButton(
            onPressed: () async {
              await account.cancelMicrosoftLogin();
            },
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: account.deviceCode != null || account.msaBusy
                ? null
                : () async {
                    final messenger = ScaffoldMessenger.of(context);
                    final ok = await context
                        .read<AccountProvider>()
                        .startMicrosoftLoginAndPoll(
                          onStatus: (s) => setState(() => _msaStatus = s),
                        );
                    if (!mounted) return;
                    final name = context
                            .read<AccountProvider>()
                            .account
                            ?.username ??
                        '';
                    Navigator.pop(context);
                    messenger.showSnackBar(
                      SnackBar(
                        content: Text(ok
                            ? 'Signed in as $name'
                            : 'Microsoft sign-in failed'),
                      ),
                    );
                  },
            icon: const Icon(Icons.verified_user_outlined),
            label: const Text('Start sign-in'),
          ),
        ],
      _LoginMode.skinServer => [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: _loginSkinServer,
            icon: const Icon(Icons.login),
            label: const Text('Sign in'),
          ),
        ],
    };
  }

  Future<void> _loginOffline() async {
    if (!(_offlineForm.currentState?.validate() ?? false)) return;
    final messenger = ScaffoldMessenger.of(context);
    final account = context.read<AccountProvider>();
    final ok = await account.loginOffline(_offlineName.text);
    if (!mounted) return;
    Navigator.pop(context);
    messenger.showSnackBar(
      SnackBar(
        content: Text(ok
            ? 'Signed in as ${account.account!.username}'
            : 'Sign-in failed'),
      ),
    );
  }

  Future<void> _loginSkinServer() async {
    if (!(_skinForm.currentState?.validate() ?? false)) return;
    final messenger = ScaffoldMessenger.of(context);
    final preferChina =
        context.read<SettingsProvider>().settings.downloadSource ==
            DownloadSource.china;
    final account = context.read<AccountProvider>();
    final ok = await account.loginSkinServer(
      serverUrl: _serverUrl.text,
      username: _skinUser.text.trim(),
      password: _skinPass.text,
      preferChinaMirror: preferChina,
    );
    if (!mounted) return;
    Navigator.pop(context);
    messenger.showSnackBar(
      SnackBar(
        content: Text(ok
            ? 'Signed in as ${account.account!.username} '
                '(${account.account!.authServerName})'
            : account.error ?? 'Login failed'),
      ),
    );
  }
}
