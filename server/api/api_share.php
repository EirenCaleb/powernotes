<?php
declare(strict_types=1);
require __DIR__ . '/lib.php';
require_method('POST');

// Publishes a read-only copy of a note at share.php?t=TOKEN, or revokes it.
$uid = auth_user();
$in = input();
$action = (string)($in['action'] ?? 'create');
$noteUuid = (string)($in['note_uuid'] ?? '');
if (!valid_uuid($noteUuid)) {
    json_out(false, 'Bad note id.', null, 422);
}

if ($action === 'revoke') {
    db()->prepare('DELETE FROM pn_shares WHERE user_id = ? AND note_uuid = ?')->execute([$uid, $noteUuid]);
    json_out(true, 'Link turned off');
}

$title = mb_substr(trim((string)($in['title'] ?? 'Note')), 0, 500);
$body = (string)($in['body'] ?? '');
if (strlen($body) > 2 * 1024 * 1024) {
    json_out(false, 'Note is too large to share.', null, 413);
}

$st = db()->prepare('SELECT token FROM pn_shares WHERE user_id = ? AND note_uuid = ?');
$st->execute([$uid, $noteUuid]);
$token = $st->fetchColumn();

if ($token === false) {
    $token = bin2hex(random_bytes(16));
    db()->prepare('INSERT INTO pn_shares (token, user_id, note_uuid, title, body) VALUES (?, ?, ?, ?, ?)')
        ->execute([$token, $uid, $noteUuid, $title, $body]);
} else {
    db()->prepare('UPDATE pn_shares SET title = ?, body = ? WHERE token = ?')->execute([$title, $body, $token]);
}

$base = rtrim((string)(config()['base_url'] ?? ''), '/');
json_out(true, 'Shared', ['url' => $base . '/share.php?t=' . $token]);
