import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// App settings, saved in shared_preferences.
class Settings extends ChangeNotifier {
  Settings(this._p);
  final SharedPreferences _p;

  static Future<Settings> load() async =>
      Settings(await SharedPreferences.getInstance());

  // ---------- look ----------
  ThemeMode get themeMode =>
      ThemeMode.values[_p.getInt('themeMode') ?? ThemeMode.system.index];
  set themeMode(ThemeMode m) {
    _p.setInt('themeMode', m.index);
    notifyListeners();
  }

  static const accents = <String, Color>{
    'Indigo': Color(0xFF4F46E5),
    'Teal': Color(0xFF0D9488),
    'Rose': Color(0xFFE11D48),
    'Amber': Color(0xFFD97706),
    'Slate': Color(0xFF475569),
    'Green': Color(0xFF16A34A),
  };
  String get accentName => _p.getString('accent') ?? 'Indigo';
  Color get accent => accents[accentName] ?? accents['Indigo']!;
  set accentName(String v) {
    _p.setString('accent', v);
    notifyListeners();
  }

  double get editorFontSize => _p.getDouble('fontSize') ?? 16;
  set editorFontSize(double v) {
    _p.setDouble('fontSize', v);
    notifyListeners();
  }

  // ---------- sync ----------
  String get serverUrl => _p.getString('serverUrl') ?? '';
  set serverUrl(String v) {
    var url = v.trim();
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    _p.setString('serverUrl', url);
    notifyListeners();
  }

  String get token => _p.getString('token') ?? '';
  String get email => _p.getString('email') ?? '';
  bool get signedIn => serverUrl.isNotEmpty && token.isNotEmpty;

  void setSession(String email, String token) {
    _p.setString('email', email);
    _p.setString('token', token);
    notifyListeners();
  }

  void signOut() {
    _p.remove('token');
    _p.remove('lastSyncAt');
    notifyListeners();
  }

  int get lastSyncAt => _p.getInt('lastSyncAt') ?? 0;
  set lastSyncAt(int v) => _p.setInt('lastSyncAt', v);

  // ---------- end-to-end encryption ----------
  bool get encryptionEnabled => _p.getBool('e2e') ?? false;
  String? get encryptionKey => _p.getString('e2eKey');
  void setEncryption(bool enabled, String? keyB64) {
    _p.setBool('e2e', enabled);
    if (keyB64 == null) {
      _p.remove('e2eKey');
    } else {
      _p.setString('e2eKey', keyB64);
    }
    notifyListeners();
  }

  // ---------- lock ----------
  bool get lockEnabled => _p.getString('pinHash') != null;
  bool get useBiometrics => _p.getBool('biometrics') ?? true;
  set useBiometrics(bool v) {
    _p.setBool('biometrics', v);
    notifyListeners();
  }

  /// Lock the whole app (true) or only notes marked private (false).
  bool get lockWholeApp => _p.getBool('lockWholeApp') ?? false;
  set lockWholeApp(bool v) {
    _p.setBool('lockWholeApp', v);
    notifyListeners();
  }

  String _hash(String pin) {
    final salt = _p.getString('pinSalt') ??
        DateTime.now().microsecondsSinceEpoch.toString();
    _p.setString('pinSalt', salt);
    return sha256.convert(utf8.encode('$salt:$pin')).toString();
  }

  void setPin(String? pin) {
    if (pin == null) {
      _p.remove('pinHash');
      _p.remove('pinSalt');
    } else {
      _p.remove('pinSalt');
      _p.setString('pinHash', _hash(pin));
    }
    notifyListeners();
  }

  bool checkPin(String pin) => _p.getString('pinHash') == _hash(pin);

  // ---------- misc ----------
  String get bibleTranslation => _p.getString('bible') ?? 'kjv';
  set bibleTranslation(String v) {
    _p.setString('bible', v);
    notifyListeners();
  }

  String get quickHotkeyLabel => 'Ctrl + Alt + N';
}
