import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' show sqfliteFfiInit, databaseFactoryFfi;

import '../models/note.dart';

/// Local SQLite store. Everything is written here first (offline-first),
/// then pushed to the server by SyncService.
class AppDb {
  AppDb._(this.db);
  final Database db;

  static Future<AppDb> open() async {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }
    final dir = await getApplicationSupportDirectory();
    final path = p.join(dir.path, 'powernotes.db');
    final db = await openDatabase(
      path,
      version: 1,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE notes (
            uuid TEXT PRIMARY KEY,
            title TEXT NOT NULL DEFAULT '',
            body TEXT NOT NULL DEFAULT '',
            folder_uuid TEXT,
            tags TEXT NOT NULL DEFAULT '',
            pinned INTEGER NOT NULL DEFAULT 0,
            private INTEGER NOT NULL DEFAULT 0,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL,
            deleted INTEGER NOT NULL DEFAULT 0,
            sync_status INTEGER NOT NULL DEFAULT 0
          )''');
        await db.execute('CREATE INDEX idx_notes_updated ON notes(updated_at)');
        await db.execute('''
          CREATE TABLE folders (
            uuid TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            updated_at INTEGER NOT NULL,
            deleted INTEGER NOT NULL DEFAULT 0,
            sync_status INTEGER NOT NULL DEFAULT 0
          )''');
        await db.execute('''
          CREATE TABLE note_versions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            note_uuid TEXT NOT NULL,
            title TEXT NOT NULL DEFAULT '',
            body TEXT NOT NULL DEFAULT '',
            created_at INTEGER NOT NULL
          )''');
        await db.execute(
            'CREATE INDEX idx_versions_note ON note_versions(note_uuid, created_at)');
        await db.execute('''
          CREATE TABLE meta (
            key TEXT PRIMARY KEY,
            value TEXT
          )''');
      },
    );
    return AppDb._(db);
  }

  // ---------- notes ----------
  Future<List<Note>> allNotes() async {
    final rows = await db.query('notes',
        where: 'deleted = 0', orderBy: 'pinned DESC, updated_at DESC');
    return rows.map(Note.fromDb).toList();
  }

  Future<List<Note>> trashedNotes() async {
    final rows =
        await db.query('notes', where: 'deleted = 1', orderBy: 'updated_at DESC');
    return rows.map(Note.fromDb).toList();
  }

  Future<Note?> note(String uuid) async {
    final rows = await db.query('notes', where: 'uuid = ?', whereArgs: [uuid]);
    return rows.isEmpty ? null : Note.fromDb(rows.first);
  }

  Future<void> upsertNote(Note n) =>
      db.insert('notes', n.toDb(), conflictAlgorithm: ConflictAlgorithm.replace);

  Future<void> purgeNote(String uuid) async {
    await db.delete('notes', where: 'uuid = ?', whereArgs: [uuid]);
    await db.delete('note_versions', where: 'note_uuid = ?', whereArgs: [uuid]);
  }

  Future<List<Note>> pendingNotes() async {
    final rows = await db.query('notes', where: 'sync_status = 0');
    return rows.map(Note.fromDb).toList();
  }

  Future<void> markNotesSynced(List<String> uuids, Map<String, int> stamps) async {
    final batch = db.batch();
    for (final u in uuids) {
      // Only mark synced if not edited again since we read it.
      batch.update('notes', {'sync_status': 1},
          where: 'uuid = ? AND updated_at = ?', whereArgs: [u, stamps[u]]);
    }
    await batch.commit(noResult: true);
  }

  // ---------- folders ----------
  Future<List<Folder>> allFolders() async {
    final rows =
        await db.query('folders', where: 'deleted = 0', orderBy: 'name COLLATE NOCASE');
    return rows.map(Folder.fromDb).toList();
  }

  Future<Folder?> folder(String uuid) async {
    final rows = await db.query('folders', where: 'uuid = ?', whereArgs: [uuid]);
    return rows.isEmpty ? null : Folder.fromDb(rows.first);
  }

  Future<void> upsertFolder(Folder f) => db.insert('folders', f.toDb(),
      conflictAlgorithm: ConflictAlgorithm.replace);

  Future<List<Folder>> pendingFolders() async {
    final rows = await db.query('folders', where: 'sync_status = 0');
    return rows.map(Folder.fromDb).toList();
  }

  Future<void> markFoldersSynced(List<String> uuids, Map<String, int> stamps) async {
    final batch = db.batch();
    for (final u in uuids) {
      batch.update('folders', {'sync_status': 1},
          where: 'uuid = ? AND updated_at = ?', whereArgs: [u, stamps[u]]);
    }
    await batch.commit(noResult: true);
  }

  // ---------- version history ----------
  Future<void> addVersion(Note n) async {
    await db.insert('note_versions', {
      'note_uuid': n.uuid,
      'title': n.title,
      'body': n.body,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
    // Keep the newest 200 versions per note.
    await db.rawDelete('''
      DELETE FROM note_versions WHERE note_uuid = ? AND id NOT IN (
        SELECT id FROM note_versions WHERE note_uuid = ?
        ORDER BY created_at DESC LIMIT 200)''', [n.uuid, n.uuid]);
  }

  Future<NoteVersion?> latestVersion(String noteUuid) async {
    final rows = await db.query('note_versions',
        where: 'note_uuid = ?',
        whereArgs: [noteUuid],
        orderBy: 'created_at DESC',
        limit: 1);
    return rows.isEmpty ? null : NoteVersion.fromDb(rows.first);
  }

  Future<List<NoteVersion>> versions(String noteUuid) async {
    final rows = await db.query('note_versions',
        where: 'note_uuid = ?', whereArgs: [noteUuid], orderBy: 'created_at DESC');
    return rows.map(NoteVersion.fromDb).toList();
  }

  // ---------- meta ----------
  Future<String?> getMeta(String key) async {
    final rows = await db.query('meta', where: 'key = ?', whereArgs: [key]);
    return rows.isEmpty ? null : rows.first['value'] as String?;
  }

  Future<void> setMeta(String key, String value) => db.insert(
      'meta', {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace);
}
