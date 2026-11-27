import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:quick_actions/quick_actions.dart';

import 'data/api_client.dart';
import 'data/db.dart';
import 'screens/home_screen.dart';
import 'screens/lock_screen.dart';
import 'services/ai_service.dart';
import 'services/capture_service.dart';
import 'services/desktop_service.dart';
import 'services/lock_service.dart';
import 'services/notes_store.dart';
import 'services/reminder_service.dart';
import 'services/settings.dart';
import 'services/sync_service.dart';
import 'theme.dart';

final navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DesktopService.initWindow();

  final settings = await Settings.load();
  final db = await AppDb.open();
  final store = NotesStore(db);
  await store.load();
  final api = ApiClient(settings);
  final reminders = ReminderService();
  await reminders.init();
  store.onNoteSaved = reminders.scheduleFor;
  final sync = SyncService(db, store, settings, api);
  final lock = LockService(settings);
  final capture = CaptureService(api);

  runApp(MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: settings),
      ChangeNotifierProvider.value(value: store),
      ChangeNotifierProvider.value(value: sync),
      ChangeNotifierProvider.value(value: lock),
      Provider.value(value: api),
      Provider.value(value: reminders),
      Provider.value(value: capture),
      Provider.value(value: AiService(api)),
    ],
    child: const PowerNotesApp(),
  ));

  // Sync once at launch (quietly does nothing when not signed in).
  sync.sync();
}

class PowerNotesApp extends StatefulWidget {
  const PowerNotesApp({super.key});

  @override
  State<PowerNotesApp> createState() => _PowerNotesAppState();
}

class _PowerNotesAppState extends State<PowerNotesApp> with WidgetsBindingObserver {
  final _homeKey = GlobalKey<HomeScreenState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _initCapture());
  }

  void _initCapture() {
    final capture = context.read<CaptureService>();
    // Android: text shared from other apps becomes a new note.
    capture.listenForShares((text) => _homeKey.currentState?.newNote(body: text));

    // Android: long-press the app icon for quick actions.
    if (Platform.isAndroid) {
      const qa = QuickActions();
      qa.initialize((type) {
        final home = _homeKey.currentState;
        if (home == null) return;
        switch (type) {
          case 'new_note':
            home.newNote();
          case 'voice_note':
            home.newNote(startVoice: true);
          case 'scan_note':
            home.newNote(startScan: true);
        }
      });
      qa.setShortcutItems(const [
        ShortcutItem(type: 'new_note', localizedTitle: 'Quick note', icon: 'ic_launcher'),
        ShortcutItem(type: 'voice_note', localizedTitle: 'Voice note', icon: 'ic_launcher'),
        ShortcutItem(type: 'scan_note', localizedTitle: 'Scan to text', icon: 'ic_launcher'),
      ]);
    }

    // Laptop: Ctrl+Alt+N from anywhere opens a quick note.
    DesktopService.registerQuickNote(() async => _homeKey.currentState?.newNote());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final lock = context.read<LockService>();
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      lock.onPaused();
    } else if (state == AppLifecycleState.resumed) {
      lock.onResumed();
      context.read<SyncService>().sync();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<Settings>();
    final lock = context.watch<LockService>();
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'PowerNotes',
      debugShowCheckedModeBanner: false,
      themeMode: settings.themeMode,
      theme: buildTheme(settings.accent, Brightness.light),
      darkTheme: buildTheme(settings.accent, Brightness.dark),
      home: Stack(children: [
        HomeScreen(key: _homeKey),
        if (lock.appLocked) const Positioned.fill(child: LockScreen()),
      ]),
    );
  }
}
