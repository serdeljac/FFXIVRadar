<#
  Converts the RAW sheet of PrepData.xlsx into one row per item on the CRAFTING sheet.

  RAW layout: an item line (columns A-H filled), then column I below it holds
  quantity / material-name pairs. Crystals (Shard/Crystal/Cluster of the six
  elements) go to crystals_name / crystals_quantity, everything else to
  materials_name / materials_quantity, written as Postgres array literals:
  {"Maple Log","Wind Shard"} and {3,1}.

  Safe to re-run:
  - RAW is only read, never changed.
  - Column A (id) on CRAFTING is never written.
  - An item already on CRAFTING (same item + class) has columns B-M refreshed;
    new items are appended below. No rows are deleted.
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

$rawHeaders   = @('item','class','level','type','yield','durability','difficulty','max quality','materials')
$craftHeaders = @('id','item','class','level','type','yield','durability','difficulty','max quality',
                  'crystals_name','crystals_quantity','materials_name','materials_quantity')

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

  # --- header checks ---
  for ($j = 1; $j -le $rawHeaders.Count; $j++) {
    $h = ([string]$raw.Cells.Item(1, $j).Value2).Trim().ToLower()
    if ($h -ne $rawHeaders[$j - 1]) { throw "RAW column $j header is '$h', expected '$($rawHeaders[$j - 1])'." }
  }
  for ($j = 1; $j -le $craftHeaders.Count; $j++) {
    $h = ([string]$craft.Cells.Item(1, $j).Value2).Trim().ToLower()
    if ($h -ne $craftHeaders[$j - 1]) { throw "CRAFTING column $j header is '$h', expected '$($craftHeaders[$j - 1])'." }
  }

  # --- read RAW ---
  $ur = $raw.UsedRange
  $lastRow = $ur.Row + $ur.Rows.Count - 1
  if ($lastRow -lt 2) { throw 'RAW has no data rows.' }
  $v = $raw.Range("A1:I$lastRow").Value2

  $items = New-Object System.Collections.Generic.List[object]
  $cur = $null
  for ($i = 2; $i -le $lastRow; $i++) {
    if (-not (Test-Blank $v[$i, 1])) {
      $fields = @(); for ($j = 1; $j -le 8; $j++) { $fields += , $v[$i, $j] }
      $cur = [pscustomobject]@{ Row = $i; Fields = $fields; Cells = (New-Object System.Collections.Generic.List[object]) }
      $items.Add($cur)
      if (-not (Test-Blank $v[$i, 9])) { $warnings.Add("RAW row ${i}: item line also has '$($v[$i, 9])' in column I (ignored).") }
      continue
    }
    for ($j = 2; $j -le 8; $j++) {
      if (-not (Test-Blank $v[$i, $j])) { $warnings.Add("RAW row ${i}: column $j has '$($v[$i, $j])' but no item name in column A (ignored).") }
    }
    if (Test-Blank $v[$i, 9]) { continue }
    if ($null -eq $cur) { $warnings.Add("RAW row ${i}: material '$($v[$i, 9])' appears before any item (ignored)."); continue }
    $cellValue = $v[$i, 9]
    $cur.Cells.Add([pscustomobject]@{ Row = $i; Value = $cellValue })
  }

  # --- build CRAFTING rows ---
  $rows = New-Object System.Collections.Generic.List[object]
  $skipped = 0
  foreach ($it in $items) {
    $name = ([string]$it.Fields[0]).Trim()
    $problem = $null
    if ($it.Cells.Count -eq 0) { $problem = 'no materials listed' }
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

    $out = @()
    for ($j = 0; $j -lt 8; $j++) {
      $f = $it.Fields[$j]
      if ($f -is [string]) { $f = $f.Trim() }
      $out += , $f
    }
    $out += , (ConvertTo-PgTextArray $cn)
    $out += , (ConvertTo-PgIntArray $cq)
    $out += , (ConvertTo-PgTextArray $mn)
    $out += , (ConvertTo-PgIntArray $mq)
    $rows.Add([pscustomobject]@{ Key = ($name + '|' + ([string]$it.Fields[1]).Trim()).ToLower(); Name = $name; Values = $out })
  }

  # --- match against existing CRAFTING rows ---
  $cur2 = $craft.UsedRange
  $craftLast = $cur2.Row + $cur2.Rows.Count - 1
  $existing = @{}
  for ($r = 2; $r -le $craftLast; $r++) {
    $b = $craft.Cells.Item($r, 2).Value2
    if (Test-Blank $b) { continue }
    $key = (([string]$b).Trim() + '|' + ([string]$craft.Cells.Item($r, 3).Value2).Trim()).ToLower()
    if (-not $existing.ContainsKey($key)) { $existing[$key] = $r }
  }
  $nextRow = [math]::Max($craftLast + 1, 2)

  $seen = @{}; $updated = 0; $appended = 0
  foreach ($row in $rows) {
    if ($seen.ContainsKey($row.Key)) { $warnings.Add("'$($row.Name)' appears more than once in RAW with the same class; the later one wins.") }
    $seen[$row.Key] = $true
    if ($existing.ContainsKey($row.Key)) { $target = $existing[$row.Key]; $updated++ }
    else { $target = $nextRow; $existing[$row.Key] = $target; $nextRow++; $appended++ }

    if ($DryRun) {
      "row $target : " + (($row.Values | ForEach-Object { if ($null -eq $_) { '<blank>' } else { [string]$_ } }) -join ' | ')
      continue
    }
    $arr = New-Object 'object[,]' 1, 12
    for ($j = 0; $j -lt 12; $j++) { $arr[0, $j] = $row.Values[$j] }
    $craft.Range("B${target}:M${target}").Value2 = $arr
  }

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
  if ($DryRun) { '(dry run - nothing saved)' } else { "Backup saved to    : $backup" }
  if ($warnings.Count) { ''; 'Warnings:'; $warnings | ForEach-Object { "  - $_" } }
}
finally {
  if ($wb) { $wb.Close($false) }
  $xl.Quit()
  [System.Runtime.InteropServices.Marshal]::ReleaseComObject($xl) | Out-Null
}
