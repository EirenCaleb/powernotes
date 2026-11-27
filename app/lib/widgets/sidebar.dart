import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/note.dart';
import '../services/notes_store.dart';
import '../services/sync_service.dart';
import 'dialogs.dart';

/// Left navigation: views, folders, tags, trash, settings and sync status.
class Sidebar extends StatelessWidget {
  const Sidebar({super.key, required this.onOpenSettings, this.onPicked});
  final VoidCallback onOpenSettings;
  final VoidCallback? onPicked; // closes the drawer on phones

  @override
  Widget build(BuildContext context) {
    final store = context.watch<NotesStore>();
    final scheme = Theme.of(context).colorScheme;

    Widget item(IconData icon, String label, bool selected, VoidCallback onTap,
        {int? count, VoidCallback? onMenu}) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
        child: Material(
          color: selected ? scheme.primaryContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () {
              onTap();
              onPicked?.call();
            },
            onLongPress: onMenu,
            onSecondaryTap: onMenu,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              child: Row(children: [
                Icon(icon,
                    size: 19,
                    color: selected ? scheme.onPrimaryContainer : scheme.onSurfaceVariant),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(label,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                          color: selected ? scheme.onPrimaryContainer : scheme.onSurface)),
                ),
                if (count != null)
                  Text('$count',
                      style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
              ]),
            ),
          ),
        ),
      );
    }

    Widget header(String text, {VoidCallback? onAdd}) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 12, 4),
          child: Row(children: [
            Expanded(
              child: Text(text.toUpperCase(),
                  style: TextStyle(
                      fontSize: 11,
                      letterSpacing: 1.1,
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurfaceVariant)),
            ),
            if (onAdd != null)
              InkWell(
                onTap: onAdd,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(Icons.add, size: 18, color: scheme.onSurfaceVariant),
                ),
              ),
          ]),
        );

    Future<void> folderMenu(Folder f) async {
      final choice = await showModalBottomSheet<String>(
        context: context,
        builder: (c) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Rename folder'),
                onTap: () => Navigator.pop(c, 'rename')),
            ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('Delete folder (keeps its notes)'),
                onTap: () => Navigator.pop(c, 'delete')),
          ]),
        ),
      );
      if (!context.mounted) return;
      if (choice == 'rename') {
        final name = await promptText(context, 'Rename folder', initial: f.name);
        if (name != null && name.trim().isNotEmpty) await store.renameFolder(f, name);
      } else if (choice == 'delete') {
        await store.deleteFolder(f);
      }
    }

    return Container(
      color: Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF15171D)
          : const Color(0xFFEFF0F5),
      child: SafeArea(
        right: false,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 16, 8),
            child: Row(children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: scheme.primary,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(Icons.bolt, color: scheme.onPrimary, size: 20),
              ),
              const SizedBox(width: 10),
              const Text('PowerNotes',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            ]),
          ),
          Expanded(
            child: ListView(padding: EdgeInsets.zero, children: [
              const SizedBox(height: 6),
              item(Icons.notes_rounded, 'All notes', store.filter == NoteFilter.all,
                  () => store.setFilter(NoteFilter.all),
                  count: store.allNotes.length),
              item(Icons.push_pin_outlined, 'Pinned', store.filter == NoteFilter.pinned,
                  () => store.setFilter(NoteFilter.pinned),
                  count: store.allNotes.where((n) => n.pinned).length),
              item(Icons.alarm, 'Reminders', store.filter == NoteFilter.reminders,
                  () => store.setFilter(NoteFilter.reminders)),
              header('Folders', onAdd: () async {
                final name = await promptText(context, 'New folder');
                if (name != null && name.trim().isNotEmpty) await store.createFolder(name);
              }),
              for (final f in store.folders)
                item(
                  Icons.folder_outlined,
                  f.name,
                  store.filter == NoteFilter.folder && store.filterFolder == f.uuid,
                  () => store.setFilter(NoteFilter.folder, folder: f.uuid),
                  count: store.countInFolder(f.uuid),
                  onMenu: () => folderMenu(f),
                ),
              if (store.folders.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
                  child: Text('Tap + to add a folder',
                      style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
                ),
              if (store.allTags.isNotEmpty) header('Tags'),
              for (final t in store.allTags)
                item(Icons.tag, t,
                    store.filter == NoteFilter.tag && store.filterTag == t,
                    () => store.setFilter(NoteFilter.tag, tag: t)),
              const SizedBox(height: 12),
              item(Icons.delete_outline, 'Trash', store.filter == NoteFilter.trash,
                  () => store.setFilter(NoteFilter.trash)),
              item(Icons.settings_outlined, 'Settings', false, onOpenSettings),
            ]),
          ),
          const SyncChip(),
        ]),
      ),
    );
  }
}

class SyncChip extends StatelessWidget {
  const SyncChip({super.key});

  @override
  Widget build(BuildContext context) {
    final sync = context.watch<SyncService>();
    final scheme = Theme.of(context).colorScheme;
    final (icon, text) = switch (sync.state) {
      SyncState.syncing => (Icons.sync, 'Syncing…'),
      SyncState.offline => (Icons.cloud_off_outlined, 'Offline, saved on device'),
      SyncState.error => (Icons.error_outline, sync.lastError ?? 'Sync error'),
      SyncState.signedOut => (Icons.cloud_outlined, 'Sync off (sign in in Settings)'),
      SyncState.idle => (
          Icons.cloud_done_outlined,
          sync.lastSynced == null ? 'Up to date' : 'Synced ${_ago(sync.lastSynced!)}'
        ),
    };
    return InkWell(
      onTap: sync.sync,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 16, 14),
        child: Row(children: [
          Icon(icon, size: 16, color: scheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
          ),
        ]),
      ),
    );
  }

  static String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inSeconds < 60) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes} min ago';
    return '${d.inHours} h ago';
  }
}
