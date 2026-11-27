<?php
declare(strict_types=1);

// Shared helpers for every PowerNotes API endpoint.

header('Content-Type: application/json; charset=utf-8');
header('X-Content-Type-Options: nosniff');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Headers: Authorization, Content-Type');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
if (($_SERVER['REQUEST_METHOD'] ?? '') === 'OPTIONS') {
    http_response_code(204);
    exit;
}

function config(): array
{
    static $cfg = null;
    if ($cfg !== null) {
        return $cfg;
    }
    $candidates = [
        dirname(__DIR__, 2) . '/powernotes_config.php', // above public_html (site root install)
        dirname(__DIR__, 3) . '/powernotes_config.php', // above public_html (subfolder install)
        dirname(__DIR__) . '/powernotes_config.local.php', // last resort, blocked by .htaccess
    ];
    foreach ($candidates as $path) {
        if (is_file($path)) {
            $cfg = require $path;
            return $cfg;
        }
    }
    json_out(false, 'Server config missing. Upload powernotes_config.php (see README).', null, 500);
}

// Turn warnings and deprecations into logged failures instead of broken JSON.
set_error_handler(static function (int $no, string $str, string $file, int $line): bool {
    throw new ErrorException($str, 0, $no, $file, $line);
});
set_exception_handler(static function (Throwable $e): void {
    error_log('[PowerNotes] ' . $e->getMessage() . ' in ' . $e->getFile() . ':' . $e->getLine());
    $debug = false;
    try {
        $debug = (bool)(config()['debug'] ?? false);
    } catch (Throwable) {
    }
    json_out(false, $debug ? $e->getMessage() . ' (' . basename($e->getFile()) . ':' . $e->getLine() . ')' : 'Server error', null, 500);
});

function db(): PDO
{
    static $pdo = null;
    if ($pdo === null) {
        $c = config();
        $pdo = new PDO(
            'mysql:host=' . $c['db_host'] . ';dbname=' . $c['db_name'] . ';charset=utf8mb4',
            $c['db_user'],
            $c['db_pass'],
            [
                PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
                PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
                PDO::ATTR_EMULATE_PREPARES => false,
            ]
        );
    }
    return $pdo;
}

function json_out(bool $ok, string $message = '', mixed $data = null, int $status = 200): never
{
    http_response_code($status);
    echo json_encode(['ok' => $ok, 'message' => $message, 'data' => $data], JSON_UNESCAPED_UNICODE);
    exit;
}

function input(): array
{
    static $in = null;
    if ($in === null) {
        $raw = file_get_contents('php://input') ?: '';
        $in = json_decode($raw, true);
        if (!is_array($in)) {
            $in = [];
        }
    }
    return $in;
}

function require_method(string $method): void
{
    if (($_SERVER['REQUEST_METHOD'] ?? '') !== $method) {
        json_out(false, 'Method not allowed', null, 405);
    }
}

function now_ms(): int
{
    return (int) floor(microtime(true) * 1000);
}

function bearer_token(): string
{
    $h = $_SERVER['HTTP_AUTHORIZATION'] ?? $_SERVER['REDIRECT_HTTP_AUTHORIZATION'] ?? '';
    if ($h === '' && function_exists('getallheaders')) {
        foreach (getallheaders() as $k => $v) {
            if (strcasecmp($k, 'Authorization') === 0) {
                $h = $v;
            }
        }
    }
    return preg_match('/^Bearer\s+([A-Za-z0-9]+)$/', trim($h), $m) ? $m[1] : '';
}

/** Returns the signed-in user's id or stops with 401. */
function auth_user(): int
{
    $token = bearer_token();
    if ($token === '') {
        json_out(false, 'Please sign in again.', null, 401);
    }
    $st = db()->prepare('SELECT user_id FROM pn_tokens WHERE token_hash = ?');
    $st->execute([hash('sha256', $token)]);
    $uid = $st->fetchColumn();
    if ($uid === false) {
        json_out(false, 'Session expired. Please sign in again.', null, 401);
    }
    db()->prepare('UPDATE pn_tokens SET last_used_at = NOW() WHERE token_hash = ?')
        ->execute([hash('sha256', $token)]);
    return (int) $uid;
}

function issue_token(int $userId): string
{
    $token = bin2hex(random_bytes(32));
    db()->prepare('INSERT INTO pn_tokens (token_hash, user_id) VALUES (?, ?)')
        ->execute([hash('sha256', $token), $userId]);
    return $token;
}

function valid_uuid(mixed $v): bool
{
    return is_string($v) && preg_match('/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i', $v) === 1;
}
