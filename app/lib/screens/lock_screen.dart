import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/lock_service.dart';

/// Full-screen PIN pad shown when "Lock the whole app" is on.
class LockScreen extends StatefulWidget {
  const LockScreen({super.key});

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  String _pin = '';
  bool _wrong = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => context.read<LockService>().tryBiometric());
  }

  void _tap(String d) {
    setState(() {
      _wrong = false;
      _pin += d;
    });
    if (_pin.length >= 4) {
      final ok = context.read<LockService>().tryPin(_pin);
      if (!ok && _pin.length >= 8) {
        setState(() {
          _pin = '';
          _wrong = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget key(String label, {VoidCallback? onTap, IconData? icon}) => Padding(
          padding: const EdgeInsets.all(8),
          child: SizedBox(
            width: 72,
            height: 72,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(shape: const CircleBorder()),
              onPressed: onTap ?? () => _tap(label),
              child: icon != null
                  ? Icon(icon)
                  : Text(label, style: const TextStyle(fontSize: 24)),
            ),
          ),
        );
    return Material(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: SafeArea(
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.bolt, size: 48, color: scheme.primary),
            const SizedBox(height: 8),
            const Text('PowerNotes is locked',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            Text(_wrong ? 'Wrong PIN, try again' : '•' * _pin.length,
                style: TextStyle(
                    fontSize: _wrong ? 14 : 28,
                    letterSpacing: 6,
                    color: _wrong ? scheme.error : scheme.onSurface)),
            const SizedBox(height: 16),
            for (final row in const [
              ['1', '2', '3'],
              ['4', '5', '6'],
              ['7', '8', '9'],
            ])
              Row(mainAxisSize: MainAxisSize.min, children: [for (final d in row) key(d)]),
            Row(mainAxisSize: MainAxisSize.min, children: [
              key('', icon: Icons.fingerprint,
                  onTap: () => context.read<LockService>().tryBiometric()),
              key('0'),
              key('', icon: Icons.backspace_outlined, onTap: () {
                if (_pin.isNotEmpty) setState(() => _pin = _pin.substring(0, _pin.length - 1));
              }),
            ]),
          ]),
        ),
      ),
    );
  }
}
