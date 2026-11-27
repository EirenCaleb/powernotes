import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../data/api_client.dart';
import '../models/note.dart';
import '../screens/history_screen.dart';
import '../services/capture_service.dart';
import '../services/export_service.dart';
import '../services/lock_service.dart';
import '../services/notes_store.dart';
import '../services/settings.dart';
import 'ai_sheet.dart';
import 'dialogs.dart';
import 'markdown_view.dart';
import 'note_list.dart' show friendlyDate;

enum EditorMode { edit, preview, split }

enum PendingAction { none, voice, scan }

/// The note editor: title, tags, folder, Markdown toolbar, edit / preview,
/// autosave, word count, backlinks and the note menu.
class NoteEditor extends StatefulWidget {
  const NoteEditor({
    super.key,
    required this.uuid,
    this.pendingAction = PendingAction.none,
    this.focusMode = false,
    this.onToggleFocus,
    this.onOpenNote,
    this.showBack = false,
  });
  final String uuid;
  final PendingAction pendingAction;
  final bool focusMode;
  final VoidCallback? onToggleFocus;
  final void Function(Note n)? onOpenNote;
  final bool showBack;

  @override
  State<NoteEditor> createState() => _NoteEditorState();
}

class _NoteEditorState extends State<NoteEditor> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  final _bodyFocus = FocusNode();
  final _scroll = ScrollController();
  Note? _note;
  Timer? _saveTimer;
  bool _dirty = false;
  bool _saving = false;
  EditorMode _mode = EditorMode.edit;
  bool _listening = false;
  String _partial = '';
  late NotesStore _store;

  @override
  void initState() {
    super.initState();
    _store = context.read<NotesStore>();
    _load();
    _store.addListener(_onStoreChange);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      switch (widget.pendingAction) {
        case PendingAction.voice:
          _voice();
        case PendingAction.scan:
          _scan();
        case PendingAction.none:
          break;
      }
    });
  }

  void _load() {
    _note = _store.byUuid(widget.uuid);
    _title.text = _note?.title ?? '';
    _body.text = _note?.body ?? '';
    _dirty = false;
    final view = WidgetsBinding.instance.platformDispatcher.views.first;
    final wide = view.physicalSize.width / view.devicePixelRatio > 1200;
    _mode = (_note?.body.isNotEmpty ?? false) && !wide ? EditorMode.preview : EditorMode.edit;
    if (wide && (_note?.body.isNotEmpty ?? false)) _mode = EditorMode.split;
  }

  /// A sync replaced the note object: reload unless we're mid-edit.
  void _onStoreChange() {
    final fresh = _store.byUuid(widget.uuid);
    if (fresh == null || identical(fresh, _note)) return;
    if (_dirty) {
      _note = fresh;
      return;
    }
    setState(() {
      _note = fresh;
      if (_title.text != fresh.title) _title.text = fresh.title;
      if (_body.text != fresh.body) _body.text = fresh.body;
    });
  }

  @override
  void didUpdateWidget(NoteEditor old) {
    super.didUpdateWidget(old);
    if (old.uuid != widget.uuid) {
      _flush(snapshot: true);
      setState(_load);
    }
  }

  @override
  void dispose() {
    _flush(snapshot: true);
    _store.removeListener(_onStoreChange);
    _saveTimer?.cancel();
    _title.dispose();
    _body.dispose();
    _bodyFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _changed() {
    _dirty = true;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 700), () => _flush());
    setState(() {});
  }

  Future<void> _flush({bool snapshot = false}) async {
    _saveTimer?.cancel();
    final n = _note;
    if (n == null) return;
    if (_dirty) {
      n.title = _title.text;
      n.body = _body.text;
      _dirty = false;
      _saving = true;
      await _store.save(n);
      _saving = false;
      if (mounted) setState(() {});
    }
    if (snapshot) await _store.snapshot(n);
  }

  // ---------- text helpers ----------
  void _wrap(String left, [String? right]) {
    right ??= left;
    final sel = _body.selection;
    final text = _body.text;
    if (!sel.isValid) {
      _insert('$left$right', cursorBack: right.length);
      return;
    }
    final selected = sel.textInside(text);
    final newText = text.replaceRange(sel.start, sel.end, '$left$selected$right');
    _body.value = TextEditingValue(
      text: newText,
      selection: selected.isEmpty
          ? TextSelection.collapsed(offset: sel.start + left.length)
          : TextSelection(
              baseOffset: sel.start + left.length,
              extentOffset: sel.start + left.length + selected.length),
    );
    _changed();
    _bodyFocus.requestFocus();
  }

  void _insert(String s, {int cursorBack = 0}) {
    final sel = _body.selection;
    final text = _body.text;
    final start = sel.isValid ? sel.start : text.length;
    final end = sel.isValid ? sel.end : text.length;
    final newText = text.replaceRange(start, end, s);
    _body.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: start + s.length - cursorBack),
    );
    _changed();
    if (_mode == EditorMode.preview) setState(() => _mode = EditorMode.edit);
    _bodyFocus.requestFocus();
  }

  /// Inserts a block on its own line(s).
  void _insertBlock(String s) {
    final sel = _body.selection;
    final pos = sel.isValid ? sel.start : _body.text.length;
    final before = _body.text.substring(0, pos);
    final needsNl = before.isNotEmpty && !before.endsWith('\n');
    _insert('${needsNl ? '\n' : ''}$s\n');
  }

  /// Toggles a prefix (e.g. "- [ ] ") on every selected line.
  void _linePrefix(String prefix) {
    final text = _body.text;
    final sel = _body.selection.isValid
        ? _body.selection
        : TextSelection.collapsed(offset: text.length);
    var lineStart = text.lastIndexOf('\n', sel.start == 0 ? 0 : sel.start - 1);
    lineStart = lineStart < 0 ? 0 : lineStart + 1;
    if (sel.start == 0) lineStart = 0;
    var lineEnd = text.indexOf('\n', sel.end);
    if (lineEnd < 0) lineEnd = text.length;
    final lines = text.substring(lineStart, lineEnd).split('\n');
    final allHave = lines.every((l) => l.startsWith(prefix));
    final out = lines
        .map((l) => allHave
            ? l.substring(prefix.length)
            : '$prefix${l.replaceFirst(RegExp(r'^(#{1,6} |[-*] \[[ xX]\] |[-*] |\d+\. |> )'), '')}')
        .join('\n');
    final newText = text.replaceRange(lineStart, lineEnd, out);
    _body.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: lineStart + out.length),
    );
    _changed();
    _bodyFocus.requestFocus();
  }

  /// Appends a token to the end of the cursor's line.
  void _appendToLine(String token) {
    final text = _body.text;
    final pos = _body.selection.isValid ? _body.selection.end : text.length;
    var lineEnd = text.indexOf('\n', pos);
    if (lineEnd < 0) lineEnd = text.length;
    final insert = '${lineEnd > 0 && text[lineEnd - 1] != ' ' ? ' ' : ''}$token';
    _body.value = TextEditingValue(
      text: text.replaceRange(lineEnd, lineEnd, insert),
      selection: TextSelection.collapsed(offset: lineEnd + insert.length),
    );
    _changed();
  }

  // ---------- capture ----------
  Future<void> _voice() async {
    final capture = context.read<CaptureService>();
    if (_listening) {
      await capture.stopListening();
      setState(() => _listening = false);
      return;
    }
    final ok = await capture.startListening(
      onPartial: (p) => setState(() => _partial = p),
      onDone: (t) {
        setState(() {
          _listening = false;
          _partial = '';
        });
        if (t.trim().isNotEmpty) _insert('${t.trim()} ');
      },
    );
    if (!ok) {
      if (!mounted) return;
      final useFile = await confirm(
        context,
        'Live voice typing is not available here',
        'This device has no speech recognizer. You can pick an audio recording instead '
            'and your server will transcribe it.',
        ok: 'Pick audio file',
      );
      if (useFile && mounted) await _transcribeFile();
      return;
    }
    setState(() => _listening = true);
  }

  Future<void> _transcribeFile() async {
    try {
      toast(context, 'Transcribing… this can take a minute');
      final t = await context.read<CaptureService>().transcribeFile();
      if (t != null && mounted) _insertBlock(t.trim());
    } catch (e) {
      if (mounted) toast(context, '$e');
    }
  }

  Future<void> _scan() async {
    final capture = context.read<CaptureService>();
    var camera = true;
    if (Theme.of(context).platform == TargetPlatform.android) {
      final src = await showModalBottomSheet<bool>(
        context: context,
        builder: (c) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: const Text('Take a photo'),
                onTap: () => Navigator.pop(c, true)),
            ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Choose from gallery'),
                onTap: () => Navigator.pop(c, false)),
          ]),
        ),
      );
      if (src == null) return;
      camera = src;
    }
    try {
      if (mounted) toast(context, 'Reading text…');
      final t = await capture.scanText(camera: camera);
      if (t != null && t.trim().isNotEmpty && mounted) _insertBlock(t.trim());
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message);
    } catch (e) {
      if (mounted) toast(context, 'Could not read text: $e');
    }
  }

  // ---------- menu actions ----------
  Future<void> _menu(String action) async {
    final n = _note;
    if (n == null) return;
    await _flush();
    if (!mounted) return;
    final settings = context.read<Settings>();
    try {
      switch (action) {
        case 'pin':
          await _store.togglePin(n);
        case 'private':
          if (!n.private && !settings.lockEnabled) {
            toast(context, 'Set a PIN in Settings first, then you can lock notes.');
            return;
          }
          n.private = !n.private;
          await _store.save(n);
        case 'history':
          await Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => HistoryScreen(note: n)));
          setState(_load);
        case 'pdf':
          final path = await ExportService.exportPdf(n);
          if (path != null && mounted) toast(context, 'Saved $path');
        case 'docx':
          final path = await ExportService.exportDocx(n);
          if (path != null && mounted) toast(context, 'Saved $path');
        case 'md':
          final path = await ExportService.exportMarkdown(n);
          if (path != null && mounted) toast(context, 'Saved $path');
        case 'print':
          await ExportService.printNote(n);
        case 'copy':
          await Clipboard.setData(ClipboardData(text: n.body));
          if (mounted) toast(context, 'Copied');
        case 'link':
          if (!settings.signedIn) {
            toast(context, 'Sign in to your server in Settings to share by link.');
            return;
          }
          final url = await context.read<ApiClient>().share(n.uuid, n.displayTitle, n.body);
          await Clipboard.setData(ClipboardData(text: url));
          if (!mounted) return;
          toast(context, 'Link copied: $url');
          await SharePlus.instance.share(ShareParams(text: url, subject: n.displayTitle));
        case 'unlink':
          await context.read<ApiClient>().unshare(n.uuid);
          if (mounted) toast(context, 'Shared link turned off');
        case 'trash':
          await _store.trash(n);
          if (mounted && widget.showBack) Navigator.of(context).maybePop();
      }
    } catch (e) {
      if (mounted) toast(context, '$e');
    }
    if (mounted) setState(() {});
  }

  Future<void> _addTag() async {
    final t = await promptText(context, 'Add tag', hint: 'e.g. sermon, school, ideas');
    if (t == null || _note == null) return;
    final clean = t.trim().toLowerCase().replaceAll(RegExp(r'[#,\s]+'), '-');
    if (clean.isEmpty || _note!.tags.contains(clean)) return;
    _note!.tags.add(clean);
    _dirty = true;
    await _flush();
  }

  Future<void> _removeTag(String t) async {
    _note?.tags.remove(t);
    _dirty = true;
    await _flush();
  }

  Future<void> _openWiki(String title) async {
    var target = _store.findByTitle(title);
    target ??= await _store.create(title: title, body: '# $title\n\n');
    widget.onOpenNote?.call(target);
  }

  // ---------- build ----------
  @override
  Widget build(BuildContext context) {
    final n = _note;
    final scheme = Theme.of(context).colorScheme;
    final settings = context.watch<Settings>();
    final lock = context.watch<LockService>();
    context.watch<NotesStore>();

    if (n == null) {
      return const Center(child: Text('This note was deleted.'));
    }

    if (n.private && settings.lockEnabled && !lock.privateUnlocked) {
      return _LockedNote(onUnlock: () async {
        final ok = await lock.tryBiometric();
        if (!ok && context.mounted) {
          final pin = await promptText(context, 'Enter PIN', obscure: true);
          if (pin != null && !lock.tryPin(pin) && context.mounted) {
            toast(context, 'Wrong PIN');
          }
        }
      });
    }

    final words = _body.text.trim().isEmpty ? 0 : _body.text.trim().split(RegExp(r'\s+')).length;
    final mins = (words / 200).ceil();
    final wide = MediaQuery.of(context).size.width >= 900;
    final maxW = widget.focusMode ? 760.0 : 900.0;

    final editor = TextField(
      controller: _body,
      focusNode: _bodyFocus,
      onChanged: (_) => _changed(),
      maxLines: null,
      expands: true,
      keyboardType: TextInputType.multiline,
      textAlignVertical: TextAlignVertical.top,
      style: TextStyle(
        fontSize: settings.editorFontSize,
        height: 1.6,
        fontFamilyFallback: const ['Segoe UI', 'Roboto', 'Noto Sans'],
      ),
      decoration: const InputDecoration(
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        filled: false,
        hintText: 'Start writing… Markdown works: # heading, - [ ] task, **bold**, [[Link]]',
        contentPadding: EdgeInsets.fromLTRB(4, 8, 4, 40),
      ),
    );

    final preview = SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 40),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        GestureDetector(
          onDoubleTap: () => setState(() => _mode = EditorMode.edit),
          child: MarkdownView(
            text: _body.text.isEmpty ? '*Empty note. Double-tap to write.*' : _body.text,
            fontSize: settings.editorFontSize,
            onToggleTask: (i) {
              _body.text = MarkdownView.toggleTask(_body.text, i);
              _changed();
            },
            onWikiLink: _openWiki,
          ),
        ),
        _Backlinks(note: n, onOpen: widget.onOpenNote),
      ]),
    );

    Widget content;
    switch (_mode) {
      case EditorMode.edit:
        content = editor;
      case EditorMode.preview:
        content = preview;
      case EditorMode.split:
        content = Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(child: editor),
          VerticalDivider(width: 32, color: scheme.outlineVariant.withValues(alpha: 0.4)),
          Expanded(child: preview),
        ]);
    }

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyB, control: true): () => _wrap('**'),
        const SingleActivator(LogicalKeyboardKey.keyI, control: true): () => _wrap('*'),
        const SingleActivator(LogicalKeyboardKey.keyK, control: true): () => _wrap('[[', ']]'),
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): () async {
          _dirty = true;
          await _flush(snapshot: true);
          if (context.mounted) toast(context, 'Saved to history');
        },
        const SingleActivator(LogicalKeyboardKey.keyE, control: true): () => setState(() =>
            _mode = _mode == EditorMode.preview ? EditorMode.edit : EditorMode.preview),
        const SingleActivator(LogicalKeyboardKey.f11): () => widget.onToggleFocus?.call(),
      },
      child: Column(children: [
        // ----- top bar -----
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
          child: Row(children: [
            if (widget.showBack)
              IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            const Spacer(),
            SegmentedButton<EditorMode>(
              showSelectedIcon: false,
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
              segments: [
                const ButtonSegment(
                    value: EditorMode.edit, icon: Icon(Icons.edit_outlined, size: 18)),
                if (wide)
                  const ButtonSegment(
                      value: EditorMode.split, icon: Icon(Icons.vertical_split_outlined, size: 18)),
                const ButtonSegment(
                    value: EditorMode.preview, icon: Icon(Icons.visibility_outlined, size: 18)),
              ],
              selected: {_mode == EditorMode.split && !wide ? EditorMode.edit : _mode},
              onSelectionChanged: (s) => setState(() => _mode = s.first),
            ),
            IconButton(
              tooltip: 'AI',
              icon: const Icon(Icons.auto_awesome_outlined),
              onPressed: () => showAiSheet(context, _body, onChanged: _changed),
            ),
            if (widget.onToggleFocus != null)
              IconButton(
                tooltip: widget.focusMode ? 'Exit focus mode (F11)' : 'Focus mode (F11)',
                icon: Icon(widget.focusMode ? Icons.close_fullscreen : Icons.open_in_full),
                onPressed: widget.onToggleFocus,
              ),
            IconButton(
              tooltip: n.pinned ? 'Unpin' : 'Pin',
              icon: Icon(n.pinned ? Icons.push_pin : Icons.push_pin_outlined),
              onPressed: () => _menu('pin'),
            ),
            PopupMenuButton<String>(
              onSelected: _menu,
              itemBuilder: (_) => [
                PopupMenuItem(
                    value: 'private',
                    child: _mi(n.private ? Icons.lock_open : Icons.lock_outline,
                        n.private ? 'Remove lock' : 'Lock this note')),
                PopupMenuItem(value: 'history', child: _mi(Icons.history, 'Version history')),
                const PopupMenuDivider(),
                PopupMenuItem(
                    value: 'pdf', child: _mi(Icons.picture_as_pdf_outlined, 'Export as PDF')),
                PopupMenuItem(
                    value: 'docx', child: _mi(Icons.description_outlined, 'Export as Word')),
                PopupMenuItem(value: 'md', child: _mi(Icons.code, 'Export as Markdown')),
                PopupMenuItem(value: 'print', child: _mi(Icons.print_outlined, 'Print')),
                const PopupMenuDivider(),
                PopupMenuItem(value: 'link', child: _mi(Icons.link, 'Share by link')),
                PopupMenuItem(value: 'unlink', child: _mi(Icons.link_off, 'Stop sharing link')),
                PopupMenuItem(value: 'copy', child: _mi(Icons.copy, 'Copy text')),
                const PopupMenuDivider(),
                PopupMenuItem(value: 'trash', child: _mi(Icons.delete_outline, 'Move to trash')),
              ],
            ),
          ]),
        ),
        Expanded(
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: _mode == EditorMode.split ? 1600 : maxW),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  // ----- title -----
                  TextField(
                    controller: _title,
                    onChanged: (_) => _changed(),
                    style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
                    decoration: const InputDecoration(
                      hintText: 'Title',
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      filled: false,
                      contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                    ),
                  ),
                  // ----- folder + tags -----
                  if (!widget.focusMode)
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _FolderPicker(
                          note: n,
                          onPicked: (f) async {
                            n.folderUuid = f;
                            _dirty = true;
                            await _flush();
                          },
                        ),
                        for (final t in n.tags)
                          InputChip(
                            label: Text('#$t'),
                            visualDensity: VisualDensity.compact,
                            onDeleted: () => _removeTag(t),
                          ),
                        ActionChip(
                          avatar: const Icon(Icons.add, size: 16),
                          label: const Text('Tag'),
                          visualDensity: VisualDensity.compact,
                          onPressed: _addTag,
                        ),
                      ],
                    ),
                  if (!widget.focusMode && _mode != EditorMode.preview)
                    _Toolbar(
                      onBold: () => _wrap('**'),
                      onItalic: () => _wrap('*'),
                      onHeading: () => _linePrefix('## '),
                      onBullet: () => _linePrefix('- '),
                      onNumbered: () => _linePrefix('1. '),
                      onTask: () => _linePrefix('- [ ] '),
                      onQuote: () => _linePrefix('> '),
                      onCode: () => _insertBlock('```\n\n```'),
                      onTable: () => _insertBlock(
                          '| Column 1 | Column 2 | Column 3 |\n|---|---|---|\n|  |  |  |'),
                      onLink: () => _wrap('[[', ']]'),
                      onReminder: () async {
                        final r = await pickReminder(context);
                        if (r != null) _appendToLine(r);
                      },
                      onVerse: () async {
                        final v = await pickBibleVerse(context, settings.bibleTranslation);
                        if (v != null) _insertBlock(v);
                      },
                      onVoice: _voice,
                      listening: _listening,
                      onScan: _scan,
                    ),
                  if (_listening)
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(top: 6),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: scheme.errorContainer.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(children: [
                        Icon(Icons.mic, color: scheme.error),
                        const SizedBox(width: 8),
                        Expanded(child: Text(_partial.isEmpty ? 'Listening…' : _partial)),
                        TextButton(onPressed: _voice, child: const Text('Stop')),
                      ]),
                    ),
                  Expanded(child: content),
                ]),
              ),
            ),
          ),
        ),
        // ----- status bar -----
        Container(
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 8),
          child: SafeArea(
            top: false,
            child: Row(children: [
              Text('$words words · $mins min read',
                  style: TextStyle(fontSize: 12, color: scheme.outline)),
              const Spacer(),
              Text(
                _dirty || _saving ? 'Saving…' : 'Saved · ${friendlyDate(n.updatedAt)}',
                style: TextStyle(fontSize: 12, color: scheme.outline),
              ),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _mi(IconData i, String t) =>
      Row(children: [Icon(i, size: 20), const SizedBox(width: 12), Text(t)]);
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.onBold,
    required this.onItalic,
    required this.onHeading,
    required this.onBullet,
    required this.onNumbered,
    required this.onTask,
    required this.onQuote,
    required this.onCode,
    required this.onTable,
    required this.onLink,
    required this.onReminder,
    required this.onVerse,
    required this.onVoice,
    required this.listening,
    required this.onScan,
  });
  final VoidCallback onBold, onItalic, onHeading, onBullet, onNumbered, onTask, onQuote;
  final VoidCallback onCode, onTable, onLink, onReminder, onVerse, onVoice, onScan;
  final bool listening;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget b(IconData i, String tip, VoidCallback f, {Color? color}) => IconButton(
          tooltip: tip,
          visualDensity: VisualDensity.compact,
          iconSize: 20,
          color: color ?? scheme.onSurfaceVariant,
          icon: Icon(i),
          onPressed: f,
        );
    Widget sep() => Container(
        width: 1, height: 22, margin: const EdgeInsets.symmetric(horizontal: 4),
        color: scheme.outlineVariant);
    return Container(
      margin: const EdgeInsets.only(top: 6),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.4)),
          bottom: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.4)),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          b(Icons.format_bold, 'Bold (Ctrl+B)', onBold),
          b(Icons.format_italic, 'Italic (Ctrl+I)', onItalic),
          b(Icons.title, 'Heading', onHeading),
          sep(),
          b(Icons.format_list_bulleted, 'Bullet list', onBullet),
          b(Icons.format_list_numbered, 'Numbered list', onNumbered),
          b(Icons.check_box_outlined, 'Checklist', onTask),
          b(Icons.format_quote, 'Quote', onQuote),
          b(Icons.code, 'Code block', onCode),
          b(Icons.table_chart_outlined, 'Table', onTable),
          b(Icons.link, 'Link to note [[ ]] (Ctrl+K)', onLink),
          sep(),
          b(Icons.alarm_add_outlined, 'Reminder on this line', onReminder),
          b(Icons.menu_book_outlined, 'Insert Bible verse', onVerse),
          b(listening ? Icons.mic : Icons.mic_none, 'Voice typing', onVoice,
              color: listening ? scheme.error : null),
          b(Icons.document_scanner_outlined, 'Photo to text', onScan),
        ]),
      ),
    );
  }
}

class _FolderPicker extends StatelessWidget {
  const _FolderPicker({required this.note, required this.onPicked});
  final Note note;
  final void Function(String? folderUuid) onPicked;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<NotesStore>();
    final name = store.folderName(note.folderUuid);
    return PopupMenuButton<String>(
      tooltip: 'Move to folder',
      onSelected: (v) async {
        if (v == '__new') {
          final n = await promptText(context, 'New folder');
          if (n != null && n.trim().isNotEmpty) {
            final f = await store.createFolder(n);
            onPicked(f.uuid);
          }
        } else {
          onPicked(v.isEmpty ? null : v);
        }
      },
      itemBuilder: (_) => [
        const PopupMenuItem(value: '', child: Text('No folder')),
        for (final f in store.folders) PopupMenuItem(value: f.uuid, child: Text(f.name)),
        const PopupMenuItem(value: '__new', child: Text('+ New folder')),
      ],
      child: Chip(
        avatar: const Icon(Icons.folder_outlined, size: 16),
        label: Text(name.isEmpty ? 'No folder' : name),
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}

class _Backlinks extends StatelessWidget {
  const _Backlinks({required this.note, this.onOpen});
  final Note note;
  final void Function(Note n)? onOpen;

  @override
  Widget build(BuildContext context) {
    final links = context.watch<NotesStore>().backlinks(note);
    if (links.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 28),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Divider(color: scheme.outlineVariant),
        Text('LINKED FROM',
            style: TextStyle(
                fontSize: 11, letterSpacing: 1.1, fontWeight: FontWeight.w700,
                color: scheme.onSurfaceVariant)),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final l in links)
            ActionChip(
              avatar: const Icon(Icons.subdirectory_arrow_left, size: 16),
              label: Text(l.displayTitle),
              onPressed: () => onOpen?.call(l),
            ),
        ]),
      ]),
    );
  }
}

class _LockedNote extends StatelessWidget {
  const _LockedNote({required this.onUnlock});
  final VoidCallback onUnlock;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.lock_outline, size: 48, color: scheme.primary),
        const SizedBox(height: 12),
        const Text('This note is locked', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: onUnlock,
          icon: const Icon(Icons.fingerprint),
          label: const Text('Unlock'),
        ),
      ]),
    );
  }
}
