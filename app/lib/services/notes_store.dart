import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../data/db.dart';
import '../models/note.dart';

enum NoteFilter { all, pinned, folder, tag, trash, reminders }

/// Holds notes and folders in memory and writes every change to SQLite first.
class NotesStore extends ChangeNotifier {
  NotesStore(this.db);
  final AppDb db;
  static const _uuid = Uuid();

  List<Note> _notes = [];
  List<Note> _trash = [];
  List<Folder> folders = [];

  NoteFilter filter = NoteFilter.all;
  String? filterFolder;
  String? filterTag;
  String query = '';

  /// Notes open as tabs (desktop) and the active one.
  final List<String> openTabs = [];
  String? activeUuid;

  /// Called after any local change, so sync can be scheduled.
  VoidCallback? onLocalChange;

  /// Called after a note is saved, so reminders can be rescheduled.
  void Function(Note note)? onNoteSaved;

  int get _now => DateTime.now().millisecondsSinceEpoch;

  Future<void> load() async {
    _notes = await db.allNotes();
    _trash = await db.trashedNotes();
    folders = await db.allFolders();
    notifyListeners();
  }

  List<Note> get allNotes => List.unmodifiable(_notes);

  Note? byUuid(String? uuid) {
    if (uuid == null) return null;
    for (final n in _notes) {
      if (n.uuid == uuid) return n;
    }
    return null;
  }

  Note? get activeNote => byUuid(activeUuid);

  List<String> get allTags {
    final s = <String>{};
    for (final n in _notes) {
      s.addAll(n.tags);
    }
    final list = s.toList()..sort();
    return list;
  }

  String folderName(String? uuid) {
    for (final f in folders) {
      if (f.uuid == uuid) return f.name;
    }
    return '';
  }

  int countInFolder(String uuid) => _notes.where((n) => n.folderUuid == uuid).length;

  /// The list shown in the middle column, after filter and search.
  List<Note> get visibleNotes {
    Iterable<Note> list = filter == NoteFilter.trash ? _trash : _notes;
    switch (filter) {
      case NoteFilter.pinned:
        list = list.where((n) => n.pinned);
      case NoteFilter.folder:
        list = list.where((n) => n.folderUuid == filterFolder);
      case NoteFilter.tag:
        list = list.where((n) => n.tags.contains(filterTag));
      default:
        break;
    }
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return list.toList();
    final terms = q.split(RegExp(r'\s+'));
    final scored = <MapEntry<Note, int>>[];
    for (final n in list) {
      final title = n.displayTitle.toLowerCase();
      final body = n.body.toLowerCase();
      final tags = n.tags.join(' ');
      var score = 0;
      var all = true;
      for (final t in terms) {
        final inTitle = title.contains(t);
        final inBody = body.contains(t);
        final inTags = tags.contains(t);
        if (!inTitle && !inBody && !inTags) {
          all = false;
          break;
        }
        score += (inTitle ? 10 : 0) + (inTags ? 5 : 0) + (inBody ? 1 : 0);
      }
      if (all) scored.add(MapEntry(n, score));
    }
    scored.sort((a, b) {
      final c = b.value.compareTo(a.value);
      return c != 0 ? c : b.key.updatedAt.compareTo(a.key.updatedAt);
    });
    return scored.map((e) => e.key).toList();
  }

  /// Short snippet around the first search hit, for the results list.
  String snippetFor(Note n) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return n.preview;
    final first = q.split(RegExp(r'\s+')).first;
    final i = n.body.toLowerCase().indexOf(first);
    if (i < 0) return n.preview;
    final start = (i - 40).clamp(0, n.body.length);
    final end = (i + 100).clamp(0, n.body.length);
    return '${start > 0 ? '…' : ''}${n.body.substring(start, end).replaceAll('\n', ' ')}…';
  }

  void setFilter(NoteFilter f, {String? folder, String? tag}) {
    filter = f;
    filterFolder = folder;
    filterTag = tag;
    notifyListeners();
  }

  void setQuery(String q) {
    query = q;
    notifyListeners();
  }

  // ---------- tabs ----------
  void open(String uuid) {
    if (!openTabs.contains(uuid)) openTabs.add(uuid);
    activeUuid = uuid;
    notifyListeners();
  }

  void closeTab(String uuid) {
    final i = openTabs.indexOf(uuid);
    openTabs.remove(uuid);
    if (activeUuid == uuid) {
      activeUuid = openTabs.isEmpty ? null : openTabs[(i - 1).clamp(0, openTabs.length - 1)];
    }
    notifyListeners();
  }

  // ---------- notes ----------
  Future<Note> create({String title = '', String body = '', String? folderUuid}) async {
    final now = _now;
    final n = Note(
      uuid: _uuid.v4(),
      title: title,
      body: body,
      folderUuid: folderUuid ?? (filter == NoteFilter.folder ? filterFolder : null),
      tags: filter == NoteFilter.tag && filterTag != null ? [filterTag!] : [],
      createdAt: now,
      updatedAt: now,
    );
    await db.upsertNote(n);
    _notes.insert(0, n);
    _sort();
    notifyListeners();
    onLocalChange?.call();
    return n;
  }

  /// Saves a note. Takes a version snapshot at most every 5 minutes of editing,
  /// so history can go back across days without filling the disk.
  Future<void> save(Note n, {bool forceVersion = false}) async {
    n.updatedAt = _now;
    n.pending = true;
    await db.upsertNote(n);
    final last = await db.latestVersion(n.uuid);
    final stale = last == null || _now - last.createdAt > 5 * 60 * 1000;
    final changed = last == null || last.body != n.body || last.title != n.title;
    if ((stale || forceVersion) && changed) await db.addVersion(n);
    _sort();
    notifyListeners();
    onNoteSaved?.call(n);
    onLocalChange?.call();
  }

  Future<void> snapshot(Note n) async {
    final last = await db.latestVersion(n.uuid);
    if (last == null || last.body != n.body || last.title != n.title) {
      await db.addVersion(n);
    }
  }

  Future<void> togglePin(Note n) async {
    n.pinned = !n.pinned;
    await save(n);
  }

  Future<void> trash(Note n) async {
    n.deleted = true;
    await save(n);
    _notes.remove(n);
    _trash.insert(0, n);
    closeTab(n.uuid);
    notifyListeners();
  }

  Future<void> restore(Note n) async {
    n.deleted = false;
    await save(n);
    _trash.remove(n);
    _notes.add(n);
    _sort();
    notifyListeners();
  }

  /// Permanently removes from this device. It stays deleted on the server.
  Future<void> purge(Note n) async {
    await db.purgeNote(n.uuid);
    _trash.remove(n);
    notifyListeners();
  }

  Future<void> emptyTrash() async {
    for (final n in List<Note>.from(_trash)) {
      await db.purgeNote(n.uuid);
    }
    _trash.clear();
    notifyListeners();
  }

  void _sort() => _notes.sort((a, b) {
        if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
        return b.updatedAt.compareTo(a.updatedAt);
      });

  // ---------- wiki links ----------
  Note? findByTitle(String title) {
    final t = title.trim().toLowerCase();
    for (final n in _notes) {
      if (n.displayTitle.toLowerCase() == t) return n;
    }
    return null;
  }

  List<Note> backlinks(Note target) {
    final t = target.displayTitle.toLowerCase();
    return _notes
        .where((n) => n.uuid != target.uuid && n.body.toLowerCase().contains('[[$t]]'))
        .toList();
  }

  // ---------- folders ----------
  Future<Folder> createFolder(String name) async {
    final f = Folder(uuid: _uuid.v4(), name: name.trim(), updatedAt: _now);
    await db.upsertFolder(f);
    folders = await db.allFolders();
    notifyListeners();
    onLocalChange?.call();
    return f;
  }

  Future<void> renameFolder(Folder f, String name) async {
    f
      ..name = name.trim()
      ..updatedAt = _now
      ..pending = true;
    await db.upsertFolder(f);
    folders = await db.allFolders();
    notifyListeners();
    onLocalChange?.call();
  }

  Future<void> deleteFolder(Folder f) async {
    f
      ..deleted = true
      ..updatedAt = _now
      ..pending = true;
    await db.upsertFolder(f);
    for (final n in _notes.where((n) => n.folderUuid == f.uuid).toList()) {
      n.folderUuid = null;
      await save(n);
    }
    folders = await db.allFolders();
    if (filterFolder == f.uuid) filter = NoteFilter.all;
    notifyListeners();
    onLocalChange?.call();
  }

  /// Applies rows pulled from the server (latest updated_at wins).
  Future<void> applyRemote(List<Note> notes, List<Folder> remoteFolders) async {
    for (final f in remoteFolders) {
      final local = await db.folder(f.uuid);
      if (local != null && local.pending && local.updatedAt > f.updatedAt) continue;
      await db.upsertFolder(f);
    }
    for (final n in notes) {
      final local = await db.note(n.uuid);
      if (local != null && local.pending && local.updatedAt > n.updatedAt) continue;
      if (local != null && local.body != n.body) await db.addVersion(local);
      await db.upsertNote(n);
      onNoteSaved?.call(n);
    }
    await load();
  }
}
