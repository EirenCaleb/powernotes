import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/note.dart';
import '../services/notes_store.dart';
import '../services/reminder_service.dart';
import 'dialogs.dart';

String friendlyDate(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  final now = DateTime.now();
  if (d.year == now.year && d.month == now.month && d.day == now.day) {
    return DateFormat.jm().format(d);
  }
  if (now.difference(d).inDays < 7) return DateFormat.E().format(d);
  return DateFormat.yMMMd().format(d);
}

/// Middle column: search box and the list of notes.
class NoteList extends StatefulWidget {
  const NoteList({
    super.key,
    required this.onOpen,
    required this.onNew,
    required this.onNewFromTemplate,
    this.leading,
  });
  final void Function(Note n) onOpen;
  final VoidCallback onNew;
  final VoidCallback onNewFromTemplate;
  final Widget? leading;

  @override
  State<NoteList> createState() => _NoteListState();
}

class _NoteListState extends State<NoteList> {
  final _search = TextEditingController();

  String _title(NotesStore s) => switch (s.filter) {
        NoteFilter.all => 'All notes',
        NoteFilter.pinned => 'Pinned',
        NoteFilter.folder => s.folderName(s.filterFolder),
        NoteFilter.tag => '#${s.filterTag}',
        NoteFilter.trash => 'Trash',
        NoteFilter.reminders => 'Reminders',
      };

  @override
  Widget build(BuildContext context) {
    final store = context.watch<NotesStore>();
    final scheme = Theme.of(context).colorScheme;
    final notes = store.visibleNotes;

    return SafeArea(
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 10, 8, 4),
          child: Row(children: [
            if (widget.leading != null) widget.leading!,
            const SizedBox(width: 8),
            Expanded(
              child: Text(_title(store),
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            ),
            if (store.filter == NoteFilter.trash && notes.isNotEmpty)
              TextButton(
                onPressed: () async {
                  if (await confirm(context, 'Empty trash?',
                      'Notes in the trash are removed from this device for good.',
                      ok: 'Empty')) {
                    await store.emptyTrash();
                  }
                },
                child: const Text('Empty'),
              )
            else ...[
              IconButton(
                tooltip: 'New from template',
                icon: const Icon(Icons.dashboard_customize_outlined),
                onPressed: widget.onNewFromTemplate,
              ),
              IconButton.filledTonal(
                tooltip: 'New note (Ctrl+N)',
                icon: const Icon(Icons.edit_outlined),
                onPressed: widget.onNew,
              ),
            ],
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
          child: TextField(
            controller: _search,
            onChanged: store.setQuery,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search, size: 20),
              hintText: 'Search all notes',
              suffixIcon: store.query.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () {
                        _search.clear();
                        store.setQuery('');
                      },
                    ),
            ),
          ),
        ),
        Expanded(
          child: store.filter == NoteFilter.reminders
              ? _RemindersView(onOpen: widget.onOpen)
              : notes.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(
                          store.query.isNotEmpty
                              ? 'No notes match "${store.query}".'
                              : store.filter == NoteFilter.trash
                                  ? 'Trash is empty.'
                                  : 'No notes yet. Tap the pencil to start one.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: scheme.onSurfaceVariant),
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 80),
                      itemCount: notes.length,
                      itemBuilder: (_, i) => _NoteTile(
                        note: notes[i],
                        selected: store.activeUuid == notes[i].uuid,
                        onTap: () => widget.onOpen(notes[i]),
                      ),
                    ),
        ),
      ]),
    );
  }
}

class _NoteTile extends StatelessWidget {
  const _NoteTile({required this.note, required this.selected, required this.onTap});
  final Note note;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final store = context.read<NotesStore>();
    final scheme = Theme.of(context).colorScheme;
    final isTrash = note.deleted;
    final hidden = note.private;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: selected ? scheme.primaryContainer.withValues(alpha: 0.55) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: isTrash ? null : onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    if (note.pinned)
                      Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: Icon(Icons.push_pin, size: 14, color: scheme.primary),
                      ),
                    if (hidden)
                      Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: Icon(Icons.lock, size: 14, color: scheme.tertiary),
                      ),
                    Expanded(
                      child: Text(note.displayTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                    ),
                  ]),
                  const SizedBox(height: 3),
                  Text(
                    hidden ? 'Private note' : store.snippetFor(note),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant, height: 1.3),
                  ),
                  const SizedBox(height: 5),
                  Wrap(spacing: 6, runSpacing: 4, children: [
                    Text(friendlyDate(note.updatedAt),
                        style: TextStyle(fontSize: 11.5, color: scheme.outline)),
                    if (note.folderUuid != null && store.folderName(note.folderUuid).isNotEmpty)
                      Text('· ${store.folderName(note.folderUuid)}',
                          style: TextStyle(fontSize: 11.5, color: scheme.outline)),
                    for (final t in note.tags.take(3))
                      Text('#$t', style: TextStyle(fontSize: 11.5, color: scheme.primary)),
                  ]),
                ]),
              ),
              if (isTrash) ...[
                IconButton(
                  tooltip: 'Restore',
                  icon: const Icon(Icons.restore, size: 20),
                  onPressed: () => store.restore(note),
                ),
                IconButton(
                  tooltip: 'Delete forever',
                  icon: const Icon(Icons.delete_forever_outlined, size: 20),
                  onPressed: () => store.purge(note),
                ),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}

class _RemindersView extends StatelessWidget {
  const _RemindersView({required this.onOpen});
  final void Function(Note n) onOpen;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<NotesStore>();
    final scheme = Theme.of(context).colorScheme;
    final list = ReminderService.upcoming(store.allNotes);
    if (list.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            'No reminders yet.\n\nAdd one to any line with the alarm button in the editor, '
            'or type @remind(2026-12-01 09:00) or @due(2026-12-01).',
            textAlign: TextAlign.center,
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
        ),
      );
    }
    final now = DateTime.now();
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 80),
      itemCount: list.length,
      itemBuilder: (_, i) {
        final r = list[i];
        final overdue = r.dueAt.isBefore(now);
        return ListTile(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          leading: Icon(overdue ? Icons.alarm_off : Icons.alarm,
              color: overdue ? scheme.error : scheme.primary),
          title: Text(r.text.isEmpty ? r.noteTitle : r.text,
              maxLines: 2, overflow: TextOverflow.ellipsis),
          subtitle: Text(
              '${DateFormat('EEE, MMM d · h:mm a').format(r.dueAt)}${overdue ? ' · overdue' : ''}\n${r.noteTitle}'),
          isThreeLine: true,
          onTap: () {
            final n = store.byUuid(r.noteUuid);
            if (n != null) onOpen(n);
          },
        );
      },
    );
  }
}
