<?php
declare(strict_types=1);

// Public, read-only view of a shared note.
$cfgPaths = [dirname(__DIR__) . '/powernotes_config.php', dirname(__DIR__, 2) . '/powernotes_config.php', __DIR__ . '/powernotes_config.local.php'];
$cfg = null;
foreach ($cfgPaths as $p) {
    if (is_file($p)) {
        $cfg = require $p;
        break;
    }
}
$token = (string)($_GET['t'] ?? '');
$note = null;
if ($cfg && preg_match('/^[a-f0-9]{32}$/', $token)) {
    try {
        $pdo = new PDO(
            'mysql:host=' . $cfg['db_host'] . ';dbname=' . $cfg['db_name'] . ';charset=utf8mb4',
            $cfg['db_user'],
            $cfg['db_pass'],
            [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION, PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC]
        );
        $st = $pdo->prepare('SELECT title, body, updated_at FROM pn_shares WHERE token = ?');
        $st->execute([$token]);
        $note = $st->fetch() ?: null;
    } catch (Throwable $e) {
        error_log('[PowerNotes] share.php: ' . $e->getMessage());
    }
}
if (!$note) {
    http_response_code(404);
}
header('X-Robots-Tag: noindex');
$title = $note ? $note['title'] : 'Note not found';
?>
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex">
<title><?= htmlspecialchars($title) ?> · PowerNotes</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link href="https://fonts.googleapis.com/css2?family=Plus+Jakarta+Sans:wght@400;600;800&display=swap" rel="stylesheet">
<style>
  :root { --bg:#f7f7fa; --card:#fff; --text:#1d1f27; --muted:#6b6f80; --accent:#4f46e5; --line:#e4e5ee; }
  @media (prefers-color-scheme: dark) { :root { --bg:#111318; --card:#1a1d24; --text:#e8e9ef; --muted:#9a9eb0; --accent:#8b85ff; --line:#2a2e38; } }
  * { box-sizing: border-box; }
  body { margin:0; background:var(--bg); color:var(--text); font:17px/1.65 "Plus Jakarta Sans", system-ui, sans-serif; }
  main { max-width:760px; margin:32px auto; padding:32px 28px; background:var(--card); border:1px solid var(--line); border-radius:18px; box-shadow:0 8px 30px rgba(0,0,0,.05); }
  @media (max-width:640px){ main { margin:0; border-radius:0; border:0; padding:24px 16px; } }
  h1,h2,h3 { line-height:1.25; font-weight:800; }
  .title { font-size:2rem; margin:0 0 4px; }
  .meta { color:var(--muted); font-size:.85rem; margin-bottom:24px; }
  blockquote { margin:16px 0; padding:8px 16px; border-left:3px solid var(--accent); color:var(--muted); font-style:italic; background:color-mix(in srgb, var(--accent) 7%, transparent); border-radius:0 10px 10px 0; }
  pre { background:color-mix(in srgb, var(--text) 6%, transparent); padding:14px; border-radius:10px; overflow:auto; }
  code { font-family: ui-monospace, Consolas, monospace; font-size:.9em; }
  table { border-collapse:collapse; width:100%; display:block; overflow-x:auto; }
  th,td { border:1px solid var(--line); padding:6px 10px; text-align:left; }
  a { color:var(--accent); }
  ul.contains-task-list { list-style:none; padding-left:4px; }
  footer { text-align:center; color:var(--muted); font-size:.8rem; margin:16px 0 32px; }
</style>
</head>
<body>
<main>
<?php if ($note): ?>
  <h1 class="title"><?= htmlspecialchars($note['title']) ?></h1>
  <div class="meta">Shared from PowerNotes · updated <?= htmlspecialchars(date('M j, Y', strtotime($note['updated_at']))) ?></div>
  <article id="content"></article>
  <script type="application/json" id="md"><?= json_encode($note['body'], JSON_HEX_TAG | JSON_HEX_AMP | JSON_HEX_APOS | JSON_HEX_QUOT) ?></script>
  <script src="https://cdnjs.cloudflare.com/ajax/libs/marked/12.0.2/marked.min.js"></script>
  <script src="https://cdnjs.cloudflare.com/ajax/libs/dompurify/3.1.6/purify.min.js"></script>
  <script>
    let md = JSON.parse(document.getElementById('md').textContent);
    md = md.replace(/\[\[([^\]\n]+)\]\]/g, '**$1**')
           .replace(/@(remind|due)\(([^)]+)\)/g, '`⏰ $2`');
    document.getElementById('content').innerHTML = DOMPurify.sanitize(marked.parse(md, { gfm: true, breaks: true }));
  </script>
<?php else: ?>
  <h1 class="title">Note not found</h1>
  <p>This link was turned off or never existed.</p>
<?php endif; ?>
</main>
<footer>PowerNotes</footer>
</body>
</html>
