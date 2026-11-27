<?php
declare(strict_types=1);
require __DIR__ . '/lib.php';
require_method('POST');

// AI actions through Gemini. The API key stays on the server.
$uid = auth_user();
$in = input();
$action = (string)($in['action'] ?? '');
$cfg = config();
$key = (string)($cfg['gemini_key'] ?? '');
if ($key === '') {
    json_out(false, 'AI is not set up yet. Add gemini_key to powernotes_config.php on the server.', null, 503);
}
$model = (string)($cfg['gemini_model'] ?? 'gemini-2.5-flash');

$text = (string)($in['text'] ?? '');
$extra = (string)($in['extra'] ?? '');
if (mb_strlen($text) > 60000) {
    json_out(false, 'That note is too long for AI. Select a part of it first.', null, 413);
}

$keepFormat = ' Reply with Markdown only, no preamble, no explanation.';
$prompts = [
    'summarize'    => 'Summarize this note in a few short bullet points. Keep names, dates and Bible references.' . $keepFormat,
    'rewrite'      => 'Rewrite this text so it is clear, warm and easy to read. Keep the meaning, language and Markdown structure.' . $keepFormat,
    'fix'          => 'Fix grammar, spelling and punctuation only. Do not change the wording otherwise. Keep the Markdown.' . $keepFormat,
    'translate_tl' => 'Translate this into natural, church-appropriate Filipino (Tagalog), not word-for-word. Keep Markdown, names and Bible references.' . $keepFormat,
    'translate_en' => 'Translate this into natural English. Keep Markdown, names and Bible references.' . $keepFormat,
    'todo'         => 'Turn this into a practical to-do list using Markdown task items ("- [ ] ..."). Group under short headings if helpful.' . $keepFormat,
    'outline'      => 'Turn this into a clear outline with headings and bullet points.' . $keepFormat,
    'continue'     => 'Continue writing this note in the same voice and language for one or two more paragraphs. Return only the new text.' . $keepFormat,
    'ask'          => 'Answer the question using the note below. If the note does not contain the answer, say so briefly.' . $keepFormat,
];

$parts = [];
if ($action === 'ocr') {
    $img = (string)($in['image'] ?? '');
    $mime = (string)($in['mime'] ?? 'image/jpeg');
    if (!in_array($mime, ['image/jpeg', 'image/png', 'image/webp'], true) || $img === '') {
        json_out(false, 'Send a JPG, PNG or WEBP image.', null, 422);
    }
    if (strlen($img) > 14 * 1024 * 1024) {
        json_out(false, 'Image is too large. Use a smaller photo.', null, 413);
    }
    $parts[] = ['text' => 'Transcribe all text in this image exactly, including handwriting. Keep line breaks, lists and headings as Markdown. Return only the text.'];
    $parts[] = ['inline_data' => ['mime_type' => $mime, 'data' => $img]];
} elseif ($action === 'transcribe') {
    $audio = (string)($in['audio'] ?? '');
    $mime = (string)($in['mime'] ?? 'audio/mpeg');
    if (!preg_match('#^audio/[a-z0-9.+-]+$#', $mime) || $audio === '') {
        json_out(false, 'Send an audio file.', null, 422);
    }
    $parts[] = ['text' => 'Transcribe this audio. It may be English, Tagalog or Taglish; keep the original language. Add paragraph breaks at natural pauses. Return only the transcript.'];
    $parts[] = ['inline_data' => ['mime_type' => $mime, 'data' => $audio]];
} elseif (isset($prompts[$action])) {
    if (trim($text) === '') {
        json_out(false, 'Nothing to work on.', null, 422);
    }
    $prompt = $prompts[$action];
    if ($action === 'ask') {
        $prompt .= "\n\nQuestion: " . mb_substr($extra, 0, 2000);
    }
    $parts[] = ['text' => $prompt . "\n\n---\n" . $text];
} else {
    json_out(false, 'Unknown AI action.', null, 422);
}

$payload = json_encode([
    'contents' => [['role' => 'user', 'parts' => $parts]],
    'generationConfig' => ['temperature' => $action === 'continue' ? 0.8 : 0.3],
]);

$ch = curl_init('https://generativelanguage.googleapis.com/v1beta/models/' . rawurlencode($model) . ':generateContent');
curl_setopt_array($ch, [
    CURLOPT_POST => true,
    CURLOPT_RETURNTRANSFER => true,
    CURLOPT_TIMEOUT => 110,
    CURLOPT_HTTPHEADER => ['Content-Type: application/json', 'x-goog-api-key: ' . $key],
    CURLOPT_POSTFIELDS => $payload,
]);
$res = curl_exec($ch);
$code = (int) curl_getinfo($ch, CURLINFO_HTTP_CODE);
$err = curl_error($ch);
curl_close($ch);

if ($res === false) {
    error_log('[PowerNotes] Gemini curl error: ' . $err);
    json_out(false, 'Could not reach the AI service. Try again.', null, 502);
}
$j = json_decode((string)$res, true);
if ($code !== 200) {
    $msg = $j['error']['message'] ?? ('HTTP ' . $code);
    error_log('[PowerNotes] Gemini error: ' . $msg);
    json_out(false, 'AI error: ' . $msg, null, 502);
}

$out = '';
foreach (($j['candidates'][0]['content']['parts'] ?? []) as $p) {
    $out .= $p['text'] ?? '';
}
$out = trim($out);
if ($out === '') {
    json_out(false, 'The AI returned nothing. Try rewording or a shorter text.', null, 502);
}
json_out(true, 'OK', ['result' => $out]);
