param([string[]]$ExtraIds = @(), [switch]$Fast)

$ErrorActionPreference = 'Stop'
try { Add-Type -AssemblyName System.Drawing } catch {}
$steamId = '76561198172408791'
$dir = $PSScriptRoot
$known = @(
  '3389728250','3164171897','3001397905','3812999330','3812775577','3813193355','3813246511','3417993003','3223838856',
  '3811510024','3811516550','3808370112','3812613764','3808370009','3812277577','3542961565','3784198948','3706396434',
  '3798583072','3798581460','3798579052','3743871687','3743426205','3084828206','3796875668','3812203759','3595572960',
  '3567911349','3479527645','3812488096','3812214020','3810364638','3812532795','3794535009','3790354929','3594713545',
  '3702833441','3659150392','3164156044','3389795738','3164167970','3708047631','3791205525','3787456835'
)

$ids = New-Object System.Collections.Generic.HashSet[string]
foreach ($i in $known + $ExtraIds) { [void]$ids.Add($i) }
$idFile = Join-Path $dir 'ids.txt'
if (Test-Path $idFile) { foreach ($i in (Get-Content $idFile)) { if ($i -match '^\d+$') { [void]$ids.Add($i) } } }

$followers = $null
foreach ($section in @('', '&section=collections')) {
  for ($p = 1; $p -le 50; $p++) {
    $h = (Invoke-WebRequest -UseBasicParsing "https://steamcommunity.com/profiles/$steamId/myworkshopfiles/?appid=4000&p=$p&numperpage=30$section").Content
    if ($null -eq $followers -and $h -match 'class="followStat">\s*([\d,\.]+)') { $followers = [int]($Matches[1] -replace '[,\.]', '') }
    $before = $ids.Count
    foreach ($m in [regex]::Matches($h, 'sharedfiles/filedetails/\?id=(\d+)')) { [void]$ids.Add($m.Groups[1].Value) }
    if ($ids.Count -eq $before) { break }
  }
}

$body = @{ itemcount = $ids.Count }
$n = 0
foreach ($i in $ids) { $body["publishedfileids[$n]"] = $i; $n++ }
$details = (Invoke-RestMethod -Method Post -Uri 'https://api.steampowered.com/ISteamRemoteStorage/GetPublishedFileDetails/v1/' -Body $body).response.publishedfiledetails
$mine = @($details | Where-Object { $_.result -eq 1 -and $_.creator -eq $steamId -and -not (@($_.tags | ForEach-Object { $_.tag }) -contains 'map') })

$cbody = @{ collectioncount = $mine.Count }
for ($k = 0; $k -lt $mine.Count; $k++) { $cbody["publishedfileids[$k]"] = $mine[$k].publishedfileid }
$colls = @{}
$collKids = @{}
foreach ($c in (Invoke-RestMethod -Method Post -Uri 'https://api.steampowered.com/ISteamRemoteStorage/GetCollectionDetails/v1/' -Body $cbody).response.collectiondetails) {
  if ($c.result -eq 1) { $colls[$c.publishedfileid] = @($c.children).Count; $collKids[[string]$c.publishedfileid] = @($c.children | ForEach-Object { [string]$_.publishedfileid }) }
}

$votes = @{}
$keyFile = Join-Path $dir 'steam_api_key.txt'
if ($env:STEAM_API_KEY -or (Test-Path $keyFile)) {
  $apiKey = if ($env:STEAM_API_KEY) { $env:STEAM_API_KEY.Trim() } else { (Get-Content $keyFile -Raw).Trim() }
  if ($apiKey -match '^[0-9A-Fa-f]{32}$') {
    try {
      $q = "key=$apiKey&includevotes=true&includeadditionalpreviews=true"
      for ($k = 0; $k -lt $mine.Count; $k++) { $q += "&publishedfileids[$k]=$($mine[$k].publishedfileid)" }
      foreach ($v in (Invoke-RestMethod "https://api.steampowered.com/IPublishedFileService/GetDetails/v1/?$q").response.publishedfiledetails) {
        if ($v.vote_data) { $votes[[string]$v.publishedfileid] = $v }
      }
    } catch { Write-Host "Votes Steam indisponibles : $($_.Exception.Message)" }
  }
}

$mediaDir = Join-Path $dir 'media'
New-Item -ItemType Directory -Force $mediaDir | Out-Null
$mcFile = Join-Path $dir 'media_cache.json'
$mc = @{}
if (Test-Path $mcFile) { (Get-Content $mcFile -Raw -Encoding utf8 | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $mc[$_.Name] = $_.Value } }
function Get-MainMedia([string]$id, [string]$url) {
  $k = "main|$url"
  if ($mc.ContainsKey($k) -and (Test-Path (Join-Path $dir $mc[$k]))) { return $mc[$k] }
  try { $b = [byte[]](Invoke-WebRequest -UseBasicParsing $url).Content } catch { return $null }
  if ($b.Length -lt 16) { return $null }
  $ext = if ($b[0] -eq 0x47 -and $b[1] -eq 0x49 -and $b[2] -eq 0x46) { 'gif' } elseif ($b[0] -eq 0x89 -and $b[1] -eq 0x50) { 'png' } else { 'jpg' }
  $rel = "media/$id.$ext"
  [IO.File]::WriteAllBytes((Join-Path $dir $rel), $b)
  $mc[$k] = $rel
  return $rel
}
function Get-StillMedia([string]$name, [string]$url) {
  $k = "still|$url"
  if ($mc.ContainsKey($k) -and (Test-Path (Join-Path $dir $mc[$k]))) { return $mc[$k] }
  try {
    $b = [byte[]](Invoke-WebRequest -UseBasicParsing $url).Content
    $src = [Drawing.Image]::FromStream((New-Object IO.MemoryStream(,$b)))
    $s = [Math]::Min(1.0, 900 / [Math]::Max($src.Width, $src.Height))
    $bmp = New-Object Drawing.Bitmap ([int]($src.Width * $s)), ([int]($src.Height * $s))
    $g = [Drawing.Graphics]::FromImage($bmp)
    $g.InterpolationMode = 'HighQualityBicubic'
    $g.DrawImage($src, 0, 0, $bmp.Width, $bmp.Height)
    $rel = "media/$name.jpg"
    $bmp.Save((Join-Path $dir $rel), [Drawing.Imaging.ImageFormat]::Jpeg)
    $g.Dispose(); $bmp.Dispose(); $src.Dispose()
    $mc[$k] = $rel
    return $rel
  } catch { return $null }
}

$cacheFile = Join-Path $dir 'pages_cache.json'
$cache = @{}
if (Test-Path $cacheFile) { (Get-Content $cacheFile -Raw -Encoding utf8 | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $cache[$_.Name] = $_.Value } }

$thumbFile = Join-Path $dir 'thumbs_cache.json'
$thumbs = @{}
if (Test-Path $thumbFile) { (Get-Content $thumbFile -Raw -Encoding utf8 | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $thumbs[$_.Name] = $_.Value } }

$now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$refresh = @{}
if ($Fast) {
  $mine | Sort-Object { $cid = [string]$_.publishedfileid; if ($cache.ContainsKey($cid) -and $cache[$cid].u) { [long]$cache[$cid].u } else { 0 } } | Select-Object -First 4 | ForEach-Object { $refresh[[string]$_.publishedfileid] = $true }
}

$items = foreach ($d in $mine) {
  $rating = $null; $stars = $null; $comments = 0; $kind = 'item'
  $page = ''
  if (-not $Fast -or $refresh.ContainsKey([string]$d.publishedfileid)) { try {
    $page = ''
    for ($try = 0; $try -lt $(if ($Fast) { 2 } else { 6 }) -and $page -notmatch '_totalcount"'; $try++) {
      if ($try) { Start-Sleep -Seconds (5 * $try) }
      try { $page = (Invoke-WebRequest -UseBasicParsing -Headers @{ 'Accept-Language' = 'en' } "https://steamcommunity.com/sharedfiles/filedetails/?id=$($d.publishedfileid)&l=english").Content } catch { $page = '' }
    }
    Start-Sleep -Milliseconds 1500
    if ($page -match 'class="numRatings">\s*([\d,\.]+)') { $rating = [int]($Matches[1] -replace '[,\.]', '') }
    if ($page -match 'images/sharedfiles/(\d)-star_large') { $stars = [int]$Matches[1] }
    if ($page -match '_totalcount">\s*([\d,\.]+)') { $comments = [int]($Matches[1] -replace '[,\.]', '') }
  } catch {} }
  $key = [string]$d.publishedfileid
  if ($page -match '_totalcount"') { $cache[$key] = [pscustomobject]@{ r = $rating; s = $stars; c = $comments; u = $now } }
  else {
    if ($cache.ContainsKey($key)) { $rating = $cache[$key].r; $stars = $cache[$key].s; $comments = $cache[$key].c }
    if ($refresh.ContainsKey($key)) { $cache[$key] = [pscustomobject]@{ r = $rating; s = $stars; c = $comments; u = $now } }
  }
  $children = 0
  if ($colls.ContainsKey($d.publishedfileid)) { $kind = 'collection'; $children = $colls[$d.publishedfileid] }
  $thumb = $null
  if ($thumbs.ContainsKey("$($d.preview_url)|160")) { $thumb = $thumbs["$($d.preview_url)|160"] }
  else { try {
    $bytes = (Invoke-WebRequest -UseBasicParsing "$($d.preview_url)?imw=256&imh=256&ima=fit&impolicy=Letterbox").Content
    $ms = New-Object IO.MemoryStream(,$bytes)
    $src = [Drawing.Image]::FromStream($ms)
    $bmp = New-Object Drawing.Bitmap 160, 160
    $g = [Drawing.Graphics]::FromImage($bmp)
    $g.InterpolationMode = 'HighQualityBicubic'
    $g.DrawImage($src, 0, 0, 160, 160)
    $out = New-Object IO.MemoryStream
    $bmp.Save($out, [Drawing.Imaging.ImageFormat]::Jpeg)
    $thumb = 'data:image/jpeg;base64,' + [Convert]::ToBase64String($out.ToArray())
    $g.Dispose(); $bmp.Dispose(); $src.Dispose()
    $thumbs["$($d.preview_url)|160"] = $thumb
  } catch {} }
  [pscustomobject]@{
    id = $d.publishedfileid
    thumb = $thumb
    title = $d.title
    kind = $kind
    children = $children
    kids = $(if ($collKids.ContainsKey([string]$d.publishedfileid)) { $collKids[[string]$d.publishedfileid] } else { $null })
    preview = $d.preview_url
    size = [int64]$d.file_size
    created = [int64]$d.time_created
    updated = [int64]$d.time_updated
    visibility = [int]$d.visibility
    subs = [int]$d.subscriptions
    lifetimeSubs = [int]$d.lifetime_subscriptions
    favs = [int]$d.favorited
    lifetimeFavs = [int]$d.lifetime_favorited
    views = [int]$d.views
    ratings = $rating
    stars = $stars
    comments = $comments
    tags = @($d.tags | ForEach-Object { $_.tag })
    likes = $(if ($votes.ContainsKey($key)) { [int]$votes[$key].vote_data.votes_up } else { $null })
    dislikes = $(if ($votes.ContainsKey($key)) { [int]$votes[$key].vote_data.votes_down } else { $null })
    score = $(if ($votes.ContainsKey($key)) { [double]$votes[$key].vote_data.score } else { $null })
    media = $(if ($kind -eq 'item') { Get-MainMedia $key $d.preview_url } else { $null })
    gallery = @($(if ($kind -eq 'item' -and $votes.ContainsKey($key)) {
      $n = 0
      foreach ($p in @($votes[$key].previews | Where-Object { $_.preview_type -eq 0 -and $_.url } | Select-Object -First 4)) { $n++; Get-StillMedia "$key-$n" $p.url }
    }) | Where-Object { $_ })
    videos = @($(if ($votes.ContainsKey($key)) { @($votes[$key].previews | Where-Object { $_.preview_type -eq 1 -and $_.youtubevideoid } | ForEach-Object { $_.youtubevideoid }) }))
  }
}

foreach ($it in @($items | Where-Object { $_.kind -eq 'item' } | Sort-Object subs -Descending | Select-Object -First 6)) {
  $key = "$($it.preview)|cover"
  if (-not $thumbs.ContainsKey($key)) {
    try {
      $bytes = (Invoke-WebRequest -UseBasicParsing "$($it.preview)?imw=640&imh=640&ima=fit").Content
      $src = [Drawing.Image]::FromStream((New-Object IO.MemoryStream(,$bytes)))
      $k = [Math]::Min(1.0, 560 / [Math]::Max($src.Width, $src.Height))
      $bmp = New-Object Drawing.Bitmap ([int]($src.Width * $k)), ([int]($src.Height * $k))
      $g = [Drawing.Graphics]::FromImage($bmp)
      $g.InterpolationMode = 'HighQualityBicubic'
      $g.DrawImage($src, 0, 0, $bmp.Width, $bmp.Height)
      $out = New-Object IO.MemoryStream
      $bmp.Save($out, [Drawing.Imaging.ImageFormat]::Jpeg)
      $thumbs[$key] = 'data:image/jpeg;base64,' + [Convert]::ToBase64String($out.ToArray())
      $g.Dispose(); $bmp.Dispose(); $src.Dispose()
    } catch {}
  }
  if ($thumbs.ContainsKey($key)) { $it | Add-Member -NotePropertyName cover -NotePropertyValue $thumbs[$key] -Force }
}

$hasKey = $apiKey -match '^[0-9A-Fa-f]{32}$'
$mineIds = New-Object System.Collections.Generic.HashSet[string]
foreach ($it in $items) { if ($it.kind -eq 'item') { [void]$mineIds.Add([string]$it.id) } }
$RANKQ = [ordered]@{ d1 = 'query_type=3&days=1'; d7 = 'query_type=3&days=7'; d30 = 'query_type=3&days=30'; d90 = 'query_type=3&days=90'; d365 = 'query_type=3&days=365'; cv = 'query_type=3&days=7&requiredtags[0]=Vehicle'; cw = 'query_type=3&days=7&requiredtags[0]=Weapon'; cm = 'query_type=3&days=7&requiredtags[0]=Model' }
$ranks = @{}
foreach ($rk in $RANKQ.Keys) { $ranks[$rk] = @{} }
if ($hasKey) {
  foreach ($rk in $RANKQ.Keys) {
    for ($pg = 1; $pg -le 3; $pg++) {
      try {
        $q = Invoke-RestMethod "https://api.steampowered.com/IPublishedFileService/QueryFiles/v1/?key=$apiKey&appid=4000&numperpage=100&page=$pg&$($RANKQ[$rk])"
        $l = @($q.response.publishedfiledetails | ForEach-Object { [string]$_.publishedfileid })
        for ($k = 0; $k -lt $l.Count; $k++) { if ($mineIds.Contains($l[$k])) { $ranks[$rk][$l[$k]] = ($pg - 1) * 100 + $k + 1 } }
        if ($l.Count -lt 100) { break }
      } catch {}
    }
  }
}
foreach ($it in $items) {
  $o = [ordered]@{}
  foreach ($rk in $RANKQ.Keys) { if ($ranks[$rk].ContainsKey([string]$it.id)) { $o[$rk] = $ranks[$rk][[string]$it.id] } }
  $it | Add-Member -NotePropertyName rk -NotePropertyValue ([pscustomobject]$o) -Force
  $it | Add-Member -NotePropertyName r1 -NotePropertyValue $(if ($ranks.d1.ContainsKey([string]$it.id)) { $ranks.d1[[string]$it.id] } else { $null }) -Force
  $it | Add-Member -NotePropertyName r7 -NotePropertyValue $(if ($ranks.d7.ContainsKey([string]$it.id)) { $ranks.d7[[string]$it.id] } else { $null }) -Force
}
$cmtFile = Join-Path $dir 'comments_cache.json'
$cmts = @{}
if (Test-Path $cmtFile) { (Get-Content $cmtFile -Raw -Encoding utf8 | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $cmts[$_.Name] = $_.Value } }
$rx = [regex]'(?s)id="comment_(\d+)".*?data-miniprofile="(\d+)".*?<bdi>(.*?)</bdi>.*?data-timestamp="(\d+)".*?id="comment_content_\1">(.*?)</div>'
foreach ($it in @($items | Where-Object { $_.kind -eq 'item' })) {
  try {
    $r = Invoke-RestMethod "https://steamcommunity.com/comment/PublishedFile_Public/render/$steamId/$($it.id)/?start=0&count=50"
    if ($r.success) {
      foreach ($m in $rx.Matches([string]$r.comments_html)) {
        $txt = $m.Groups[5].Value -replace '(?i)<br\s*/?>', "`n" -replace '<img[^>]*alt="([^"]*)"[^>]*>', '$1' -replace '<[^>]+>', ''
        $txt = [System.Net.WebUtility]::HtmlDecode($txt).Trim()
        if ($txt.Length -gt 400) { $txt = $txt.Substring(0, 400) + '…' }
        $cmts[$m.Groups[1].Value] = [pscustomobject]@{
          a = [string]$it.id
          u = [string](76561197960265728 + [int64]$m.Groups[2].Value)
          n = [System.Net.WebUtility]::HtmlDecode($m.Groups[3].Value).Trim()
          t = [int64]$m.Groups[4].Value
          x = $txt
        }
      }
    }
  } catch {}
  Start-Sleep -Milliseconds 300
}
($cmts | ConvertTo-Json -Depth 4 -Compress) | Out-File $cmtFile -Encoding utf8

$plFile = Join-Path $dir 'players_cache.json'
$players = @{}
if (Test-Path $plFile) { (Get-Content $plFile -Raw -Encoding utf8 | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $players[$_.Name] = $_.Value } }
if ($hasKey) {
  $need = @($cmts.Values | ForEach-Object { $_.u } | Sort-Object -Unique | Where-Object { -not $players.ContainsKey($_) })
  for ($k = 0; $k -lt $need.Count; $k += 100) {
    $batch = $need[$k..([Math]::Min($k + 99, $need.Count - 1))]
    try {
      $pr = Invoke-RestMethod "https://api.steampowered.com/ISteamUser/GetPlayerSummaries/v2/?key=$apiKey&steamids=$($batch -join ',')"
      foreach ($p in $pr.response.players) { $players[[string]$p.steamid] = [string]$p.loccountrycode }
      foreach ($b in $batch) { if (-not $players.ContainsKey($b)) { $players[$b] = '' } }
    } catch {}
  }
  ($players | ConvertTo-Json -Compress) | Out-File $plFile -Encoding utf8
}
$allC = @($cmts.GetEnumerator() | ForEach-Object { $_.Value | Add-Member -NotePropertyName id -NotePropertyValue $_.Key -Force -PassThru } | Sort-Object t -Descending)
$seen = @{}
$recentCut = [int64]([DateTimeOffset]::UtcNow.ToUnixTimeSeconds()) - 14 * 86400
$keepC = @(@($allC | Select-Object -First 80) + @($allC | Where-Object { $_.t -ge $recentCut }) + @($allC | Group-Object a | ForEach-Object { $_.Group | Select-Object -First 10 }) | Where-Object { if ($seen.ContainsKey($_.id)) { $false } else { $seen[$_.id] = 1; $true } } | Sort-Object t -Descending)
$commentsOut = @($keepC | ForEach-Object { [pscustomobject]@{ a = $_.a; n = $_.n; t = $_.t; x = $_.x; c = $(if ($players.ContainsKey($_.u)) { $players[$_.u] } else { '' }); me = ($_.u -eq $steamId) } })
$countries = @{}
foreach ($u in @($cmts.Values | Where-Object { $_.u -ne $steamId } | ForEach-Object { $_.u } | Sort-Object -Unique)) {
  $cc = if ($players.ContainsKey($u)) { $players[$u] } else { '' }
  if (-not $cc) { $cc = '?' }
  $countries[$cc] = 1 + $(if ($countries.ContainsKey($cc)) { $countries[$cc] } else { 0 })
}

($cache | ConvertTo-Json -Depth 4 -Compress) | Out-File $cacheFile -Encoding utf8
($thumbs | ConvertTo-Json -Compress) | Out-File $thumbFile -Encoding utf8
($mc | ConvertTo-Json -Compress) | Out-File $mcFile -Encoding utf8

$now = [int64]([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())
$histFile = Join-Path $dir 'history.json'
$history = @()
if (Test-Path $histFile) { $history = @((Get-Content $histFile -Raw -Encoding utf8 | ConvertFrom-Json) | ForEach-Object { $_ }) }
$foFile = Join-Path $dir 'followers.json'
$foFresh = $followers
$followersAt = $now
if ($null -ne $followers) { ([pscustomobject]@{ fo = $followers; t = $now } | ConvertTo-Json -Compress) | Out-File $foFile -Encoding utf8 }
elseif (Test-Path $foFile) { $last = Get-Content $foFile -Raw -Encoding utf8 | ConvertFrom-Json; $followers = $last.fo; $followersAt = $last.t }
$snap = [pscustomobject]@{ t = $now; fo = $foFresh; items = @($items | ForEach-Object { [pscustomobject]@{ id = $_.id; s = $_.subs; ls = $_.lifetimeSubs; f = $_.favs; lf = $_.lifetimeFavs; v = $_.views; c = $_.comments; up = $_.likes; dn = $_.dislikes; r1 = $_.r1; r7 = $_.r7; rk = $_.rk } }) }
$hourOf = { param($t) $dt = [DateTimeOffset]::FromUnixTimeSeconds([int64]$t).LocalDateTime; $dt.ToString('yyyyMMddHH') + $(if ($dt.Minute -lt 30) { 'a' } else { 'b' }) }
$nowHour = & $hourOf $now
$history = @($history | Where-Object { (& $hourOf $_.t) -ne $nowHour }) + $snap
$cut = $now - 8 * 86400
$older = @($history | Where-Object { $_.t -lt $cut } | Group-Object { [DateTimeOffset]::FromUnixTimeSeconds($_.t).LocalDateTime.ToString('yyyy-MM-dd') } | ForEach-Object { $_.Group | Sort-Object t | Select-Object -Last 1 })
$history = @(@($older) + @($history | Where-Object { $_.t -ge $cut }) | Sort-Object t)
($history | ConvertTo-Json -Depth 6 -Compress) | Out-File $histFile -Encoding utf8
@($items | ForEach-Object { $_.id }) | Out-File $idFile -Encoding utf8

foreach ($it in $items) { if ($it.media) { $it.thumb = $null; if ($it.PSObject.Properties['cover']) { $it.PSObject.Properties.Remove('cover') } } }
$data = [pscustomobject]@{ steamId = $steamId; generated = $now; followers = $followers; followersAt = $followersAt; comments = $commentsOut; countries = $countries; commentTotal = $cmts.Count; items = @($items); history = $history }
$json = $data | ConvertTo-Json -Depth 8 -Compress
$tpl = Get-Content (Join-Path $dir 'template.html') -Raw -Encoding utf8
$html = $tpl.Replace('/*__DATA__*/null', $json)
[IO.File]::WriteAllText((Join-Path $dir 'index.html'), $html, (New-Object Text.UTF8Encoding $false))
"$($items.Count) objets, $(($items | Measure-Object subs -Sum).Sum) abonnes"
