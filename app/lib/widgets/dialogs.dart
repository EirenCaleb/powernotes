import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/templates.dart';
import '../services/bible_service.dart';

Future<String?> promptText(BuildContext context, String title,
    {String initial = '', String? hint, bool obscure = false, int maxLines = 1}) {
  final c = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 420,
        child: TextField(
          controller: c,
          autofocus: true,
          obscureText: obscure,
          maxLines: obscure ? 1 : maxLines,
          decoration: InputDecoration(hintText: hint),
          onSubmitted: maxLines == 1 ? (v) => Navigator.pop(ctx, v) : null,
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('OK')),
      ],
    ),
  );
}

Future<bool> confirm(BuildContext context, String title, String body,
    {String ok = 'OK'}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(ok)),
      ],
    ),
  );
  return r ?? false;
}

void toast(BuildContext context, String msg) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating));
}

/// Returns "title\u0000body" with {{date}} filled, or null.
Future<NoteTemplate?> pickTemplate(BuildContext context) {
  return showModalBottomSheet<NoteTemplate>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: ListView(shrinkWrap: true, children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Text('New from template',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        ),
        for (final t in templates)
          ListTile(
            leading: Text(t.icon, style: const TextStyle(fontSize: 22)),
            title: Text(t.name),
            onTap: () => Navigator.pop(ctx, t),
          ),
      ]),
    ),
  );
}

String fillTemplate(String s) =>
    s.replaceAll('{{date}}', DateFormat('yyyy-MM-dd').format(DateTime.now()));

/// Asks for a Bible reference and returns the passage as Markdown quote.
Future<String?> pickBibleVerse(BuildContext context, String translation) {
  return showDialog<String>(
    context: context,
    builder: (_) => _BibleDialog(translation: translation),
  );
}

class _BibleDialog extends StatefulWidget {
  const _BibleDialog({required this.translation});
  final String translation;

  @override
  State<_BibleDialog> createState() => _BibleDialogState();
}

class _BibleDialogState extends State<_BibleDialog> {
  final _ref = TextEditingController();
  late String _tr = widget.translation;
  String? _result;
  String? _error;
  bool _busy = false;

  Future<void> _lookup() async {
    if (_ref.text.trim().isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      _result = await BibleService.lookup(_ref.text, _tr);
    } catch (e) {
      _error = '$e'.replaceFirst('Exception: ', '');
      _result = null;
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Insert Bible verse'),
      content: SizedBox(
        width: 480,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            Expanded(
              child: TextField(
                controller: _ref,
                autofocus: true,
                decoration: const InputDecoration(hintText: 'e.g. John 3:16 or Psalm 23:1-4'),
                onSubmitted: (_) => _lookup(),
              ),
            ),
            const SizedBox(width: 8),
            DropdownButton<String>(
              value: _tr,
              underline: const SizedBox(),
              items: [
                for (final e in BibleService.translations.entries)
                  DropdownMenuItem(value: e.key, child: Text(e.key.toUpperCase())),
              ],
              onChanged: (v) => setState(() => _tr = v ?? _tr),
            ),
          ]),
          const SizedBox(height: 12),
          if (_busy) const LinearProgressIndicator(),
          if (_error != null)
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          if (_result != null)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 260),
              child: SingleChildScrollView(child: SelectableText(_result!)),
            ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        if (_result == null)
          FilledButton(onPressed: _busy ? null : _lookup, child: const Text('Look up'))
        else
          FilledButton(
              onPressed: () => Navigator.pop(context, _result), child: const Text('Insert')),
      ],
    );
  }
}

/// Picks a date and time and returns "@remind(yyyy-MM-dd HH:mm)".
Future<String?> pickReminder(BuildContext context) async {
  final now = DateTime.now();
  final date = await showDatePicker(
    context: context,
    firstDate: now.subtract(const Duration(days: 1)),
    lastDate: now.add(const Duration(days: 365 * 3)),
    initialDate: now,
  );
  if (date == null || !context.mounted) return null;
  final time = await showTimePicker(
      context: context, initialTime: TimeOfDay.fromDateTime(now.add(const Duration(hours: 1))));
  if (time == null) return null;
  final dt = DateTime(date.year, date.month, date.day, time.hour, time.minute);
  return '@remind(${DateFormat('yyyy-MM-dd HH:mm').format(dt)})';
}
