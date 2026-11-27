import 'package:flutter_test/flutter_test.dart';
import 'package:powernotes/models/note.dart';
import 'package:powernotes/services/export_service.dart';
import 'package:powernotes/services/reminder_service.dart';
import 'package:powernotes/widgets/markdown_view.dart';

Note _note(String body) => Note(uuid: 'u1', body: body, createdAt: 0, updatedAt: 0);

void main() {
  test('title falls back to first line', () {
    expect(_note('# Hello world\nmore').displayTitle, 'Hello world');
    expect(_note('').displayTitle, 'Untitled');
  });

  test('tags round-trip', () {
    expect(Note.decodeTags(Note.encodeTags(['a', 'b'])), ['a', 'b']);
  });

  test('toggle task flips the right checkbox', () {
    const body = '- [ ] one\n```\n- [ ] in code\n```\n- [ ] two';
    final out = MarkdownView.toggleTask(body, 1);
    expect(out, '- [ ] one\n```\n- [ ] in code\n```\n- [x] two');
  });

  test('reminders are parsed from lines', () {
    final r = ReminderService.parse(
        _note('- [ ] Call Ben @remind(2030-01-02 09:30)\n- [x] done @due(2030-01-01)\nPay @due(2030-02-03)'));
    expect(r.length, 2);
    expect(r.first.text, 'Call Ben');
    expect(r.first.dueAt, DateTime(2030, 1, 2, 9, 30));
    expect(r.last.dueAt, DateTime(2030, 2, 3, 8, 0));
  });

  test('markdown blocks parse', () {
    final b = parseMarkdown('# H\n\npara line\n- [x] task\n| a | b |\n|---|---|\n| 1 | 2 |\n> quote');
    expect(b.map((e) => e.kind).toList(), ['h', 'p', 'li', 'table', 'quote']);
    expect(b[2].checked, true);
    expect(b[3].rows, [
      ['a', 'b'],
      ['1', '2']
    ]);
  });

  test('docx builds a zip', () {
    final bytes = ExportService.buildDocx(_note('# Title\n\nHello **bold**\n- [ ] task'));
    expect(bytes.sublist(0, 2), [0x50, 0x4B]); // "PK"
  });
}
