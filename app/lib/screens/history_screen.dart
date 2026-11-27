import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/note.dart';
import '../services/notes_store.dart';
import '../widgets/dialogs.dart';
import '../widgets/markdown_view.dart';

/// Version history: every few minutes of editing is kept, going back days.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key, required this.note});
  final Note note;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<NoteVersion> _versions = [];
  NoteVersion? _selected;

  @override
  void initState() {
    super.initState();
    context.read<NotesStore>().db.versions(widget.note.uuid).then((v) {
      if (mounted) {
        setState(() {
          _versions = v;
          _selected = v.isEmpty ? null : v.first;
        });
      }
    });
  }

  Future<void> _restore(NoteVersion v) async {
    final store = context.read<NotesStore>();
    if (!await confirm(context, 'Restore this version?',
        'The current text is kept in history too, so you can undo this.',
        ok: 'Restore')) {
      return;
    }
    final n = store.byUuid(widget.note.uuid) ?? widget.note;
    await store.snapshot(n);
    n
      ..title = v.title
      ..body = v.body;
    await store.save(n, forceVersion: true);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.of(context).size.width >= 800;
    final fmt = DateFormat('EEE, MMM d, yyyy · h:mm a');
    final list = ListView.builder(
      itemCount: _versions.length,
      itemBuilder: (_, i) {
        final v = _versions[i];
        return ListTile(
          selected: identical(v, _selected),
          title: Text(fmt.format(DateTime.fromMillisecondsSinceEpoch(v.createdAt))),
          subtitle: Text(
              '${v.body.trim().isEmpty ? 0 : v.body.trim().split(RegExp(r'\s+')).length} words',
              style: const TextStyle(fontSize: 12)),
          onTap: () {
            setState(() => _selected = v);
            if (!wide) _showPreview(v);
          },
        );
      },
    );
    return Scaffold(
      appBar: AppBar(title: Text('History · ${widget.note.displayTitle}')),
      body: _versions.isEmpty
          ? const Center(
              child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                  'No saved versions yet. PowerNotes saves one every few minutes while you edit, and when you press Ctrl+S.',
                  textAlign: TextAlign.center),
            ))
          : wide
              ? Row(children: [
                  SizedBox(width: 320, child: list),
                  const VerticalDivider(width: 1),
                  Expanded(child: _selected == null ? const SizedBox() : _preview(_selected!)),
                ])
              : list,
    );
  }

  void _showPreview(NoteVersion v) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => Scaffold(appBar: AppBar(title: const Text('Version')), body: _preview(v)),
    ));
  }

  Widget _preview(NoteVersion v) => Column(children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (v.title.isNotEmpty)
                Text(v.title, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              MarkdownView(text: v.body, onToggleTask: (_) {}, onWikiLink: (_) {}),
            ]),
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: FilledButton.icon(
              onPressed: () => _restore(v),
              icon: const Icon(Icons.restore),
              label: const Text('Restore this version'),
            ),
          ),
        ),
      ]);
}
