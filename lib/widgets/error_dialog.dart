import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Shows a modal error dialog with a scrollable, selectable message and a
/// one-click "copy details" button.
Future<void> showErrorDialog(
  BuildContext context, {
  String title = 'Error',
  required String message,
}) async {
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => _ErrorDialog(title: title, message: message),
  );
}

class _ErrorDialog extends StatefulWidget {
  const _ErrorDialog({required this.title, required this.message});

  final String title;
  final String message;

  @override
  State<_ErrorDialog> createState() => _ErrorDialogState();
}

class _ErrorDialogState extends State<_ErrorDialog> {
  bool _copied = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final fullText = widget.message.trim().isEmpty
        ? 'Unknown error'
        : widget.message.trim();

    return AlertDialog(
      icon: Icon(Icons.error_outline, color: scheme.error, size: 32),
      title: Text(widget.title),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 380),
        child: SingleChildScrollView(
          child: SelectableText(
            fullText,
            style: text.bodySmall?.copyWith(fontFamily: 'monospace'),
          ),
        ),
      ),
      actions: [
        TextButton.icon(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: fullText));
            if (mounted) setState(() => _copied = true);
          },
          icon: Icon(_copied ? Icons.check : Icons.copy_all_rounded),
          label: Text(_copied ? 'Copied' : 'Copy details'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
