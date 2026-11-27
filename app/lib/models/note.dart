/// A single note. Every syncable row carries a device-generated [uuid],
/// [updatedAt] (ms since epoch), a soft-delete flag and a sync status.
class Note {
  final String uuid;
  String title;
  String body;
  String? folderUuid;
  List<String> tags;
  bool pinned;
  bool private; // needs unlock to open
  int createdAt;
  int updatedAt;
  bool deleted;
  bool pending; // true = changed locally, not yet pushed

  Note({
    required this.uuid,
    this.title = '',
    this.body = '',
    this.folderUuid,
    List<String>? tags,
    this.pinned = false,
    this.private = false,
    required this.createdAt,
    required this.updatedAt,
    this.deleted = false,
    this.pending = true,
  }) : tags = tags ?? [];

  String get displayTitle {
    if (title.trim().isNotEmpty) return title.trim();
    final firstLine = body.trim().split('\n').first.replaceAll(RegExp(r'^#+\s*'), '');
    return firstLine.isEmpty ? 'Untitled' : firstLine;
  }

  String get preview {
    final text = body
        .replaceAll(RegExp(r'^\s*\|?[\s:|-]+\|?\s*$', multiLine: true), '')
        .replaceAll(RegExp(r'[#>*_`\[\]|]'), ' ')
        .replaceAll(RegExp(r'\s-\s'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return text.length > 140 ? '${text.substring(0, 140)}…' : text;
  }

  int get wordCount =>
      body.trim().isEmpty ? 0 : body.trim().split(RegExp(r'\s+')).length;

  /// Reading time in minutes at ~200 words per minute.
  int get readingMinutes => (wordCount / 200).ceil();

  static String encodeTags(List<String> tags) =>
      tags.isEmpty ? '' : ',${tags.join(',')},';

  static List<String> decodeTags(String? raw) => (raw ?? '')
      .split(',')
      .map((t) => t.trim())
      .where((t) => t.isNotEmpty)
      .toList();

  Map<String, Object?> toDb() => {
        'uuid': uuid,
        'title': title,
        'body': body,
        'folder_uuid': folderUuid,
        'tags': encodeTags(tags),
        'pinned': pinned ? 1 : 0,
        'private': private ? 1 : 0,
        'created_at': createdAt,
        'updated_at': updatedAt,
        'deleted': deleted ? 1 : 0,
        'sync_status': pending ? 0 : 1,
      };

  factory Note.fromDb(Map<String, Object?> r) => Note(
        uuid: r['uuid'] as String,
        title: (r['title'] as String?) ?? '',
        body: (r['body'] as String?) ?? '',
        folderUuid: r['folder_uuid'] as String?,
        tags: decodeTags(r['tags'] as String?),
        pinned: (r['pinned'] as int? ?? 0) == 1,
        private: (r['private'] as int? ?? 0) == 1,
        createdAt: r['created_at'] as int,
        updatedAt: r['updated_at'] as int,
        deleted: (r['deleted'] as int? ?? 0) == 1,
        pending: (r['sync_status'] as int? ?? 0) == 0,
      );

  /// Shape sent to / received from the PHP API.
  Map<String, Object?> toApi() => {
        'uuid': uuid,
        'title': title,
        'body': body,
        'folder_uuid': folderUuid,
        'tags': tags.join(','),
        'pinned': pinned ? 1 : 0,
        'private': private ? 1 : 0,
        'created_at': createdAt,
        'updated_at': updatedAt,
        'deleted': deleted ? 1 : 0,
      };

  factory Note.fromApi(Map<String, dynamic> j) => Note(
        uuid: j['uuid'] as String,
        title: (j['title'] ?? '') as String,
        body: (j['body'] ?? '') as String,
        folderUuid: j['folder_uuid'] as String?,
        tags: decodeTags(j['tags'] as String?),
        pinned: _asInt(j['pinned']) == 1,
        private: _asInt(j['private']) == 1,
        createdAt: _asInt(j['created_at']),
        updatedAt: _asInt(j['updated_at']),
        deleted: _asInt(j['deleted']) == 1,
        pending: false,
      );
}

int _asInt(Object? v) => v is int ? v : int.tryParse('$v') ?? 0;

class Folder {
  final String uuid;
  String name;
  int updatedAt;
  bool deleted;
  bool pending;

  Folder({
    required this.uuid,
    required this.name,
    required this.updatedAt,
    this.deleted = false,
    this.pending = true,
  });

  Map<String, Object?> toDb() => {
        'uuid': uuid,
        'name': name,
        'updated_at': updatedAt,
        'deleted': deleted ? 1 : 0,
        'sync_status': pending ? 0 : 1,
      };

  factory Folder.fromDb(Map<String, Object?> r) => Folder(
        uuid: r['uuid'] as String,
        name: r['name'] as String,
        updatedAt: r['updated_at'] as int,
        deleted: (r['deleted'] as int? ?? 0) == 1,
        pending: (r['sync_status'] as int? ?? 0) == 0,
      );

  Map<String, Object?> toApi() => {
        'uuid': uuid,
        'name': name,
        'updated_at': updatedAt,
        'deleted': deleted ? 1 : 0,
      };

  factory Folder.fromApi(Map<String, dynamic> j) => Folder(
        uuid: j['uuid'] as String,
        name: (j['name'] ?? '') as String,
        updatedAt: _asInt(j['updated_at']),
        deleted: _asInt(j['deleted']) == 1,
        pending: false,
      );
}

class NoteVersion {
  final int id;
  final String noteUuid;
  final String title;
  final String body;
  final int createdAt;

  NoteVersion({
    required this.id,
    required this.noteUuid,
    required this.title,
    required this.body,
    required this.createdAt,
  });

  factory NoteVersion.fromDb(Map<String, Object?> r) => NoteVersion(
        id: r['id'] as int,
        noteUuid: r['note_uuid'] as String,
        title: (r['title'] as String?) ?? '',
        body: (r['body'] as String?) ?? '',
        createdAt: r['created_at'] as int,
      );
}

class Reminder {
  final String noteUuid;
  final String noteTitle;
  final String text;
  final DateTime dueAt;

  Reminder({
    required this.noteUuid,
    required this.noteTitle,
    required this.text,
    required this.dueAt,
  });
}
