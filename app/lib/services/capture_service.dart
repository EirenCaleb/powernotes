import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../data/api_client.dart';

/// Voice notes, photo-to-text and Android share-to-PowerNotes.
class CaptureService {
  CaptureService(this.api);
  final ApiClient api;

  // ---------- voice ----------
  final SpeechToText _speech = SpeechToText();
  bool _speechReady = false;

  Future<bool> initSpeech() async {
    if (_speechReady) return true;
    try {
      _speechReady = await _speech.initialize();
    } catch (_) {
      _speechReady = false;
    }
    return _speechReady;
  }

  bool get listening => _speech.isListening;

  /// Streams partial transcripts; [onDone] receives the final text.
  Future<bool> startListening({
    required void Function(String partial) onPartial,
    required void Function(String text) onDone,
    String localeId = 'en_US',
  }) async {
    if (!await initSpeech()) return false;
    await _speech.listen(
      listenOptions: SpeechListenOptions(
        localeId: localeId,
        partialResults: true,
        listenMode: ListenMode.dictation,
        cancelOnError: true,
        pauseFor: const Duration(seconds: 6),
        listenFor: const Duration(minutes: 5),
      ),
      onResult: (r) {
        if (r.finalResult) {
          onDone(r.recognizedWords);
        } else {
          onPartial(r.recognizedWords);
        }
      },
    );
    return true;
  }

  Future<void> stopListening() => _speech.stop();

  Future<List<String>> locales() async {
    if (!await initSpeech()) return [];
    final l = await _speech.locales();
    return l.map((e) => e.localeId).toList();
  }

  // ---------- photo / scan to text ----------
  /// Android: on-device ML Kit (works offline).
  /// Windows: the image goes to your server, which asks Gemini to read it.
  Future<String?> scanText({bool camera = true}) async {
    if (Platform.isAndroid || Platform.isIOS) {
      final img = await ImagePicker().pickImage(
          source: camera ? ImageSource.camera : ImageSource.gallery, imageQuality: 90);
      if (img == null) return null;
      final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
      try {
        final result = await recognizer.processImage(InputImage.fromFilePath(img.path));
        if (result.text.trim().isNotEmpty) return result.text;
      } finally {
        await recognizer.close();
      }
      // Handwriting ML Kit can't read: try the server.
      final bytes = await File(img.path).readAsBytes();
      return api.ocr(bytes, 'image/jpeg');
    }
    final file = await openFile(acceptedTypeGroups: [
      const XTypeGroup(label: 'Images', extensions: ['jpg', 'jpeg', 'png', 'webp']),
    ]);
    if (file == null) return null;
    final bytes = await file.readAsBytes();
    final ext = file.name.split('.').last.toLowerCase();
    return api.ocr(bytes, ext == 'png' ? 'image/png' : ext == 'webp' ? 'image/webp' : 'image/jpeg');
  }

  /// Transcribe an audio file (e.g. a recorded sermon) through the server.
  Future<String?> transcribeFile() async {
    final file = await openFile(acceptedTypeGroups: [
      const XTypeGroup(label: 'Audio', extensions: ['mp3', 'm4a', 'wav', 'ogg', 'aac']),
    ]);
    if (file == null) return null;
    final bytes = await file.readAsBytes();
    if (bytes.length > 15 * 1024 * 1024) {
      throw ApiException('Audio file is over 15 MB. Trim it first.');
    }
    final ext = file.name.split('.').last.toLowerCase();
    const mimes = {
      'mp3': 'audio/mpeg',
      'm4a': 'audio/mp4',
      'wav': 'audio/wav',
      'ogg': 'audio/ogg',
      'aac': 'audio/aac',
    };
    return api.transcribe(bytes, mimes[ext] ?? 'audio/mpeg');
  }

  // ---------- share to PowerNotes (Android) ----------
  StreamSubscription? _shareSub;

  void listenForShares(void Function(String text) onShared) {
    if (!Platform.isAndroid) return;
    void handle(List<SharedMediaFile> files) {
      final text = files
          .where((f) => f.type == SharedMediaType.text || f.type == SharedMediaType.url)
          .map((f) => f.path)
          .join('\n\n');
      if (text.trim().isNotEmpty) onShared(text);
    }

    ReceiveSharingIntent.instance.getInitialMedia().then((f) {
      handle(f);
      ReceiveSharingIntent.instance.reset();
    });
    _shareSub = ReceiveSharingIntent.instance.getMediaStream().listen(handle);
  }

  void dispose() => _shareSub?.cancel();
}
