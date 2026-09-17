<!DOCTYPE html>
<html lang="uk">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <meta name="robots" content="noindex, nofollow">
    <title>{{ $title ?? 'Документація для фронтенду' }}</title>
    <style>
        :root {
            --bg: #fbfbfa; --panel: #fff; --ink: #1d1d1f; --muted: #6b6b70;
            --line: #e3e3e0; --accent: #1b5e9e; --warn: #b4341c; --ok: #1f6f43;
            --code-bg: #f4f4f2;
        }
        @media (prefers-color-scheme: dark) {
            :root {
                --bg: #16171a; --panel: #1e1f23; --ink: #e8e8ea; --muted: #9a9aa2;
                --line: #2e3036; --accent: #6fb0f0; --warn: #f08a76; --ok: #74c99a;
                --code-bg: #26272c;
            }
        }
        * { box-sizing: border-box; }
        body {
            margin: 0; background: var(--bg); color: var(--ink);
            font: 16px/1.6 -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
        }
        .wrap { max-width: 900px; margin: 0 auto; padding: 0 20px 80px; }
        header.top { border-bottom: 1px solid var(--line); background: var(--panel); margin-bottom: 32px; }
        header.top .wrap { padding: 16px 20px; display: flex; gap: 16px; align-items: baseline; flex-wrap: wrap; }
        header.top a.home { font-weight: 600; text-decoration: none; color: var(--ink); }
        header.top .spacer { flex: 1; }
        header.top a.meta { font-size: 13px; color: var(--muted); }
        a { color: var(--accent); }
        h1 { font-size: 28px; line-height: 1.25; margin: 0 0 8px; }
        h2 { font-size: 21px; margin: 32px 0 12px; }
        h3 { font-size: 17px; margin: 24px 0 8px; }
        .lede { color: var(--muted); margin: 0 0 28px; }
        .area { margin: 0 0 36px; }
        .area > h2 { border-bottom: 1px solid var(--line); padding-bottom: 8px; }
        .cards { display: grid; gap: 10px; grid-template-columns: repeat(auto-fill, minmax(260px, 1fr)); }
        .card {
            display: block; background: var(--panel); border: 1px solid var(--line);
            border-radius: 10px; padding: 14px 16px; text-decoration: none; color: inherit;
        }
        .card:hover { border-color: var(--accent); }
        .card .name { font-weight: 600; display: block; margin-bottom: 6px; }
        .card .sub { font-size: 13px; color: var(--muted); }
        .badge {
            display: inline-block; font-size: 11px; line-height: 1.6; padding: 0 7px;
            border-radius: 999px; border: 1px solid var(--line); color: var(--muted);
            vertical-align: 1px; margin-left: 6px; white-space: nowrap;
        }
        .badge.breaking { color: var(--warn); border-color: var(--warn); }
        .badge.stale { text-decoration: line-through; }
        .badge.ru { color: var(--muted); }
        .badge.gap { color: var(--warn); border-color: var(--warn); }
        ol.deltas { list-style: none; padding: 0; margin: 0; }
        ol.deltas li { border-bottom: 1px solid var(--line); padding: 12px 0; }
        ol.deltas li:last-child { border-bottom: 0; }
        ol.deltas .date { color: var(--muted); font-variant-numeric: tabular-nums; font-size: 13px; margin-right: 10px; }
        ol.deltas a { text-decoration: none; font-weight: 500; }
        ol.deltas a:hover { text-decoration: underline; }
        .files { margin: 16px 0 0; padding: 0; list-style: none; font-size: 14px; }
        .files li { margin: 4px 0; }
        .doc { background: var(--panel); border: 1px solid var(--line); border-radius: 12px; padding: 4px 28px 28px; margin-top: 20px; }
        .doc table { border-collapse: collapse; width: 100%; margin: 16px 0; font-size: 14px; display: block; overflow-x: auto; }
        .doc th, .doc td { border: 1px solid var(--line); padding: 6px 10px; text-align: left; vertical-align: top; }
        .doc th { background: var(--code-bg); }
        .doc pre { background: var(--code-bg); padding: 12px 14px; border-radius: 8px; overflow-x: auto; font-size: 13px; }
        .doc code { background: var(--code-bg); padding: 1px 5px; border-radius: 4px; font-size: 90%; }
        .doc pre code { background: none; padding: 0; }
        .doc blockquote { border-left: 3px solid var(--line); margin: 16px 0; padding: 2px 0 2px 16px; color: var(--muted); }
        .doc img { max-width: 100%; }
        .notice { border: 1px solid var(--warn); color: var(--warn); border-radius: 8px; padding: 10px 14px; margin: 16px 0; font-size: 14px; }
        .toolbar { display: flex; gap: 12px; flex-wrap: wrap; align-items: center; margin: 14px 0 0; font-size: 14px; }
        .crumb { font-size: 14px; color: var(--muted); margin-bottom: 12px; }
        .crumb a { text-decoration: none; }
    </style>
</head>
<body>
<header class="top">
    <div class="wrap">
        <a class="home" href="{{ route('docs-portal.index', ['token' => $token]) }}">Документація бекенду</a>
        <span class="spacer"></span>
        <a class="meta" href="{{ route('docs-portal.json', ['token' => $token]) }}">index.json для агента</a>
    </div>
</header>
<main class="wrap">
    @yield('content')
</main>
</body>
</html>
