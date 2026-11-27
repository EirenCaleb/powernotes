import 'dart:convert';

import 'package:http/http.dart' as http;

/// Looks up Bible passages by reference (e.g. "John 3:16", "Ps 23:1-4")
/// using the free bible-api.com service.
class BibleService {
  static const translations = <String, String>{
    'kjv': 'King James Version',
    'web': 'World English Bible',
    'asv': 'American Standard Version',
    'bbe': 'Bible in Basic English',
    'ylt': "Young's Literal Translation",
  };

  static Future<String> lookup(String reference, String translation) async {
    final uri = Uri.parse(
        'https://bible-api.com/${Uri.encodeComponent(reference.trim())}?translation=$translation');
    final res = await http.get(uri).timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) {
      throw Exception('Could not find "$reference". Check the book, chapter and verse.');
    }
    final j = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    final verses = (j['verses'] as List?) ?? [];
    final ref = j['reference'] as String? ?? reference;
    final buf = StringBuffer();
    if (verses.length <= 1) {
      buf.write('> ${(j['text'] as String? ?? '').trim().replaceAll('\n', ' ')}');
    } else {
      for (final v in verses) {
        final m = v as Map<String, dynamic>;
        buf.write('> **${m['verse']}** ${(m['text'] as String).trim().replaceAll('\n', ' ')}\n>\n');
      }
    }
    final out = buf.toString().trimRight();
    return '$out\n> — *$ref (${translation.toUpperCase()})*\n';
  }
}
