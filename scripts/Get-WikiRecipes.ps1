<#
  Downloads a class's recipe pages from the FFXIV consolegameswiki
  (https://ffxiv.consolegameswiki.com/wiki/<Class>_Recipes/Level_1_-_9 and so on)
  and saves every recipe, in page order, as one JSON file for
  Convert-RawToCrafting.ps1 -InputJson.

  Each page's "crafting" table is read the same way as in the browser:
    item (+ "Learned from" note), class, level (with any stars after it), type,
    yield, durability, difficulty, max quality (+ synthesis note), ingredients.

  For each page it prints the recipe count and a fingerprint (SHA-256). Running
  scripts/wiki-table-fingerprint.js on the same page in a browser gives the same
  fingerprint when the saved data matches the table on screen exactly.

  Usage (from the repo root):
    .\scripts\Get-WikiRecipes.ps1 -Class Goldsmith
    .\scripts\Convert-RawToCrafting.ps1 -InputJson <printed path> -DryRun
    .\scripts\Convert-RawToCrafting.ps1 -InputJson <printed path>

  -Pages picks other pages (default: all 16 level pages, Level_1_-_9 to Level_100).
  -OutFile picks the output path (default: %TEMP%\FFXIVRadar-wiki\<class>_recipes.json).
#>
param(
  [Parameter(Mandatory)] [string]$Class,
  [string[]]$Pages = @('Level_1_-_9','Level_10_-_19','Level_20_-_29','Level_30_-_39','Level_40_-_49',
                       'Level_50','Level_51_-_59','Level_60','Level_61_-_69','Level_70','Level_71_-_79',
                       'Level_80','Level_81_-_89','Level_90','Level_91_-_99','Level_100'),
  [string]$OutFile = (Join-Path $env:TEMP ("FFXIVRadar-wiki\{0}_recipes.json" -f $Class.ToLower()))
)
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Like the browser's innerText with whitespace collapsed: <br> -> space, tags dropped, entities decoded.
function Get-Text([string]$h) {
  $t = $h -replace '(?i)<br\s*/?>', ' '
  $t = $t -replace '<[^>]+>', ''
  $t = [System.Net.WebUtility]::HtmlDecode($t)
  return ($t -replace '\s+', ' ').Trim()
}
function Get-Num([string]$s) { if ($s -match '^\d+$') { return [int]$s } else { return $s } }

# Recipes on one page, as arrays:
# [item, class, level, type, yield, durability, difficulty, max quality,
#  learned-from note or null, max quality note or null, [qty, name, qty, name, ...]]
function Get-PageRecipes([string]$html) {
  $recipes = New-Object System.Collections.Generic.List[object]
  $tables = [regex]::Matches($html, '(?s)<table[^>]*class="[^"]*\bcrafting\b[^"]*"[^>]*>(.*?)</table>')
  foreach ($t in $tables) {
    foreach ($tr in [regex]::Matches($t.Groups[1].Value, '(?s)<tr[^>]*>(.*?)</tr>')) {
      $cells = @([regex]::Matches($tr.Groups[1].Value, '(?s)<td[^>]*>(.*?)</td>') | ForEach-Object { $_.Groups[1].Value })
      if ($cells.Count -eq 0) { continue }   # header row (th only)
      if ($cells.Count -lt 9) { throw "Row with $($cells.Count) cells: $(Get-Text $tr.Value)" }

      # Item name is the first link with text; anything after it is the "Learned from" note.
      $itemCell = Get-Text $cells[0]
      $name = $null
      foreach ($a in [regex]::Matches($cells[0], '(?s)<a\b[^>]*>(.*?)</a>')) {
        $at = Get-Text $a.Groups[1].Value
        if ($at) { $name = $at; break }
      }
      if (-not $name) { $name = $itemCell }
      $learned = if ($itemCell.StartsWith($name)) { $itemCell.Substring($name.Length).Trim() } else { '' }

      # "12716 (12700 required for synthesis)" -> 12716 + the note.
      $mqText = Get-Text $cells[7]
      $mqNum = $mqText; $mqNote = $null
      if ($mqText -match '^(\d+)\s*(.*)$') { $mqNum = [int]$Matches[1]; if ($Matches[2]) { $mqNote = $Matches[2] } }

      $seq = New-Object System.Collections.Generic.List[object]
      foreach ($p in [regex]::Matches($cells[8], '(?s)<dt[^>]*>(.*?)</dt>\s*<dd[^>]*>(.*?)</dd>')) {
        $seq.Add((Get-Num (Get-Text $p.Groups[1].Value)))
        $seq.Add((Get-Text $p.Groups[2].Value))
      }

      $recipes.Add(@(
        $name, (Get-Text $cells[1]), (Get-Text $cells[2]), (Get-Text $cells[3]),
        (Get-Num (Get-Text $cells[4])), (Get-Num (Get-Text $cells[5])), (Get-Num (Get-Text $cells[6])),
        $mqNum, $(if ($learned) { $learned } else { $null }), $mqNote, $seq.ToArray()
      ))
    }
  }
  return , $recipes.ToArray()
}

# Same rule as wiki-table-fingerprint.js: fields joined with U+001F, recipes with newlines.
function Get-Fingerprint($recipes) {
  $us = [string][char]0x1F
  $canon = ($recipes | ForEach-Object {
    $d = $_
    ((@($d[0..9] | ForEach-Object { if ($null -eq $_) { '' } else { [string]$_ } }) + @($d[10] | ForEach-Object { [string]$_ })) -join $us)
  }) -join "`n"
  $sha = [System.Security.Cryptography.SHA256]::Create()
  return -join ($sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($canon)) | ForEach-Object { $_.ToString('x2') })
}

$wc = New-Object System.Net.WebClient
$wc.Encoding = [System.Text.Encoding]::UTF8
$wc.Headers.Add('User-Agent', 'Mozilla/5.0 (FFXIVRadar data import)')

$all = New-Object System.Collections.Generic.List[object]
foreach ($page in $Pages) {
  $url = "https://ffxiv.consolegameswiki.com/wiki/$($Class)_Recipes/$page"
  try { $html = $wc.DownloadString($url) }
  catch { throw "Couldn't download $url : $($_.Exception.Message)" }
  $recipes = Get-PageRecipes $html
  if ($recipes.Count -eq 0) { throw "No recipe table found on $url" }

  # Round-trip through JSON first, so the fingerprint describes exactly what gets saved.
  $back = ConvertTo-Json -InputObject $recipes -Depth 5 -Compress | ConvertFrom-Json
  foreach ($r in $back) { $all.Add($r) }
  [pscustomobject]@{ Page = $page; Recipes = @($back).Count; Fingerprint = (Get-Fingerprint $back) }
}

New-Item -ItemType Directory -Force (Split-Path $OutFile -Parent) | Out-Null
[System.IO.File]::WriteAllText($OutFile, (ConvertTo-Json -InputObject $all.ToArray() -Depth 5 -Compress), (New-Object System.Text.UTF8Encoding $false))
''
"Total recipes : $($all.Count)"
"Saved to      : $OutFile"
