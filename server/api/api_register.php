<?php
declare(strict_types=1);
require __DIR__ . '/lib.php';
require_method('POST');

$in = input();
$email = strtolower(trim((string)($in['email'] ?? '')));
$pass = (string)($in['password'] ?? '');

if (!filter_var($email, FILTER_VALIDATE_EMAIL)) {
    json_out(false, 'Enter a valid email.', null, 422);
}
if (strlen($pass) < 8) {
    json_out(false, 'Password needs at least 8 characters.', null, 422);
}

$count = (int) db()->query('SELECT COUNT(*) FROM pn_users')->fetchColumn();
if ($count > 0 && empty(config()['allow_register'])) {
    json_out(false, 'Sign-ups are closed on this server. Sign in instead.', null, 403);
}

$st = db()->prepare('SELECT id FROM pn_users WHERE email = ?');
$st->execute([$email]);
if ($st->fetchColumn() !== false) {
    json_out(false, 'That email already has an account. Sign in instead.', null, 409);
}

db()->prepare('INSERT INTO pn_users (email, password_hash) VALUES (?, ?)')
    ->execute([$email, password_hash($pass, PASSWORD_DEFAULT)]);
$uid = (int) db()->lastInsertId();

json_out(true, 'Account created', ['token' => issue_token($uid), 'email' => $email]);
