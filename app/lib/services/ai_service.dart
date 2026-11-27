import '../data/api_client.dart';

/// AI actions. The Gemini key lives on your Hostinger server, never in the app.
class AiAction {
  const AiAction(this.id, this.label, this.icon, {this.replaces = false});
  final String id;
  final String label;
  final String icon;
  final bool replaces; // true = offer "Replace", else "Insert below"
}

const aiActions = <AiAction>[
  AiAction('summarize', 'Summarize', '📋'),
  AiAction('rewrite', 'Rewrite clearly', '✍️', replaces: true),
  AiAction('fix', 'Fix grammar and spelling', '🔤', replaces: true),
  AiAction('translate_tl', 'Translate to Tagalog', '🇵🇭', replaces: true),
  AiAction('translate_en', 'Translate to English', '🇺🇸', replaces: true),
  AiAction('todo', 'Turn into a to-do list', '✅'),
  AiAction('outline', 'Make an outline', '🧭'),
  AiAction('continue', 'Continue writing', '➡️'),
  AiAction('ask', 'Ask anything about this note', '💬'),
];

class AiService {
  AiService(this.api);
  final ApiClient api;

  Future<String> run(String action, String text, {String? question}) =>
      api.ai(action, text, extra: question);
}
