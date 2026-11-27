<?php
declare(strict_types=1);
require __DIR__ . '/lib.php';
require_method('GET');

// Returns rows changed on the server since the device's last cursor.
$uid = auth_user();
$since = max(0, (int)($_GET['since'] ?? 0));
// Cursor overlaps by 5 seconds so a push that commits mid-pull is never missed.
// Re-sending a row is harmless: the app upserts by uuid.
$cursor = now_ms() - 5000;

$st = db()->prepare(
    'SELECT uuid, title, body, folder_uuid, tags, pinned, private, created_at, updated_at, deleted
     FROM pn_notes WHERE user_id = ? AND server_ts > ? ORDER BY server_ts'
);
$st->execute([$uid, $since]);
$notes = $st->fetchAll();

$st = db()->prepare(
    'SELECT uuid, name, updated_at, deleted FROM pn_folders WHERE user_id = ? AND server_ts > ?'
);
$st->execute([$uid, $since]);
$folders = $st->fetchAll();

foreach ($notes as &$n) {
    foreach (['pinned', 'private', 'created_at', 'updated_at', 'deleted'] as $k) {
        $n[$k] = (int)$n[$k];
    }
}
unset($n);
foreach ($folders as &$f) {
    $f['updated_at'] = (int)$f['updated_at'];
    $f['deleted'] = (int)$f['deleted'];
}
unset($f);

json_out(true, 'OK', [
    'notes' => $notes,
    'folders' => $folders,
    'server_time' => max($cursor, $since),
]);
