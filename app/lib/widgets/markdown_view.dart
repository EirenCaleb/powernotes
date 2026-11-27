import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:url_launcher/url_launcher.dart';

/// Renders a note's Markdown. Checkboxes can be tapped to tick them, and
/// [[Wiki links]] open (or create) the linked note.
class MarkdownView extends StatelessWidget {
  const MarkdownView({
    super.key,
    required this.text,
    required this.onToggleTask,
    required this.onWikiLink,
    this.fontSize = 16,
  });
  final String text;
  final void Function(int taskIndex) onToggleTask;
  final void Function(String title) onWikiLink;
  final double fontSize;

  static String _withWikiLinks(String s) => s.replaceAllMapped(
      RegExp(r'\[\[([^\]\n]+)\]\]'),
      (m) => '[${m.group(1)}](wiki:${Uri.encodeComponent(m.group(1)!)})');

  /// Highlight @remind(...) tags.
  static String _withReminders(String s) => s.replaceAllMapped(
      RegExp(r'@(remind|due)\(([^)]+)\)'), (m) => '`⏰ ${m.group(2)}`');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    var taskCounter = 0;
    final base = theme.textTheme.bodyLarge!.copyWith(fontSize: fontSize, height: 1.55);
    return MarkdownBody(
      data: _withReminders(_withWikiLinks(text)),
      selectable: false,
      softLineBreak: true,
      extensionSet: md.ExtensionSet.gitHubFlavored,
      styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
        p: base,
        listBullet: base,
        h1: base.copyWith(fontSize: fontSize * 1.75, fontWeight: FontWeight.w800, height: 1.3),
        h2: base.copyWith(fontSize: fontSize * 1.4, fontWeight: FontWeight.w800, height: 1.3),
        h3: base.copyWith(fontSize: fontSize * 1.18, fontWeight: FontWeight.w700),
        blockquote: base.copyWith(color: scheme.onSurfaceVariant, fontStyle: FontStyle.italic),
        blockquoteDecoration: BoxDecoration(
          border: Border(left: BorderSide(color: scheme.primary, width: 3)),
          color: scheme.primaryContainer.withValues(alpha: 0.18),
        ),
        blockquotePadding: const EdgeInsets.fromLTRB(14, 6, 10, 6),
        code: TextStyle(
          fontFamily: 'monospace',
          fontSize: fontSize * 0.88,
          backgroundColor: scheme.surfaceContainerHighest,
        ),
        codeblockDecoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(10),
        ),
        codeblockPadding: const EdgeInsets.all(12),
        tableBorder: TableBorder.all(color: scheme.outlineVariant),
        tableCellsPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        a: TextStyle(color: scheme.primary, decoration: TextDecoration.underline),
      ),
      checkboxBuilder: (checked) {
        final index = taskCounter++;
        return Padding(
          padding: const EdgeInsets.only(right: 6),
          child: InkWell(
            onTap: () => onToggleTask(index),
            child: Icon(
              checked ? Icons.check_box : Icons.check_box_outline_blank,
              size: fontSize + 4,
              color: checked ? scheme.primary : scheme.outline,
            ),
          ),
        );
      },
      onTapLink: (text, href, title) async {
        if (href == null) return;
        if (href.startsWith('wiki:')) {
          onWikiLink(Uri.decodeComponent(href.substring(5)));
        } else {
          final uri = Uri.tryParse(href);
          if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      },
    );
  }

  /// Flips the [index]-th task checkbox in the raw Markdown.
  static String toggleTask(String body, int index) {
    final lines = body.split('\n');
    var count = 0;
    var inFence = false;
    final re = RegExp(r'^(\s*[-*+]\s+)\[([ xX])\]');
    for (var i = 0; i < lines.length; i++) {
      if (lines[i].trimLeft().startsWith('```')) inFence = !inFence;
      if (inFence) continue;
      final m = re.firstMatch(lines[i]);
      if (m == null) continue;
      if (count == index) {
        final done = m.group(2)!.trim().isNotEmpty;
        lines[i] = lines[i].replaceRange(m.start, m.end, '${m.group(1)}[${done ? ' ' : 'x'}]');
        break;
      }
      count++;
    }
    return lines.join('\n');
  }
}
