<?php
declare(strict_types=1);
require __DIR__ . '/lib.php';
require_method('POST');

// Upserts notes and folders by uuid. The newest updated_at wins.
$uid = auth_user();
$in = input();
$notes = is_array($in['notes'] ?? null) ? $in['notes'] : [];
$folders = is_array($in['folders'] ?? null) ? $in['folders'] : [];
if (count($notes) > 2000 || count($folders) > 2000) {
    json_out(false, 'Too many rows in one push.', null, 413);
}

$pdo = db();
$ts = now_ms();
$saved = ['notes' => 0, 'folders' => 0, 'skipped' => 0];

$pdo->beginTransaction();

$getNote = $pdo->prepare('SELECT updated_at FROM pn_notes WHERE user_id = ? AND uuid = ? FOR UPDATE');
$insNote = $pdo->prepare(
    'INSERT INTO pn_notes (user_id, uuid, title, body, folder_uuid, tags, pinned, private, created_at, updated_at, deleted, server_ts)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)'
);
$updNote = $pdo->prepare(
    'UPDATE pn_notes SET title = ?, body = ?, folder_uuid = ?, tags = ?, pinned = ?, private = ?,
       created_at = ?, updated_at = ?, deleted = ?, server_ts = ?
     WHERE user_id = ? AND uuid = ?'
);

foreach ($notes as $n) {
    if (!is_array($n) || !valid_uuid($n['uuid'] ?? null)) {
        $saved['skipped']++;
        continue;
    }
    $folder = valid_uuid($n['folder_uuid'] ?? null) ? $n['folder_uuid'] : null;
    $vals = [
        (string)($n['title'] ?? ''),
        (string)($n['body'] ?? ''),
        $folder,
        mb_substr((string)($n['tags'] ?? ''), 0, 1000),
        (int)!empty($n['pinned']),
        (int)!empty($n['private']),
        (int)($n['created_at'] ?? 0),
        (int)($n['updated_at'] ?? 0),
        (int)!empty($n['deleted']),
        $ts,
    ];
    $getNote->execute([$uid, $n['uuid']]);
    $existing = $getNote->fetchColumn();
    if ($existing === false) {
        $insNote->execute(array_merge([$uid, $n['uuid']], $vals));
        $saved['notes']++;
    } elseif ((int)$existing <= $vals[7]) {
        $updNote->execute(array_merge($vals, [$uid, $n['uuid']]));
        $saved['notes']++;
    } else {
        $saved['skipped']++; // server has a newer edit
    }
}

$getFolder = $pdo->prepare('SELECT updated_at FROM pn_folders WHERE user_id = ? AND uuid = ? FOR UPDATE');
$insFolder = $pdo->prepare(
    'INSERT INTO pn_folders (user_id, uuid, name, updated_at, deleted, server_ts) VALUES (?, ?, ?, ?, ?, ?)'
);
$updFolder = $pdo->prepare(
    'UPDATE pn_folders SET name = ?, updated_at = ?, deleted = ?, server_ts = ? WHERE user_id = ? AND uuid = ?'
);

foreach ($folders as $f) {
    if (!is_array($f) || !valid_uuid($f['uuid'] ?? null)) {
        $saved['skipped']++;
        continue;
    }
    $name = mb_substr(trim((string)($f['name'] ?? '')), 0, 255);
    $upd = (int)($f['updated_at'] ?? 0);
    $del = (int)!empty($f['deleted']);
    $getFolder->execute([$uid, $f['uuid']]);
    $existing = $getFolder->fetchColumn();
    if ($existing === false) {
        $insFolder->execute([$uid, $f['uuid'], $name, $upd, $del, $ts]);
        $saved['folders']++;
    } elseif ((int)$existing <= $upd) {
        $updFolder->execute([$name, $upd, $del, $ts, $uid, $f['uuid']]);
        $saved['folders']++;
    } else {
        $saved['skipped']++;
    }
}

$pdo->commit();
json_out(true, 'Saved', $saved);
