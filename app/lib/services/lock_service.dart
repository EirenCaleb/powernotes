import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';

import 'settings.dart';

/// PIN and fingerprint / Windows Hello lock.
class LockService extends ChangeNotifier {
  LockService(this.settings) {
    _unlocked = !(settings.lockEnabled && settings.lockWholeApp);
  }
  final Settings settings;
  final _auth = LocalAuthentication();

  bool _unlocked = true;
  bool get unlocked => _unlocked;

  /// Private notes unlocked in this session.
  bool privateUnlocked = false;
  DateTime? _backgroundedAt;

  bool get appLocked => settings.lockEnabled && settings.lockWholeApp && !_unlocked;

  Future<bool> biometricsAvailable() async {
    if (!(Platform.isAndroid || Platform.isWindows || Platform.isIOS)) return false;
    try {
      return await _auth.isDeviceSupported() && await _auth.canCheckBiometrics ||
          (Platform.isWindows && await _auth.isDeviceSupported());
    } catch (_) {
      return false;
    }
  }

  Future<bool> tryBiometric() async {
    if (!settings.useBiometrics || !await biometricsAvailable()) return false;
    try {
      final ok = await _auth.authenticate(
        localizedReason: 'Unlock PowerNotes',
        options: const AuthenticationOptions(stickyAuth: true),
      );
      if (ok) _unlock();
      return ok;
    } catch (_) {
      return false;
    }
  }

  bool tryPin(String pin) {
    final ok = settings.checkPin(pin);
    if (ok) _unlock();
    return ok;
  }

  void _unlock() {
    _unlocked = true;
    privateUnlocked = true;
    notifyListeners();
  }

  void lockNow() {
    if (!settings.lockEnabled) return;
    _unlocked = !settings.lockWholeApp;
    privateUnlocked = false;
    notifyListeners();
  }

  /// Lock again if the app was in the background for more than a minute.
  void onPaused() => _backgroundedAt = DateTime.now();
  void onResumed() {
    final t = _backgroundedAt;
    if (t != null && DateTime.now().difference(t) > const Duration(minutes: 1)) lockNow();
    _backgroundedAt = null;
  }
}
