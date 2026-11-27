import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

import '../data/api_client.dart';
import '../data/db.dart';
import '../models/note.dart';
import 'crypto_service.dart';
import 'notes_store.dart';
import 'settings.dart';

enum SyncState { idle, syncing, offline, error, signedOut }

/// Offline-first sync: push pending rows, then pull rows the server changed
/// since our last cursor. Latest updated_at wins on conflict.
class SyncService extends ChangeNotifier {
  SyncService(this.db, this.store, this.settings, this.api) {
    store.onLocalChange = _scheduleSoon;
    try {
      _conn = Connectivity().onConnectivityChanged.listen((r) {
        if (!r.contains(ConnectivityResult.none)) sync();
      }, onError: (_) {});
    } catch (_) {
      // No network monitor on this system; the 2-minute timer still syncs.
    }
    _timer = Timer.periodic(const Duration(minutes: 2), (_) => sync());
  }

  final AppDb db;
  final NotesStore store;
  final Settings settings;
  final ApiClient api;

  SyncState state = SyncState.idle;
  String? lastError;
  DateTime? lastSynced;
  StreamSubscription? _conn;
  Timer? _timer;
  Timer? _debounce;
  bool _running = false;

  void _scheduleSoon() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 5), sync);
  }

  Future<void> sync() async {
    if (_running) return;
    if (!settings.signedIn) {
      state = SyncState.signedOut;
      notifyListeners();
      return;
    }
    _running = true;
    state = SyncState.syncing;
    notifyListeners();
    try {
      final key = settings.encryptionEnabled ? settings.encryptionKey : null;

      // 1. Push
      final notes = await db.pendingNotes();
      final folders = await db.pendingFolders();
      if (notes.isNotEmpty || folders.isNotEmpty) {
        final payloadNotes = <Map<String, Object?>>[];
        for (final n in notes) {
          final m = n.toApi();
          if (key != null) {
            m['title'] = await CryptoService.encrypt(n.title, key);
            m['body'] = await CryptoService.encrypt(n.body, key);
          }
          payloadNotes.add(m);
        }
        await api.post('api_sync_push.php', {
          'notes': payloadNotes,
          'folders': folders.map((f) => f.toApi()).toList(),
        });
        await db.markNotesSynced(
            notes.map((n) => n.uuid).toList(), {for (final n in notes) n.uuid: n.updatedAt});
        await db.markFoldersSynced(folders.map((f) => f.uuid).toList(),
            {for (final f in folders) f.uuid: f.updatedAt});
      }

      // 2. Pull
      final data = await api.get(
          'api_sync_pull.php', {'since': settings.lastSyncAt.toString()}) as Map<String, dynamic>;
      final remoteNotes = <Note>[];
      for (final j in (data['notes'] as List? ?? [])) {
        final n = Note.fromApi(j as Map<String, dynamic>);
        if (CryptoService.isEncrypted(n.body) || CryptoService.isEncrypted(n.title)) {
          if (key == null) {
            throw ApiException(
                'Some notes are encrypted. Turn on encryption in Settings with your passphrase.');
          }
          n.title = await CryptoService.decrypt(n.title, key);
          n.body = await CryptoService.decrypt(n.body, key);
        }
        remoteNotes.add(n);
      }
      final remoteFolders = (data['folders'] as List? ?? [])
          .map((j) => Folder.fromApi(j as Map<String, dynamic>))
          .toList();
      if (remoteNotes.isNotEmpty || remoteFolders.isNotEmpty) {
        await store.applyRemote(remoteNotes, remoteFolders);
      }
      settings.lastSyncAt = (data['server_time'] as num).toInt();
      lastSynced = DateTime.now();
      lastError = null;
      state = SyncState.idle;
    } on ApiException catch (e) {
      lastError = e.message;
      state = e.status == 401 ? SyncState.signedOut : SyncState.error;
    } catch (e) {
      lastError = 'Offline or server unreachable';
      state = SyncState.offline;
      debugPrint('sync failed: $e');
    } finally {
      _running = false;
      notifyListeners();
    }
  }

  /// Re-upload every note, e.g. after turning encryption on or off.
  Future<void> markAllPending() async {
    await db.db.update('notes', {'sync_status': 0});
    await db.db.update('folders', {'sync_status': 0});
    await sync();
  }

  @override
  void dispose() {
    _conn?.cancel();
    _timer?.cancel();
    _debounce?.cancel();
    super.dispose();
  }
}
