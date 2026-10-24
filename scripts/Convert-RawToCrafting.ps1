<#
  Converts the RAW sheet of PrepData.xlsx into one row per item on the CRAFTING sheet.

  RAW layout (an optional "Item | Class | ..." header row is skipped):
  - Item line: columns A-H filled (item, class, level, type, yield, durability,
    difficulty, max quality). Level may carry stars, e.g. "50 ★★".
  - Column I, from the item line down to the next item, holds
    quantity / material-name pairs.
  - Rows with text in column A but no class are notes for the item above,
    e.g. "(Learned from: " + "Master Carpenter I)".
  - Text under max quality (column H) below an item line is also a note,
    e.g. "(31500 required for synthesis)".

  CRAFTING output:
  - level is the number only; stars is the count of ★ (0 if none).
  - Crystals (Shard/Crystal/Cluster of the six elements) go to
    crystals_name / crystals_quantity, everything else to materials_name /
    materials_quantity, written as Postgres array literals:
    {"Maple Log","Wind Shard"} and {3,1}.
  - notes holds the "Learned from" text first (e.g. Master Carpenter I), then
    any max quality note without its brackets, joined with "; ", e.g.
    "Master Carpenter XII; 31500 required for synthesis". Blank if none.
  - id: "cr-" + first two letters of class + "-" + item name in lower case with
    only letters and digits kept (Maple Lumber, Carpenter -> cr-ca-maplelumber).
    Greek letters are spelled out and accents dropped, as in the other tables.
    Filled for every CRAFTING row whose id is blank; an existing id is never
    changed. An id that would duplicate another row is left blank and reported.
  - Columns are found by header name, so their order on CRAFTING can change.
    Columns the script doesn't know (e.g. default_order) are never touched.

  Safe to re-run:
  - RAW is only read, never changed.
  - An item already on CRAFTING (same item + class) is refreshed; new items
    are appended below. No rows are deleted.
  - A backup of the workbook is saved before every real run (see -BackupDir).

  Needs Excel installed. Close the workbook in Excel before running.

  Usage (from the repo root):
    .\scripts\Convert-RawToCrafting.ps1 -DryRun   # preview, saves nothing
    .\scripts\Convert-RawToCrafting.ps1           # write CRAFTING and save
#>
param(
  [string]$Path = (Join-Path $PSScriptRoot '..\PrepData.xlsx'),
  [string]$BackupDir = (Join-Path $env:TEMP 'FFXIVRadar-backups'),
  [switch]$DryRun
)
$ErrorActionPreference = 'Stop'

# Excel needs an absolute path.
$Path = (Resolve-Path $Path).Path

# Written as a char code so the script file can stay plain ASCII.
$star = [string][char]0x2605

$crystals = @(
  'Earth Cluster','Earth Crystal','Earth Shard',
  'Fire Cluster','Fire Crystal','Fire Shard',
  'Ice Cluster','Ice Crystal','Ice Shard',
  'Lightning Cluster','Lightning Crystal','Lightning Shard',
  'Water Cluster','Water Crystal','Water Shard',
  'Wind Cluster','Wind Crystal','Wind Shard'
)
$crystalSet = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
foreach ($c in $crystals) { [void]$crystalSet.Add($c) }

# CRAFTING columns this script fills, in the order the values are built below.
$managed = @('item','class','level','stars','type','yield','durability','difficulty','max quality',
             'crystals_name','crystals_quantity','materials_name','materials_quantity','notes')

function Test-Blank($x) { return ($null -eq $x) -or ([string]$x).Trim() -eq '' }

function ConvertTo-PgTextArray([System.Collections.Generic.List[string]]$names) {
  if ($names.Count -eq 0) { return $null }
  $quoted = foreach ($n in $names) { '"' + (($n -replace '\\', '\\') -replace '"', '\"') + '"' }
  return '{' + ($quoted -join ',') + '}'
}

function ConvertTo-PgIntArray([System.Collections.Generic.List[int]]$nums) {
  if ($nums.Count -eq 0) { return $null }
  return '{' + ($nums -join ',') + '}'
}

# "50 ★★" -> level 50, stars 2. Returns $null if the level isn't a whole number.
function ConvertFrom-Level($x) {
  $s = [string]$x
  $stars = [regex]::Matches($s, [regex]::Escape($star)).Count
  $lvl = 0
  if (-not [int]::TryParse(($s.Replace($star, '')).Trim(), [ref]$lvl)) { return $null }
  return [pscustomobject]@{ Level = $lvl; Stars = $stars }
}

# Lower-case Greek letters (U+03B1..U+03C9, final sigma included) -> names.
$greekNames = 'alpha','beta','gamma','delta','epsilon','zeta','eta','theta','iota','kappa','lambda','mu',
              'nu','xi','omicron','pi','rho','sigma','sigma','tau','upsilon','phi','chi','psi','omega'
$greek = @{}
for ($k = 0; $k -lt $greekNames.Count; $k++) { $greek[[string][char](0x03B1 + $k)] = $greekNames[$k] }

# "Amateur's Grinding Wheel" -> "amateursgrindingwheel"
function ConvertTo-Slug([string]$s) {
  $s = $s.ToLower()
  foreach ($g in $greek.Keys) { $s = $s.Replace($g, $greek[$g]) }
  $s = $s.Normalize([System.Text.NormalizationForm]::FormD)
  $s = -join ($s.ToCharArray() | Where-Object { [System.Globalization.CharUnicodeInfo]::GetUnicodeCategory($_) -ne 'NonSpacingMark' })
  return ($s -replace '[^a-z0-9]', '')
}

# (Maple Lumber, Carpenter) -> cr-ca-maplelumber. $null if class or name gives too little to work with.
function New-CraftId([string]$item, [string]$class) {
  $cls = ConvertTo-Slug $class
  $slug = ConvertTo-Slug $item
  if ($cls.Length -lt 2 -or -not $slug) { return $null }
  return "cr-$($cls.Substring(0, 2))-$slug"
}

# Reads one column of a sheet (rows $first..$last) as a 1-based array of values.
function Get-ColumnValues($ws, [int]$col, [int]$first, [int]$last) {
  $out = @($null) * ($last + 1)
  if ($last -lt $first) { return $out }
  $vals = $ws.Range($ws.Cells.Item($first, $col), $ws.Cells.Item($last, $col)).Value2
  if ($first -eq $last) { $out[$first] = $vals; return $out }
  for ($r = $first; $r -le $last; $r++) { $out[$r] = $vals[($r - $first + 1), 1] }
  return $out
}

$dir = Split-Path $Path -Parent
$leaf = Split-Path $Path -Leaf
if (Test-Path (Join-Path $dir ('~$' + $leaf))) {
  throw "$leaf looks open in Excel (lock file found). Close it and run again."
}

$warnings = New-Object System.Collections.Generic.List[string]
$xl = New-Object -ComObject Excel.Application
$xl.Visible = $false
$xl.DisplayAlerts = $false
$wb = $null
try {
  $wb = $xl.Workbooks.Open($Path, 0, [bool]$DryRun)
  $raw   = $wb.Worksheets.Item('RAW')
  $craft = $wb.Worksheets.Item('CRAFTING')

  # --- CRAFTING columns, by header name ---
  $cu = $craft.UsedRange
  $craftLastCol = $cu.Column + $cu.Columns.Count - 1
  $col = @{}
  for ($j = 1; $j -le $craftLastCol; $j++) {
    $h = ([string]$craft.Cells.Item(1, $j).Value2).Trim().ToLower()
    if ($h -and -not $col.ContainsKey($h)) { $col[$h] = $j }
  }
  foreach ($h in @('id') + $managed) {
    if (-not $col.ContainsKey($h)) { throw "CRAFTING has no '$h' column in row 1." }
  }
  $managedCols = @($managed | ForEach-Object { $col[$_] })
  $minCol = ($managedCols | Measure-Object -Minimum).Minimum
  $maxCol = ($managedCols | Measure-Object -Maximum).Maximum
  # Side by side (the usual case) -> one write per row; otherwise one write per cell.
  $contiguous = ($maxCol - $minCol + 1) -eq $managed.Count

  # --- read RAW ---
  $ur = $raw.UsedRange
  $lastRow = $ur.Row + $ur.Rows.Count - 1
  $v = $raw.Range("A1:I$lastRow").Value2
  $start = 1
  if (([string]$v[1, 1]).Trim().ToLower() -eq 'item' -and ([string]$v[1, 2]).Trim().ToLower() -eq 'class') { $start = 2 }
  if ($lastRow -lt $start) { throw 'RAW has no data rows.' }

  $items = New-Object System.Collections.Generic.List[object]
  $cur = $null
  for ($i = $start; $i -le $lastRow; $i++) {
    $a = $v[$i, 1]
    $isItemLine = -not (Test-Blank $a) -and -not (Test-Blank $v[$i, 2])
    if ($isItemLine) {
      $fields = @(); for ($j = 1; $j -le 8; $j++) { $fields += , $v[$i, $j] }
      $cur = [pscustomobject]@{
        Row    = $i
        Fields = $fields
        Notes  = (New-Object System.Collections.Generic.List[string])
        QualityNotes = (New-Object System.Collections.Generic.List[string])
        Cells  = (New-Object System.Collections.Generic.List[object])
      }
      $items.Add($cur)
    }
    else {
      for ($j = 2; $j -le 7; $j++) {
        if (-not (Test-Blank $v[$i, $j])) { $warnings.Add("RAW row ${i}: column $j has '$($v[$i, $j])' but this isn't an item line (ignored).") }
      }
      $h = $v[$i, 8]
      if (-not (Test-Blank $h)) {
        if ($null -eq $cur -or $h -is [double]) { $warnings.Add("RAW row ${i}: max quality column has '$h' but this isn't an item line (ignored).") }
        else { $cur.QualityNotes.Add(([string]$h).Trim()) }
      }
      if (-not (Test-Blank $a)) {
        if ($null -eq $cur) { $warnings.Add("RAW row ${i}: note '$a' appears before any item (ignored).") }
        else { $cur.Notes.Add(([string]$a).Trim()) }
      }
    }
    if (-not (Test-Blank $v[$i, 9])) {
      if ($null -eq $cur) { $warnings.Add("RAW row ${i}: material '$($v[$i, 9])' appears before any item (ignored)."); continue }
      $cellValue = $v[$i, 9]
      $cur.Cells.Add([pscustomobject]@{ Row = $i; Value = $cellValue })
    }
  }

  # --- build CRAFTING rows ---
  $rows = New-Object System.Collections.Generic.List[object]
  $skipped = 0
  foreach ($it in $items) {
    $name = ([string]$it.Fields[0]).Trim()
    $problem = $null
    $lvl = ConvertFrom-Level $it.Fields[2]
    if ($null -eq $lvl) { $problem = "level '$($it.Fields[2])' isn't a whole number" }
    elseif ($it.Cells.Count -eq 0) { $problem = 'no materials listed' }
    elseif ($it.Cells.Count % 2 -ne 0) { $problem = "odd number of material cells ($($it.Cells.Count)); a quantity or name is missing" }

    $cn = New-Object System.Collections.Generic.List[string]; $cq = New-Object System.Collections.Generic.List[int]
    $mn = New-Object System.Collections.Generic.List[string]; $mq = New-Object System.Collections.Generic.List[int]
    if (-not $problem) {
      for ($k = 0; $k -lt $it.Cells.Count; $k += 2) {
        $q = $it.Cells[$k]; $n = $it.Cells[$k + 1]
        $qty = 0; $num = 0.0
        # A whole number stored as a number (3) or as text ("3") both stringify to "3".
        if (-not [int]::TryParse(([string]$q.Value).Trim(), [ref]$qty) -or $qty -lt 1) {
          $problem = "RAW row $($q.Row): expected a whole-number quantity, found '$($q.Value)'"; break
        }
        if ([double]::TryParse(([string]$n.Value).Trim(), [ref]$num)) {
          $problem = "RAW row $($n.Row): expected a material name, found number '$($n.Value)'"; break
        }
        $mat = ([string]$n.Value).Trim()
        if ($crystalSet.Contains($mat)) { $cn.Add($mat); $cq.Add($qty) }
        else { $mn.Add($mat); $mq.Add($qty) }
      }
    }
    if ($problem) { $warnings.Add("SKIPPED '$name' (RAW row $($it.Row)): $problem."); $skipped++; continue }
    if ($cn.Count -eq 0) { $warnings.Add("'$name' (RAW row $($it.Row)) has no crystals.") }

    # Column A note rows joined: "(Learned from: " + "Master Carpenter I)" -> "Master Carpenter I".
    # Max quality notes lose their brackets: "(31500 required for synthesis)" -> "31500 required for synthesis".
    $noteParts = New-Object System.Collections.Generic.List[string]
    if ($it.Notes.Count) {
      $text = (($it.Notes -join ' ') -replace '\s+', ' ').Trim()
      if ($text -match '^\(?\s*Learned from:\s*(.*?)\s*\)?$') { $noteParts.Add($Matches[1]) }
      else { $noteParts.Add($text); $warnings.Add("'$name' (RAW row $($it.Row)) has a note that isn't 'Learned from'; copied as is: $text") }
    }
    foreach ($qn in $it.QualityNotes) {
      $noteParts.Add(((($qn -replace '\s+', ' ').Trim()) -replace '^\((.*)\)$', '$1').Trim())
    }
    $note = if ($noteParts.Count) { $noteParts -join '; ' } else { $null }

    $trim = { param($f) if ($f -is [string]) { $f.Trim() } else { $f } }
    $out = @(
      $name,                          # item
      (& $trim $it.Fields[1]),        # class
      $lvl.Level,                     # level
      $lvl.Stars,                     # stars
      (& $trim $it.Fields[3]),        # type
      (& $trim $it.Fields[4]),        # yield
      (& $trim $it.Fields[5]),        # durability
      (& $trim $it.Fields[6]),        # difficulty
      (& $trim $it.Fields[7]),        # max quality
      (ConvertTo-PgTextArray $cn),    # crystals_name
      (ConvertTo-PgIntArray $cq),     # crystals_quantity
      (ConvertTo-PgTextArray $mn),    # materials_name
      (ConvertTo-PgIntArray $mq),     # materials_quantity
      $note                           # notes
    )
    $rows.Add([pscustomobject]@{ Key = ($name + '|' + ([string]$it.Fields[1]).Trim()).ToLower(); Name = $name; Values = $out })
  }

  # --- match against existing CRAFTING rows ---
  $craftLast = $cu.Row + $cu.Rows.Count - 1
  $itemVals  = Get-ColumnValues $craft $col['item']  2 $craftLast
  $classVals = Get-ColumnValues $craft $col['class'] 2 $craftLast
  $existing = @{}
  for ($r = 2; $r -le $craftLast; $r++) {
    if (Test-Blank $itemVals[$r]) { continue }
    $key = (([string]$itemVals[$r]).Trim() + '|' + ([string]$classVals[$r]).Trim()).ToLower()
    if (-not $existing.ContainsKey($key)) { $existing[$key] = $r }
  }
  $nextRow = [math]::Max($craftLast + 1, 2)

  # Item and class per CRAFTING row after this run (used for ids, also in a dry run).
  $itemAt = @{}; $classAt = @{}
  for ($r = 2; $r -le $craftLast; $r++) { $itemAt[$r] = $itemVals[$r]; $classAt[$r] = $classVals[$r] }

  $seen = @{}; $updated = 0; $appended = 0
  foreach ($row in $rows) {
    if ($seen.ContainsKey($row.Key)) { $warnings.Add("'$($row.Name)' appears more than once in RAW with the same class; the later one wins.") }
    $seen[$row.Key] = $true
    if ($existing.ContainsKey($row.Key)) { $target = $existing[$row.Key]; $updated++ }
    else { $target = $nextRow; $existing[$row.Key] = $target; $nextRow++; $appended++ }
    $itemAt[$target] = $row.Values[0]; $classAt[$target] = $row.Values[1]

    if ($DryRun) {
      "row $target : " + (($row.Values | ForEach-Object { if ($null -eq $_) { '<blank>' } else { [string]$_ } }) -join ' | ')
      continue
    }
    if ($contiguous) {
      $arr = New-Object 'object[,]' 1, $managed.Count
      for ($j = 0; $j -lt $managed.Count; $j++) { $arr[0, ($managedCols[$j] - $minCol)] = $row.Values[$j] }
      $craft.Range($craft.Cells.Item($target, $minCol), $craft.Cells.Item($target, $maxCol)).Value2 = $arr
    }
    else {
      for ($j = 0; $j -lt $managed.Count; $j++) { $craft.Cells.Item($target, $managedCols[$j]).Value2 = $row.Values[$j] }
    }
  }

  # --- fill blank ids on every CRAFTING row ---
  $finalLast = [math]::Max($craftLast, $nextRow - 1)
  $idVals = Get-ColumnValues $craft $col['id'] 2 $finalLast
  $used = @{}
  for ($r = 2; $r -le $finalLast; $r++) {
    if (Test-Blank $idVals[$r]) { continue }
    $k = ([string]$idVals[$r]).Trim().ToLower()
    if ($used.ContainsKey($k)) { $warnings.Add("CRAFTING rows $($used[$k]) and $r already share the id '$k'.") }
    else { $used[$k] = $r }
  }
  $idsFilled = 0
  for ($r = 2; $r -le $finalLast; $r++) {
    if (-not (Test-Blank $idVals[$r]) -or (Test-Blank $itemAt[$r])) { continue }
    $id = New-CraftId ([string]$itemAt[$r]) ([string]$classAt[$r])
    if (-not $id) { $warnings.Add("CRAFTING row ${r}: can't build an id from item '$($itemAt[$r])' and class '$($classAt[$r])'; left blank."); continue }
    if ($used.ContainsKey($id)) { $warnings.Add("CRAFTING row ${r}: id '$id' is already used on row $($used[$id]); left blank."); continue }
    $used[$id] = $r; $idsFilled++
    if ($DryRun) { "id row $r : $id" } else { $craft.Cells.Item($r, $col['id']).Value2 = $id }
  }

  $backup = $null
  if (-not $DryRun) {
    # The file on disk is still the pre-run version here, so this is a true backup.
    New-Item -ItemType Directory -Force $BackupDir | Out-Null
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $backup = Join-Path $BackupDir ("PrepData.backup-$stamp.xlsx")
    Copy-Item $Path $backup
    $wb.Save()
  }

  ''
  "Items found in RAW : $($items.Count)"
  "Updated rows       : $updated"
  "Appended rows      : $appended"
  "Skipped items      : $skipped"
  "IDs filled         : $idsFilled"
  if ($DryRun) { '(dry run - nothing saved)' } else { "Backup saved to    : $backup" }
  if ($warnings.Count) { ''; 'Warnings:'; $warnings | ForEach-Object { "  - $_" } }
}
finally {
  if ($wb) { $wb.Close($false) }
  $xl.Quit()
  [System.Runtime.InteropServices.Marshal]::ReleaseComObject($xl) | Out-Null
}
