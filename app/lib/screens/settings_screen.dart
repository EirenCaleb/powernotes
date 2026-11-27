import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/api_client.dart';
import '../services/bible_service.dart';
import '../services/crypto_service.dart';
import '../services/lock_service.dart';
import '../services/settings.dart';
import '../services/sync_service.dart';
import '../widgets/dialogs.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<Settings>();
    final sync = context.watch<SyncService>();
    final scheme = Theme.of(context).colorScheme;

    Widget section(String title, List<Widget> children) => Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
              child: Text(title.toUpperCase(),
                  style: TextStyle(
                      fontSize: 11, letterSpacing: 1.1, fontWeight: FontWeight.w700,
                      color: scheme.primary)),
            ),
            Card(
              elevation: 0,
              margin: const EdgeInsets.symmetric(horizontal: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
              ),
              child: Column(children: children),
            ),
          ]),
        );

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(padding: const EdgeInsets.only(bottom: 40), children: [
            section('Appearance', [
              ListTile(
                leading: const Icon(Icons.dark_mode_outlined),
                title: const Text('Theme'),
                trailing: SegmentedButton<ThemeMode>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: ThemeMode.light, label: Text('Light')),
                    ButtonSegment(value: ThemeMode.system, label: Text('Auto')),
                    ButtonSegment(value: ThemeMode.dark, label: Text('Dark')),
                  ],
                  selected: {s.themeMode},
                  onSelectionChanged: (v) => s.themeMode = v.first,
                ),
              ),
              ListTile(
                leading: const Icon(Icons.palette_outlined),
                title: const Text('Accent color'),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Wrap(spacing: 10, children: [
                    for (final e in Settings.accents.entries)
                      GestureDetector(
                        onTap: () => s.accentName = e.key,
                        child: CircleAvatar(
                          radius: 15,
                          backgroundColor: e.value,
                          child: s.accentName == e.key
                              ? const Icon(Icons.check, size: 16, color: Colors.white)
                              : null,
                        ),
                      ),
                  ]),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.format_size),
                title: Text('Editor text size (${s.editorFontSize.round()})'),
                subtitle: Slider(
                  value: s.editorFontSize,
                  min: 12,
                  max: 26,
                  divisions: 14,
                  onChanged: (v) => s.editorFontSize = v,
                ),
              ),
            ]),
            section('Sync between laptop and phone', [
              if (!s.signedIn) ...[
                const ListTile(
                  leading: Icon(Icons.info_outline),
                  title: Text('Notes are saved on this device'),
                  subtitle: Text(
                      'Sign in to your PowerNotes server so the laptop and phone share the same notes.'),
                ),
                ListTile(
                  leading: const Icon(Icons.login),
                  title: const Text('Sign in or create account'),
                  onTap: () => showDialog(context: context, builder: (_) => const _SignInDialog()),
                ),
              ] else ...[
                ListTile(
                  leading: const Icon(Icons.account_circle_outlined),
                  title: Text(s.email),
                  subtitle: Text(s.serverUrl),
                  trailing: TextButton(
                    onPressed: () async {
                      if (await confirm(context, 'Sign out?',
                          'Your notes stay on this device. Sync stops until you sign in again.')) {
                        s.signOut();
                      }
                    },
                    child: const Text('Sign out'),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.sync),
                  title: const Text('Sync now'),
                  subtitle: Text(sync.lastError ??
                      (sync.lastSynced == null ? 'Not synced yet this session' : 'Last synced ${sync.lastSynced}')),
                  trailing: sync.state == SyncState.syncing
                      ? const SizedBox(
                          width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : null,
                  onTap: sync.sync,
                ),
              ],
              SwitchListTile(
                secondary: const Icon(Icons.enhanced_encryption_outlined),
                title: const Text('End-to-end encryption'),
                subtitle: const Text(
                    'Notes are encrypted on this device before upload. Use the same passphrase on every device. Shared links still publish plain text.'),
                value: s.encryptionEnabled,
                onChanged: (on) => _toggleEncryption(context, on),
              ),
            ]),
            section('Security', [
              SwitchListTile(
                secondary: const Icon(Icons.pin_outlined),
                title: const Text('PIN lock'),
                subtitle: Text(s.lockEnabled ? 'On' : 'Lock private notes or the whole app'),
                value: s.lockEnabled,
                onChanged: (on) async {
                  if (on) {
                    final pin = await promptText(context, 'Choose a PIN (4 to 8 digits)',
                        obscure: true);
                    if (pin == null || !RegExp(r'^\d{4,8}$').hasMatch(pin)) {
                      if (context.mounted && pin != null) toast(context, 'Use 4 to 8 digits.');
                      return;
                    }
                    if (!context.mounted) return;
                    final again = await promptText(context, 'Enter the PIN again', obscure: true);
                    if (again != pin) {
                      if (context.mounted) toast(context, 'PINs did not match.');
                      return;
                    }
                    s.setPin(pin);
                  } else {
                    final pin = await promptText(context, 'Enter your PIN to turn the lock off',
                        obscure: true);
                    if (pin != null && s.checkPin(pin)) {
                      s.setPin(null);
                    } else if (context.mounted) {
                      toast(context, 'Wrong PIN');
                    }
                  }
                },
              ),
              if (s.lockEnabled) ...[
                SwitchListTile(
                  secondary: const Icon(Icons.fingerprint),
                  title: const Text('Use fingerprint or Windows Hello'),
                  value: s.useBiometrics,
                  onChanged: (v) => s.useBiometrics = v,
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.phonelink_lock),
                  title: const Text('Lock the whole app'),
                  subtitle: const Text('Off: only notes you mark as locked need the PIN'),
                  value: s.lockWholeApp,
                  onChanged: (v) => s.lockWholeApp = v,
                ),
                ListTile(
                  leading: const Icon(Icons.lock_clock_outlined),
                  title: const Text('Lock now'),
                  onTap: () {
                    context.read<LockService>().lockNow();
                    Navigator.pop(context);
                  },
                ),
              ],
            ]),
            section('Bible', [
              ListTile(
                leading: const Icon(Icons.menu_book_outlined),
                title: const Text('Default translation'),
                trailing: DropdownButton<String>(
                  value: s.bibleTranslation,
                  underline: const SizedBox(),
                  items: [
                    for (final e in BibleService.translations.entries)
                      DropdownMenuItem(value: e.key, child: Text(e.value)),
                  ],
                  onChanged: (v) => s.bibleTranslation = v ?? 'kjv',
                ),
              ),
            ]),
            section('Quick capture', [
              ListTile(
                leading: const Icon(Icons.keyboard_outlined),
                title: const Text('Laptop: quick note from anywhere'),
                subtitle: Text('${s.quickHotkeyLabel} · Ctrl+N new · Ctrl+Shift+N template · F11 focus mode'),
              ),
              const ListTile(
                leading: Icon(Icons.phone_android),
                title: Text('Android: share to PowerNotes'),
                subtitle: Text(
                    'Share text from any app to PowerNotes. Long-press the app icon for Quick note, Voice note and Scan to text.'),
              ),
            ]),
            const Center(
              child: Text('PowerNotes 1.0', style: TextStyle(fontSize: 12)),
            ),
          ]),
        ),
      ),
    );
  }

  Future<void> _toggleEncryption(BuildContext context, bool on) async {
    final s = context.read<Settings>();
    final sync = context.read<SyncService>();
    if (on) {
      if (s.email.isEmpty) {
        toast(context, 'Sign in first, so the key matches on all your devices.');
        return;
      }
      final pass = await promptText(context, 'Encryption passphrase',
          hint: 'At least 8 characters. If you forget it, synced notes cannot be read.',
          obscure: true);
      if (pass == null || pass.length < 8) {
        if (context.mounted && pass != null) toast(context, 'Use at least 8 characters.');
        return;
      }
      final key = await CryptoService.deriveKey(pass, s.email);
      s.setEncryption(true, key);
    } else {
      if (!await confirm(context, 'Turn off encryption?',
          'Your notes will be re-uploaded as plain text.')) {
        return;
      }
      s.setEncryption(false, null);
    }
    await sync.markAllPending();
  }
}

class _SignInDialog extends StatefulWidget {
  const _SignInDialog();

  @override
  State<_SignInDialog> createState() => _SignInDialogState();
}

class _SignInDialogState extends State<_SignInDialog> {
  late final _server = TextEditingController(text: context.read<Settings>().serverUrl);
  final _email = TextEditingController();
  final _pass = TextEditingController();
  bool _register = false;
  bool _busy = false;
  String? _error;

  Future<void> _go() async {
    final s = context.read<Settings>();
    final api = context.read<ApiClient>();
    final sync = context.read<SyncService>();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      var url = _server.text.trim();
      if (url.isNotEmpty && !url.startsWith('http')) url = 'https://$url';
      s.serverUrl = url;
      final token = await api.login(_email.text.trim(), _pass.text, register: _register);
      s.setSession(_email.text.trim().toLowerCase(), token);
      s.lastSyncAt = 0;
      await sync.markAllPending();
      if (mounted) Navigator.pop(context);
    } on ApiException catch (e) {
      _error = e.message;
    } catch (e) {
      _error = 'Could not reach the server. Check the address.';
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_register ? 'Create account' : 'Sign in'),
      content: SizedBox(
        width: 420,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: _server,
            decoration: const InputDecoration(
                labelText: 'Server address', hintText: 'https://notes.yourdomain.com'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'Email'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _pass,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Password'),
            onSubmitted: (_) => _go(),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          if (_busy) const Padding(padding: EdgeInsets.only(top: 10), child: LinearProgressIndicator()),
        ]),
      ),
      actions: [
        TextButton(
          onPressed: () => setState(() => _register = !_register),
          child: Text(_register ? 'I have an account' : 'Create account'),
        ),
        FilledButton(
            onPressed: _busy ? null : _go, child: Text(_register ? 'Create' : 'Sign in')),
      ],
    );
  }
}
