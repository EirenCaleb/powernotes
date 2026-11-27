import 'dart:io';

import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:window_manager/legacy.dart';

/// Laptop extras: a global Ctrl+Alt+N hotkey that brings PowerNotes to the
/// front with a fresh quick note, even when another app has focus.
class DesktopService {
  static bool get isDesktop => Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  static Future<void> initWindow() async {
    if (!isDesktop) return;
    await windowManager.ensureInitialized();
    const opts = WindowOptions(
      size: Size(1280, 820),
      minimumSize: Size(420, 500),
      center: true,
      title: 'PowerNotes',
    );
    await windowManager.waitUntilReadyToShow(opts, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }

  static Future<void> registerQuickNote(Future<void> Function() onQuickNote) async {
    if (!isDesktop) return;
    try {
      await hotKeyManager.unregisterAll();
      final key = HotKey(
        key: PhysicalKeyboardKey.keyN,
        modifiers: [HotKeyModifier.control, HotKeyModifier.alt],
        scope: HotKeyScope.system,
      );
      await hotKeyManager.register(key, keyDownHandler: (_) async {
        await windowManager.show();
        await windowManager.restore();
        await windowManager.focus();
        await onQuickNote();
      });
    } catch (_) {
      // Hotkey taken by another app; the in-app shortcut still works.
    }
  }

  static Future<void> setFullScreen(bool on) async {
    if (!isDesktop) return;
    await windowManager.setFullScreen(on);
  }
}
