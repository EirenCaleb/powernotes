import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:file_selector/file_selector.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../models/note.dart';

/// A very small Markdown block model shared by the PDF and Word exporters.
class MdBlock {
  MdBlock(this.kind, this.text, {this.level = 0, this.checked, this.rows});
  final String kind; // h, p, li, ol, quote, code, table, hr
  final String text;
  final int level;
  final bool? checked;
  final List<List<String>>? rows;
}

List<MdBlock> parseMarkdown(String md) {
  final lines = md.replaceAll('\r\n', '\n').split('\n');
  final out = <MdBlock>[];
  var i = 0;
  while (i < lines.length) {
    final line = lines[i];
    final t = line.trim();
    if (t.isEmpty) {
      i++;
      continue;
    }
    if (t.startsWith('```')) {
      final buf = <String>[];
      i++;
      while (i < lines.length && !lines[i].trim().startsWith('```')) {
        buf.add(lines[i]);
        i++;
      }
      i++;
      out.add(MdBlock('code', buf.join('\n')));
      continue;
    }
    final h = RegExp(r'^(#{1,6})\s+(.*)$').firstMatch(t);
    if (h != null) {
      out.add(MdBlock('h', h.group(2)!, level: h.group(1)!.length));
      i++;
      continue;
    }
    if (RegExp(r'^(-{3,}|\*{3,})$').hasMatch(t)) {
      out.add(MdBlock('hr', ''));
      i++;
      continue;
    }
    if (t.startsWith('|')) {
      final rows = <List<String>>[];
      while (i < lines.length && lines[i].trim().startsWith('|')) {
        final r = lines[i].trim();
        if (!RegExp(r'^\|[\s:|-]+\|$').hasMatch(r)) {
          rows.add(r.substring(1, r.endsWith('|') ? r.length - 1 : r.length)
              .split('|')
              .map((c) => c.trim())
              .toList());
        }
        i++;
      }
      out.add(MdBlock('table', '', rows: rows));
      continue;
    }
    final task = RegExp(r'^[-*+]\s+\[([ xX])\]\s*(.*)$').firstMatch(t);
    if (task != null) {
      out.add(MdBlock('li', task.group(2)!, checked: task.group(1)!.trim().isNotEmpty));
      i++;
      continue;
    }
    final li = RegExp(r'^[-*+]\s+(.*)$').firstMatch(t);
    if (li != null) {
      out.add(MdBlock('li', li.group(1)!, level: (line.length - line.trimLeft().length) ~/ 2));
      i++;
      continue;
    }
    final ol = RegExp(r'^(\d+)[.)]\s+(.*)$').firstMatch(t);
    if (ol != null) {
      out.add(MdBlock('ol', ol.group(2)!, level: int.parse(ol.group(1)!)));
      i++;
      continue;
    }
    if (t.startsWith('>')) {
      final buf = <String>[];
      while (i < lines.length && lines[i].trim().startsWith('>')) {
        buf.add(lines[i].trim().replaceFirst(RegExp(r'^>\s?'), ''));
        i++;
      }
      out.add(MdBlock('quote', buf.where((s) => s.isNotEmpty).join('\n')));
      continue;
    }
    final buf = <String>[t];
    i++;
    while (i < lines.length &&
        lines[i].trim().isNotEmpty &&
        !RegExp(r'^(#|[-*+]\s|\d+[.)]\s|>|```|\|)').hasMatch(lines[i].trim())) {
      buf.add(lines[i].trim());
      i++;
    }
    out.add(MdBlock('p', buf.join(' ')));
  }
  return out;
}

/// Splits **bold** runs. Returns (text, bold) pairs; strips other markup.
List<(String, bool)> inlineRuns(String s) {
  final clean = s
      .replaceAllMapped(RegExp(r'\[\[([^\]]+)\]\]'), (m) => m.group(1)!)
      .replaceAllMapped(RegExp(r'\[([^\]]+)\]\([^)]+\)'), (m) => m.group(1)!)
      .replaceAll('`', '')
      .replaceAll(RegExp(r'(?<!\*)\*(?!\*)'), '')
      .replaceAll(RegExp(r'\s{2,}$'), '');
  final parts = clean.split('**');
  return [for (var i = 0; i < parts.length; i++) if (parts[i].isNotEmpty) (parts[i], i.isOdd)];
}

class ExportService {
  static String _safeName(Note n) =>
      n.displayTitle.replaceAll(RegExp(r'[\\/:*?"<>|]'), '').trim().replaceAll(' ', '_');

  // ---------- PDF ----------
  static Future<Uint8List> buildPdf(Note n) async {
    pw.Font? base, bold, mono;
    try {
      base = await PdfGoogleFonts.notoSansRegular();
      bold = await PdfGoogleFonts.notoSansBold();
      mono = await PdfGoogleFonts.robotoMonoRegular();
    } catch (_) {
      // Offline: fall back to built-in fonts.
    }
    final theme = base == null
        ? pw.ThemeData.base()
        : pw.ThemeData.withFont(base: base, bold: bold);
    final doc = pw.Document(title: n.displayTitle, theme: theme);

    pw.Widget rich(String s, {double size = 11, bool allBold = false}) => pw.RichText(
          text: pw.TextSpan(children: [
            for (final (t, b) in inlineRuns(s))
              pw.TextSpan(
                  text: t,
                  style: pw.TextStyle(
                      fontSize: size,
                      fontWeight: b || allBold ? pw.FontWeight.bold : pw.FontWeight.normal)),
          ]),
        );

    final widgets = <pw.Widget>[];
    if (n.title.trim().isNotEmpty && !n.body.trimLeft().startsWith('# ')) {
      widgets.add(pw.Text(n.title,
          style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)));
      widgets.add(pw.SizedBox(height: 10));
    }
    for (final b in parseMarkdown(n.body)) {
      switch (b.kind) {
        case 'h':
          final size = <double>[0, 22.0, 17.0, 14.0, 12.0, 11.0, 11.0][b.level];
          widgets.add(pw.Padding(
              padding: const pw.EdgeInsets.only(top: 10, bottom: 4),
              child: rich(b.text, size: size, allBold: true)));
        case 'p':
          widgets.add(pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 6), child: rich(b.text)));
        case 'li':
        case 'ol':
          final bullet = b.checked == null
              ? (b.kind == 'ol' ? '${b.level}.' : '•')
              : (b.checked! ? '[x]' : '[ ]');
          widgets.add(pw.Padding(
            padding: pw.EdgeInsets.only(
                left: (b.kind == 'li' && b.checked == null ? 12 + b.level * 12 : 12).toDouble(),
                bottom: 3),
            child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.SizedBox(width: 22, child: pw.Text(bullet)),
              pw.Expanded(child: rich(b.text)),
            ]),
          ));
        case 'quote':
          widgets.add(pw.Container(
            margin: const pw.EdgeInsets.symmetric(vertical: 6),
            padding: const pw.EdgeInsets.only(left: 10),
            decoration: const pw.BoxDecoration(
                border: pw.Border(left: pw.BorderSide(color: PdfColors.grey500, width: 3))),
            child: rich(b.text.replaceAll('\n', ' ')),
          ));
        case 'code':
          widgets.add(pw.Container(
            width: double.infinity,
            margin: const pw.EdgeInsets.symmetric(vertical: 6),
            padding: const pw.EdgeInsets.all(8),
            color: PdfColors.grey200,
            child: pw.Text(b.text, style: pw.TextStyle(font: mono, fontSize: 9)),
          ));
        case 'table':
          if (b.rows!.isNotEmpty) {
            widgets.add(pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 6),
              child: pw.TableHelper.fromTextArray(
                data: b.rows!
                    .map((r) => r.map((c) => inlineRuns(c).map((e) => e.$1).join()).toList())
                    .toList(),
                cellStyle: const pw.TextStyle(fontSize: 10),
                headerStyle: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
              ),
            ));
          }
        case 'hr':
          widgets.add(pw.Divider());
      }
    }
    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(40),
      build: (_) => widgets,
    ));
    return doc.save();
  }

  // ---------- Word (.docx) ----------
  static String _x(String s) => const HtmlEscape(HtmlEscapeMode.element).convert(s);

  static String _runs(String s, {bool bold = false, String? font}) => inlineRuns(s)
      .map((r) =>
          '<w:r><w:rPr>${bold || r.$2 ? '<w:b/>' : ''}${font != null ? '<w:rFonts w:ascii="$font" w:hAnsi="$font"/>' : ''}</w:rPr><w:t xml:space="preserve">${_x(r.$1)}</w:t></w:r>')
      .join();

  static Uint8List buildDocx(Note n) {
    final body = StringBuffer();
    if (n.title.trim().isNotEmpty && !n.body.trimLeft().startsWith('# ')) {
      body.write('<w:p><w:pPr><w:pStyle w:val="Title"/></w:pPr>${_runs(n.title)}</w:p>');
    }
    for (final b in parseMarkdown(n.body)) {
      switch (b.kind) {
        case 'h':
          body.write(
              '<w:p><w:pPr><w:pStyle w:val="Heading${b.level.clamp(1, 3)}"/></w:pPr>${_runs(b.text)}</w:p>');
        case 'p':
          body.write('<w:p>${_runs(b.text)}</w:p>');
        case 'li':
        case 'ol':
          final bullet = b.checked == null
              ? (b.kind == 'ol' ? '${b.level}. ' : '• ')
              : (b.checked! ? '☑ ' : '☐ ');
          body.write(
              '<w:p><w:pPr><w:ind w:left="${b.kind == 'li' && b.checked == null ? 360 + b.level * 360 : 360}"/></w:pPr><w:r><w:t xml:space="preserve">$bullet</w:t></w:r>${_runs(b.text)}</w:p>');
        case 'quote':
          for (final l in b.text.split('\n')) {
            body.write('<w:p><w:pPr><w:pStyle w:val="Quote"/></w:pPr>${_runs(l)}</w:p>');
          }
        case 'code':
          for (final l in b.text.split('\n')) {
            body.write('<w:p>${_runs(l.isEmpty ? ' ' : l, font: 'Consolas')}</w:p>');
          }
        case 'table':
          body.write(
              '<w:tbl><w:tblPr><w:tblStyle w:val="TableGrid"/><w:tblW w:w="5000" w:type="pct"/></w:tblPr>');
          for (var r = 0; r < b.rows!.length; r++) {
            body.write('<w:tr>');
            for (final c in b.rows![r]) {
              body.write('<w:tc><w:p>${_runs(c.isEmpty ? ' ' : c, bold: r == 0)}</w:p></w:tc>');
            }
            body.write('</w:tr>');
          }
          body.write('</w:tbl><w:p/>');
        case 'hr':
          body.write(
              '<w:p><w:pPr><w:pBdr><w:bottom w:val="single" w:sz="6" w:space="1" w:color="999999"/></w:pBdr></w:pPr></w:p>');
      }
    }

    const ns = 'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"';
    final document =
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:document $ns><w:body>$body<w:sectPr><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="1134" w:right="1134" w:bottom="1134" w:left="1134" w:header="708" w:footer="708" w:gutter="0"/></w:sectPr></w:body></w:document>';
    const styles = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:styles $ns>
<w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii="Calibri" w:hAnsi="Calibri"/><w:sz w:val="22"/></w:rPr></w:rPrDefault><w:pPrDefault><w:pPr><w:spacing w:after="120"/></w:pPr></w:pPrDefault></w:docDefaults>
<w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/></w:style>
<w:style w:type="paragraph" w:styleId="Title"><w:name w:val="Title"/><w:basedOn w:val="Normal"/><w:rPr><w:b/><w:sz w:val="48"/></w:rPr></w:style>
<w:style w:type="paragraph" w:styleId="Heading1"><w:name w:val="heading 1"/><w:basedOn w:val="Normal"/><w:pPr><w:spacing w:before="240"/><w:outlineLvl w:val="0"/></w:pPr><w:rPr><w:b/><w:sz w:val="40"/></w:rPr></w:style>
<w:style w:type="paragraph" w:styleId="Heading2"><w:name w:val="heading 2"/><w:basedOn w:val="Normal"/><w:pPr><w:spacing w:before="200"/><w:outlineLvl w:val="1"/></w:pPr><w:rPr><w:b/><w:sz w:val="32"/></w:rPr></w:style>
<w:style w:type="paragraph" w:styleId="Heading3"><w:name w:val="heading 3"/><w:basedOn w:val="Normal"/><w:pPr><w:spacing w:before="160"/><w:outlineLvl w:val="2"/></w:pPr><w:rPr><w:b/><w:sz w:val="26"/></w:rPr></w:style>
<w:style w:type="paragraph" w:styleId="Quote"><w:name w:val="Quote"/><w:basedOn w:val="Normal"/><w:pPr><w:ind w:left="567"/></w:pPr><w:rPr><w:i/><w:color w:val="555555"/></w:rPr></w:style>
<w:style w:type="table" w:styleId="TableGrid"><w:name w:val="Table Grid"/><w:tblPr><w:tblBorders><w:top w:val="single" w:sz="4" w:color="999999"/><w:left w:val="single" w:sz="4" w:color="999999"/><w:bottom w:val="single" w:sz="4" w:color="999999"/><w:right w:val="single" w:sz="4" w:color="999999"/><w:insideH w:val="single" w:sz="4" w:color="999999"/><w:insideV w:val="single" w:sz="4" w:color="999999"/></w:tblBorders></w:tblPr></w:style>
</w:styles>''';
    const contentTypes = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/><Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/></Types>''';
    const rels = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>''';
    const docRels = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>''';

    final arc = Archive();
    void add(String name, String content) {
      final bytes = utf8.encode(content);
      arc.addFile(ArchiveFile(name, bytes.length, bytes));
    }

    add('[Content_Types].xml', contentTypes);
    add('_rels/.rels', rels);
    add('word/document.xml', document);
    add('word/styles.xml', styles);
    add('word/_rels/document.xml.rels', docRels);
    return Uint8List.fromList(ZipEncoder().encode(arc));
  }

  /// Saves (desktop) or shares (Android) the exported file.
  static Future<String?> deliver(Note n, String ext, Uint8List bytes, String mime) async {
    final name = '${_safeName(n).isEmpty ? 'note' : _safeName(n)}.$ext';
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      final loc = await getSaveLocation(suggestedName: name);
      if (loc == null) return null;
      await File(loc.path).writeAsBytes(bytes);
      return loc.path;
    }
    final dir = await getTemporaryDirectory();
    final f = File(p.join(dir.path, name));
    await f.writeAsBytes(bytes);
    await SharePlus.instance.share(ShareParams(files: [XFile(f.path, mimeType: mime)]));
    return f.path;
  }

  static Future<String?> exportPdf(Note n) async =>
      deliver(n, 'pdf', await buildPdf(n), 'application/pdf');

  static Future<String?> exportDocx(Note n) async => deliver(n, 'docx', buildDocx(n),
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document');

  static Future<String?> exportMarkdown(Note n) async =>
      deliver(n, 'md', Uint8List.fromList(utf8.encode(n.body)), 'text/markdown');

  static Future<void> printNote(Note n) async =>
      Printing.layoutPdf(onLayout: (_) => buildPdf(n), name: n.displayTitle);
}
