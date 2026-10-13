$ErrorActionPreference = 'Stop'
$dir = $PSScriptRoot
$site = Join-Path $dir '_site'
if (Test-Path $site) { Remove-Item $site -Recurse -Force }
New-Item -ItemType Directory -Force (Join-Path $site 'media') | Out-Null
$html = [IO.File]::ReadAllText((Join-Path $dir 'index.html'))
$site_url = 'https://fritetas-sketch.github.io/fritas-workshop-stats/'
$enc = { param($s) [System.Net.WebUtility]::HtmlEncode($s) }
$og = if (Test-Path (Join-Path $dir 'og.json')) { Get-Content (Join-Path $dir 'og.json') -Raw -Encoding utf8 | ConvertFrom-Json } else { $null }
$title = 'Workshop Fritas'
$m = [regex]::Match($html, '<title>(.*?)</title>')
if ($m.Success) { $title = $m.Groups[1].Value; $html = $html.Remove($m.Index, $m.Length) }
$meta = '<title>' + (& $enc $title) + '</title><meta name="theme-color" content="#6d5dfc">'
if (Test-Path (Join-Path $dir 'favicon.png')) { $meta += '<link rel="icon" type="image/png" href="favicon.png"><link rel="apple-touch-icon" href="favicon.png">' }
if ($og) {
  $img = $site_url + 'og.png?v=' + $og.v
  $meta += '<meta name="description" content="' + (& $enc $og.description) + '"><meta property="og:type" content="website"><meta property="og:site_name" content="Workshop Fritas"><meta property="og:url" content="' + $site_url + '"><meta property="og:title" content="' + (& $enc $og.title) + '"><meta property="og:description" content="' + (& $enc $og.description) + '"><meta property="og:image" content="' + $img + '"><meta property="og:image:width" content="1200"><meta property="og:image:height" content="630"><meta name="twitter:card" content="summary_large_image"><meta name="twitter:title" content="' + (& $enc $og.title) + '"><meta name="twitter:description" content="' + (& $enc $og.description) + '"><meta name="twitter:image" content="' + $img + '">'
}
$page = '<!doctype html><html lang="fr"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">' + $meta + '<style>:root{padding-top:env(safe-area-inset-top,0px);padding-bottom:env(safe-area-inset-bottom,0px)}body{margin:0}img{max-width:100%}[hidden]{display:none!important}</style></head><body>' + $html + '</body></html>'
if ($env:STEAM_API_KEY -and $page.Contains($env:STEAM_API_KEY.Trim())) { throw 'La clé Steam a été trouvée dans la page : publication annulée.' }
[IO.File]::WriteAllText((Join-Path $site 'index.html'), $page, (New-Object Text.UTF8Encoding $false))
foreach ($m in [regex]::Matches($html, 'media/[0-9A-Za-z\-]+\.(gif|jpg|png)') | ForEach-Object { $_.Value } | Sort-Object -Unique) {
  $p = Join-Path $dir $m
  if (Test-Path $p) { Copy-Item $p (Join-Path $site $m) }
}
Get-ChildItem (Join-Path $dir 'media') -Filter '*_t.jpg' -ErrorAction SilentlyContinue | ForEach-Object { Copy-Item $_.FullName (Join-Path $site ('media/' + $_.Name)) }
if (Test-Path (Join-Path $dir 'promo')) { New-Item -ItemType Directory -Force (Join-Path $site 'promo') | Out-Null; Copy-Item (Join-Path $dir 'promo/*.gif') (Join-Path $site 'promo') }
foreach ($x in 'og.png', 'favicon.png') { if (Test-Path (Join-Path $dir $x)) { Copy-Item (Join-Path $dir $x) (Join-Path $site $x) } }
New-Item -ItemType File (Join-Path $site '.nojekyll') -Force | Out-Null
Write-Host "Site prêt : $((Get-ChildItem $site -Recurse -File).Count) fichiers"
