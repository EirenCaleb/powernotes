<?php
declare(strict_types=1);
require __DIR__ . '/lib.php';
require_method('POST');

$in = input();
$email = strtolower(trim((string)($in['email'] ?? '')));
$pass = (string)($in['password'] ?? '');

$st = db()->prepare('SELECT id, password_hash FROM pn_users WHERE email = ?');
$st->execute([$email]);
$user = $st->fetch();

if (!$user || !password_verify($pass, $user['password_hash'])) {
    usleep(700000); // slow down guessing
    json_out(false, 'Wrong email or password.', null, 401);
}

if (password_needs_rehash($user['password_hash'], PASSWORD_DEFAULT)) {
    db()->prepare('UPDATE pn_users SET password_hash = ? WHERE id = ?')
        ->execute([password_hash($pass, PASSWORD_DEFAULT), $user['id']]);
}

json_out(true, 'Signed in', ['token' => issue_token((int)$user['id']), 'email' => $email]);
