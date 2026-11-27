import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/note.dart';
import '../services/desktop_service.dart';
import '../services/notes_store.dart';
import '../widgets/dialogs.dart';
import '../widgets/note_editor.dart';
import '../widgets/note_list.dart';
import '../widgets/sidebar.dart';
import 'settings_screen.dart';

/// Responsive shell.
///  - Laptop (wide): sidebar | note list | editor with tabs
///  - Tablet: note list | editor, sidebar in a drawer
///  - Phone: note list, editor opens full screen
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> {
  final _scaffold = GlobalKey<ScaffoldState>();
  bool _focus = false;
  PendingAction _pending = PendingAction.none;
  String? _pendingFor;

  bool get _isPhone => MediaQuery.of(context).size.width < 700;

  Future<void> newNote({
    String body = '',
    String title = '',
    bool startVoice = false,
    bool startScan = false,
  }) async {
    final store = context.read<NotesStore>();
    if (store.filter == NoteFilter.trash || store.filter == NoteFilter.reminders) {
      store.setFilter(NoteFilter.all);
    }
    final n = await store.create(title: title, body: body);
    _pending = startVoice
        ? PendingAction.voice
        : startScan
            ? PendingAction.scan
            : PendingAction.none;
    _pendingFor = n.uuid;
    if (mounted) openNote(n);
  }

  Future<void> newFromTemplate() async {
    final t = await pickTemplate(context);
    if (t == null) return;
    await newNote(title: fillTemplate(t.title).trim(), body: fillTemplate(t.body));
  }

  PendingAction _takePending(String uuid) {
    if (_pendingFor != uuid) return PendingAction.none;
    final p = _pending;
    _pending = PendingAction.none;
    _pendingFor = null;
    return p;
  }

  void openNote(Note n) {
    final store = context.read<NotesStore>();
    store.open(n.uuid);
    if (_isPhone) {
      final action = _takePending(n.uuid);
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => Scaffold(
          body: NoteEditor(
            uuid: n.uuid,
            pendingAction: action,
            showBack: true,
            onOpenNote: (other) {
              Navigator.of(context).pop();
              openNote(other);
            },
          ),
        ),
      )).then((_) => store.closeTab(n.uuid));
    }
  }

  void _openSettings() {
    if (_scaffold.currentState?.isDrawerOpen ?? false) Navigator.of(context).pop();
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
  }

  Future<void> _toggleFocus() async {
    setState(() => _focus = !_focus);
    await DesktopService.setFullScreen(_focus);
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final store = context.watch<NotesStore>();
    final showSidebar = w >= 1100 && !_focus;
    final showList = w >= 700 && !_focus;

    final list = NoteList(
      onOpen: openNote,
      onNew: () => newNote(),
      onNewFromTemplate: newFromTemplate,
      leading: showSidebar
          ? null
          : IconButton(
              icon: const Icon(Icons.menu),
              onPressed: () => _scaffold.currentState?.openDrawer(),
            ),
    );

    final body = w < 700
        ? list
        : Row(children: [
            if (showSidebar) SizedBox(width: 250, child: Sidebar(onOpenSettings: _openSettings)),
            if (showList) ...[
              SizedBox(width: w >= 1100 ? 330 : 300, child: list),
              const VerticalDivider(width: 1),
            ],
            Expanded(child: _editorArea(store)),
          ]);

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyN, control: true): () => newNote(),
        const SingleActivator(LogicalKeyboardKey.keyN, control: true, shift: true):
            newFromTemplate,
        const SingleActivator(LogicalKeyboardKey.keyW, control: true): () {
          if (store.activeUuid != null) store.closeTab(store.activeUuid!);
        },
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          key: _scaffold,
          drawer: showSidebar
              ? null
              : Drawer(
                  width: 280,
                  child: Sidebar(
                    onOpenSettings: _openSettings,
                    onPicked: () => Navigator.of(context).pop(),
                  ),
                ),
          floatingActionButton: w < 700
              ? FloatingActionButton(
                  onPressed: () => newNote(),
                  child: const Icon(Icons.edit_outlined),
                )
              : null,
          body: body,
        ),
      ),
    );
  }

  Widget _editorArea(NotesStore store) {
    final scheme = Theme.of(context).colorScheme;
    final active = store.activeNote;
    return SafeArea(
      left: false,
      child: Column(children: [
        if (store.openTabs.length > 1 && !_focus)
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              children: [
                for (final uuid in store.openTabs)
                  if (store.byUuid(uuid) != null)
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Material(
                        color: uuid == store.activeUuid
                            ? scheme.primaryContainer
                            : scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(8),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: () => store.open(uuid),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(12, 0, 4, 0),
                            child: Row(children: [
                              ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 160),
                                child: Text(store.byUuid(uuid)!.displayTitle,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 13)),
                              ),
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                iconSize: 14,
                                icon: const Icon(Icons.close),
                                onPressed: () => store.closeTab(uuid),
                              ),
                            ]),
                          ),
                        ),
                      ),
                    ),
              ],
            ),
          ),
        Expanded(
          child: active == null
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.bolt, size: 56, color: scheme.primary.withValues(alpha: 0.5)),
                    const SizedBox(height: 12),
                    Text('Pick a note or start a new one',
                        style: TextStyle(color: scheme.onSurfaceVariant)),
                    const SizedBox(height: 4),
                    Text('Ctrl+N new note · Ctrl+Alt+N quick note from anywhere',
                        style: TextStyle(fontSize: 12, color: scheme.outline)),
                  ]),
                )
              : NoteEditor(
                  key: ValueKey(active.uuid),
                  uuid: active.uuid,
                  pendingAction: _takePending(active.uuid),
                  focusMode: _focus,
                  onToggleFocus: _toggleFocus,
                  onOpenNote: openNote,
                ),
        ),
      ]),
    );
  }
}
