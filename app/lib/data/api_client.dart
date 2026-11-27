import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../services/settings.dart';

class ApiException implements Exception {
  ApiException(this.message, [this.status]);
  final String message;
  final int? status;
  @override
  String toString() => message;
}

/// Talks to the PowerNotes PHP API on Hostinger.
/// Every endpoint returns `{ ok, message, data }`.
class ApiClient {
  ApiClient(this.settings);
  final Settings settings;

  Uri _u(String endpoint) => Uri.parse('${settings.serverUrl}/api/$endpoint');

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        if (settings.token.isNotEmpty) 'Authorization': 'Bearer ${settings.token}',
      };

  Future<dynamic> post(String endpoint, Map<String, dynamic> body,
      {Duration timeout = const Duration(seconds: 30)}) async {
    if (settings.serverUrl.isEmpty) {
      throw ApiException('Set your server address in Settings first.');
    }
    final res = await http
        .post(_u(endpoint), headers: _headers, body: jsonEncode(body))
        .timeout(timeout);
    return _decode(res);
  }

  Future<dynamic> get(String endpoint, Map<String, String> query) async {
    if (settings.serverUrl.isEmpty) {
      throw ApiException('Set your server address in Settings first.');
    }
    final res = await http
        .get(_u(endpoint).replace(queryParameters: query), headers: _headers)
        .timeout(const Duration(seconds: 30));
    return _decode(res);
  }

  dynamic _decode(http.Response res) {
    Map<String, dynamic> j;
    try {
      j = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    } catch (_) {
      throw ApiException('Server sent an unexpected reply (HTTP ${res.statusCode}).',
          res.statusCode);
    }
    if (j['ok'] != true) {
      throw ApiException((j['message'] ?? 'Request failed') as String, res.statusCode);
    }
    return j['data'];
  }

  // ---------- auth ----------
  Future<String> login(String email, String password, {bool register = false}) async {
    final data = await post(register ? 'api_register.php' : 'api_login.php',
        {'email': email, 'password': password});
    return (data as Map<String, dynamic>)['token'] as String;
  }

  // ---------- AI (Gemini, key kept on the server) ----------
  Future<String> ai(String action, String text, {String? extra}) async {
    final data = await post('api_ai.php', {'action': action, 'text': text, 'extra': extra},
        timeout: const Duration(seconds: 90));
    return (data as Map<String, dynamic>)['result'] as String;
  }

  Future<String> ocr(Uint8List imageBytes, String mime) async {
    final data = await post('api_ai.php', {
      'action': 'ocr',
      'image': base64Encode(imageBytes),
      'mime': mime,
    }, timeout: const Duration(seconds: 90));
    return (data as Map<String, dynamic>)['result'] as String;
  }

  Future<String> transcribe(Uint8List audioBytes, String mime) async {
    final data = await post('api_ai.php', {
      'action': 'transcribe',
      'audio': base64Encode(audioBytes),
      'mime': mime,
    }, timeout: const Duration(seconds: 120));
    return (data as Map<String, dynamic>)['result'] as String;
  }

  // ---------- share by link ----------
  Future<String> share(String noteUuid, String title, String body) async {
    final data = await post('api_share.php',
        {'action': 'create', 'note_uuid': noteUuid, 'title': title, 'body': body});
    return (data as Map<String, dynamic>)['url'] as String;
  }

  Future<void> unshare(String noteUuid) =>
      post('api_share.php', {'action': 'revoke', 'note_uuid': noteUuid});
}
