import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../models/note.dart';

/// Reminders live inside note text, on any line:
///   - [ ] Call Pastor Ben @remind(2026-12-01 09:00)
///   Submit lesson plan @due(2026-12-03)
/// They are parsed when a note is saved and scheduled as local notifications.
class ReminderService {
  static final _re =
      RegExp(r'@(?:remind|due)\((\d{4}-\d{2}-\d{2})(?:[ T](\d{1,2}:\d{2}))?\)');
  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  Future<void> init() async {
    try {
      tzdata.initializeTimeZones();
      final offset = DateTime.now().timeZoneOffset;
      // Pick a fixed-offset zone matching the device (Philippines = +8, no DST).
      final match = tz.timeZoneDatabase.locations.values.firstWhere(
          (l) => l.currentTimeZone.offset == offset,
          orElse: () => tz.UTC);
      tz.setLocalLocation(match);
      const settings = InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        linux: LinuxInitializationSettings(defaultActionName: 'Open'),
        windows: WindowsInitializationSettings(
          appName: 'PowerNotes',
          appUserModelId: 'com.eirencaleb.powernotes',
          guid: '6d1f2b0e-8f8a-4d57-9a43-2b6f1d1f9c21',
        ),
      );
      await _plugin.initialize(settings: settings);
      if (Platform.isAndroid) {
        final android = _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
        await android?.requestNotificationsPermission();
        await android?.requestExactAlarmsPermission();
      }
      _ready = true;
    } catch (_) {
      _ready = false;
    }
  }

  static List<Reminder> parse(Note n) {
    final out = <Reminder>[];
    for (final line in n.body.split('\n')) {
      final m = _re.firstMatch(line);
      if (m == null) continue;
      if (line.trimLeft().startsWith(RegExp(r'[-*] \[[xX]\]'))) continue; // done
      final date = m.group(1)!;
      final time = m.group(2) ?? '08:00';
      final due = DateTime.tryParse('${date}T${time.padLeft(5, '0')}:00');
      if (due == null) continue;
      final text = line
          .replaceAll(_re, '')
          .replaceAll(RegExp(r'^\s*[-*]\s*(\[[ xX]\])?\s*'), '')
          .trim();
      out.add(Reminder(
          noteUuid: n.uuid, noteTitle: n.displayTitle, text: text, dueAt: due));
    }
    return out;
  }

  static List<Reminder> upcoming(List<Note> notes) {
    final all = <Reminder>[];
    for (final n in notes) {
      all.addAll(parse(n));
    }
    all.sort((a, b) => a.dueAt.compareTo(b.dueAt));
    return all;
  }

  int _id(String noteUuid, int i) => (noteUuid.hashCode & 0x7ffffff) * 16 + i;

  Future<void> scheduleFor(Note n) async {
    if (!_ready || Platform.isLinux) return;
    for (var i = 0; i < 16; i++) {
      await _plugin.cancel(id: _id(n.uuid, i));
    }
    if (n.deleted) return;
    final list = parse(n).where((r) => r.dueAt.isAfter(DateTime.now())).take(16).toList();
    for (var i = 0; i < list.length; i++) {
      final r = list[i];
      try {
        await _plugin.zonedSchedule(
          id: _id(n.uuid, i),
          title: r.noteTitle,
          body: r.text.isEmpty ? 'Reminder' : r.text,
          scheduledDate: tz.TZDateTime.from(r.dueAt, tz.local),
          notificationDetails: const NotificationDetails(
            android: AndroidNotificationDetails('reminders', 'Reminders',
                importance: Importance.high, priority: Priority.high),
            windows: WindowsNotificationDetails(),
          ),
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          payload: n.uuid,
        );
      } catch (_) {
        // Exact alarms may be refused; the Reminders view still lists them.
      }
    }
  }
}
