param(
  [Parameter(Mandatory=$true)][string]$Manifest,
  [Parameter(Mandatory=$true)][string]$OutDir,
  [Parameter(Mandatory=$true)][string]$LogPath,
  [Parameter(Mandatory=$true)][string]$Hook,
  [string]$Verifier = "",
  [int]$MaxRetry = 1
)
$ErrorActionPreference = 'Stop'
if ($Verifier -eq "") { $Verifier = Join-Path $PSScriptRoot 'verify2.ps1' }
if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Force -Path $OutDir | Out-Null }

function Invoke-Verify([string]$img, [string]$head, [string]$tail, [string]$mode, [int]$used) {
    $a = @('-NoProfile','-ExecutionPolicy','Bypass','-File',$Verifier,'-Image',$img,'-RetryUsed',"$used",'-Mode',$mode)
    if ($head -ne '') { $a += @('-Head',$head) }
    if ($tail -ne '') { $a += @('-Tail',$tail) }
    $out = & powershell.exe @a 2>&1
    $act = ($out | Where-Object { "$_" -like 'ACT=*' }) -replace '^ACT=',''
    $why = ($out | Where-Object { "$_" -like 'WHY=*' }) -replace '^WHY=',''
    $head2 = ($out | Where-Object { "$_" -like 'HEAD=*' }) -replace '^HEAD=',''
    $tail2 = ($out | Where-Object { "$_" -like 'TAIL=*' }) -replace '^TAIL=',''
    return [pscustomobject]@{ Act = "$act"; Why = "$why"; Head = "$head2"; Tail = "$tail2"; Raw = ($out -join ' ') }
}

$results = @()
foreach ($ln in [System.IO.File]::ReadAllLines($Manifest, [System.Text.Encoding]::UTF8)) {
    if ($ln.Trim() -eq "" -or $ln.StartsWith("#")) { continue }
    $p = $ln -split '\|'
    $name = $p[0].Trim(); $code = $p[1].Trim()
    $head = if ($p.Count -gt 2) { $p[2].Trim() } else { "" }
    $tail = if ($p.Count -gt 3) { $p[3].Trim() } else { "" }
    $mode = if ($p.Count -gt 4 -and $p[4].Trim() -ne "") { $p[4].Trim() } else { "first" }
    $wait = if ($p.Count -gt 5 -and $p[5].Trim() -ne "") { [int]$p[5].Trim() } else { 4 }

    $attempt = 0; $rec = $null
    while ($true) {
        $attempt++
        $png = Join-Path $OutDir ("{0}.png" -f $name)
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Hook -CodeFile $code -OutPng $png -Wait $wait -Attempt $attempt | Out-Null
        $v = Invoke-Verify $png $head $tail $mode ([Math]::Max(0, $attempt - 1))
        if ($v.Act -eq "OK") { $rec = [pscustomobject]@{ Name=$name; Act="OK"; Why=""; Attempt=$attempt; Head=$v.Head; Tail=$v.Tail }; break }
        if ($v.Act -eq "SPLIT") { $rec = [pscustomobject]@{ Name=$name; Act="NEEDS_BLOCK_SPLIT"; Why=$v.Why; Attempt=$attempt; Head=$v.Head; Tail=$v.Tail }; break }
        if ($v.Act -eq "FAIL") { $rec = [pscustomobject]@{ Name=$name; Act="FAIL"; Why=$v.Why; Attempt=$attempt; Head=$v.Head; Tail=$v.Tail }; break }
        if ($attempt -gt $MaxRetry) { $rec = [pscustomobject]@{ Name=$name; Act="FAIL"; Why=$v.Why + "+EXHAUSTED"; Attempt=$attempt; Head=$v.Head; Tail=$v.Tail }; break }
    }
    $results += $rec
    Write-Output ("{0,-8} {1,-18} try={2} head={3} tail={4} {5}" -f $rec.Name, $rec.Act, $rec.Attempt, $rec.Head, $rec.Tail, $rec.Why)
}
$results | ConvertTo-Json -Depth 4 | Set-Content -Path $LogPath -Encoding UTF8
$ok = @($results | Where-Object { $_.Act -eq 'OK' }).Count
$split = @($results | Where-Object { $_.Act -eq 'NEEDS_BLOCK_SPLIT' }).Count
$fail = @($results | Where-Object { $_.Act -eq 'FAIL' }).Count
Write-Output ("SUMMARY ok={0} split={1} fail={2} total={3}" -f $ok, $split, $fail, $results.Count)
