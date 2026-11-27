import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../services/ai_service.dart';
import '../services/settings.dart';
import 'dialogs.dart';

/// Opens the AI menu. Works on the selected text, or the whole note if
/// nothing is selected.
Future<void> showAiSheet(BuildContext context, TextEditingController body,
    {required VoidCallback onChanged}) async {
  if (!context.read<Settings>().signedIn) {
    toast(context, 'AI runs through your server. Sign in under Settings first.');
    return;
  }
  final sel = body.selection;
  final hasSel = sel.isValid && !sel.isCollapsed;
  final source = hasSel ? sel.textInside(body.text) : body.text;
  if (source.trim().isEmpty) {
    toast(context, 'Write something first.');
    return;
  }

  final action = await showModalBottomSheet<AiAction>(
    context: context,
    showDragHandle: true,
    builder: (c) => SafeArea(
      child: ListView(shrinkWrap: true, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Text(hasSel ? 'AI on selected text' : 'AI on this note',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        ),
        for (final a in aiActions)
          ListTile(
            leading: Text(a.icon, style: const TextStyle(fontSize: 20)),
            title: Text(a.label),
            onTap: () => Navigator.pop(c, a),
          ),
      ]),
    ),
  );
  if (action == null || !context.mounted) return;

  String? question;
  if (action.id == 'ask') {
    question = await promptText(context, 'Ask about this note',
        hint: 'e.g. What are the three main points?', maxLines: 3);
    if (question == null || question.trim().isEmpty || !context.mounted) return;
  }

  final result = await showDialog<String>(
    context: context,
    builder: (_) => _AiResultDialog(
      action: action,
      future: context.read<AiService>().run(action.id, source, question: question),
    ),
  );
  if (result == null) return;

  final text = body.text;
  if (result == 'replace') {
    final start = hasSel ? sel.start : 0;
    final end = hasSel ? sel.end : text.length;
    body.value = TextEditingValue(
      text: text.replaceRange(start, end, _last!),
      selection: TextSelection.collapsed(offset: start + _last!.length),
    );
  } else if (result == 'insert') {
    final at = hasSel ? sel.end : text.length;
    final insert = '\n\n${_last!}\n';
    body.value = TextEditingValue(
      text: text.replaceRange(at, at, insert),
      selection: TextSelection.collapsed(offset: at + insert.length),
    );
  }
  onChanged();
}

String? _last;

class _AiResultDialog extends StatelessWidget {
  const _AiResultDialog({required this.action, required this.future});
  final AiAction action;
  final Future<String> future;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: future,
      builder: (context, snap) {
        final done = snap.connectionState == ConnectionState.done;
        final ok = done && snap.hasData;
        if (ok) _last = snap.data!.trim();
        return AlertDialog(
          title: Text('${action.icon}  ${action.label}'),
          content: SizedBox(
            width: 560,
            child: !done
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: CircularProgressIndicator()),
                  )
                : snap.hasError
                    ? Text('${snap.error}',
                        style: TextStyle(color: Theme.of(context).colorScheme.error))
                    : ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 420),
                        child: SingleChildScrollView(child: SelectableText(_last!)),
                      ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
            if (ok) ...[
              TextButton(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: _last!));
                  Navigator.pop(context);
                },
                child: const Text('Copy'),
              ),
              if (action.id != 'ask')
                TextButton(
                    onPressed: () => Navigator.pop(context, 'insert'),
                    child: const Text('Insert below')),
              if (action.replaces)
                FilledButton(
                    onPressed: () => Navigator.pop(context, 'replace'),
                    child: const Text('Replace')),
            ],
          ],
        );
      },
    );
  }
}
