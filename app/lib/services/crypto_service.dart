import 'dart:convert';

import 'package:cryptography/cryptography.dart';

/// Optional end-to-end encryption for synced notes.
/// Note titles and bodies are encrypted on the device with AES-256-GCM before
/// they leave it, so the server only ever stores ciphertext.
class CryptoService {
  static const _prefix = 'enc:v1:';
  static final _algo = AesGcm.with256bits();

  /// Derive a key from the passphrase. The same passphrase + email gives the
  /// same key on every device, so laptop and phone can read each other's notes.
  static Future<String> deriveKey(String passphrase, String email) async {
    final pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: 150000,
      bits: 256,
    );
    final key = await pbkdf2.deriveKey(
      secretKey: SecretKey(utf8.encode(passphrase)),
      nonce: utf8.encode('powernotes:${email.trim().toLowerCase()}'),
    );
    return base64Encode(await key.extractBytes());
  }

  static bool isEncrypted(String s) => s.startsWith(_prefix);

  static Future<String> encrypt(String plain, String keyB64) async {
    if (plain.isEmpty) return plain;
    final box = await _algo.encrypt(
      utf8.encode(plain),
      secretKey: SecretKey(base64Decode(keyB64)),
    );
    return _prefix + base64Encode(box.concatenation());
  }

  static Future<String> decrypt(String data, String keyB64) async {
    if (!isEncrypted(data)) return data;
    final bytes = base64Decode(data.substring(_prefix.length));
    final box = SecretBox.fromConcatenation(bytes,
        nonceLength: _algo.nonceLength, macLength: _algo.macAlgorithm.macLength);
    final clear =
        await _algo.decrypt(box, secretKey: SecretKey(base64Decode(keyB64)));
    return utf8.decode(clear);
  }
}
