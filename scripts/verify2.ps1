param(
  [Parameter(Mandatory=$true)][string]$Image,
  [string]$Head = "",
  [string]$Tail = "",
  [ValidateSet("first","any")][string]$Mode = "first",
  [int]$ScanLines = 6,
  [double]$MinScore = 0.55,
  [int]$RetryUsed = 0,
  [int]$MaxHeight = 900,
  [string]$ForbidFile = ""
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing, System.Runtime.WindowsRuntime

$asTaskGeneric = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
    $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and
    $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' })[0]
function Await($t, $rt) {
    $as = $asTaskGeneric.MakeGenericMethod($rt); $nt = $as.Invoke($null, @($t))
    $nt.Wait(-1) | Out-Null; $nt.Result
}
[Windows.Graphics.Imaging.BitmapDecoder,Windows.Graphics,ContentType=WindowsRuntime] | Out-Null
[Windows.Media.Ocr.OcrEngine,Windows.Foundation,ContentType=WindowsRuntime] | Out-Null
$engine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromUserProfileLanguages()
$bytes = [System.IO.File]::ReadAllBytes($Image)
$ms = New-Object System.IO.MemoryStream
$ms.Write($bytes, 0, $bytes.Length); $ms.Position = 0
$ras = [System.IO.WindowsRuntimeStreamExtensions]::AsRandomAccessStream($ms)
$dec = Await ([Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($ras)) ([Windows.Graphics.Imaging.BitmapDecoder])
$sbm = Await ($dec.GetSoftwareBitmapAsync()) ([Windows.Graphics.Imaging.SoftwareBitmap])
$res = Await ($engine.RecognizeAsync($sbm)) ([Windows.Media.Ocr.OcrResult])

function Norm([string]$s) {
    if ([string]::IsNullOrEmpty($s)) { return "" }
    $b = New-Object System.Text.StringBuilder
    foreach ($ch in $s.ToCharArray()) {
        $c = [int]$ch
        if ($c -ge 0xFF01 -and $c -le 0xFF5E) { [void]$b.Append([char]($c - 0xFEE0)) }
        elseif ($c -eq 0x3000) { }
        elseif ($c -eq 0x300B -or $c -eq 0x3009 -or $c -eq 0xFF1E) { [void]$b.Append('>') }
        elseif ($c -eq 0x3014) { [void]$b.Append('(') }
        elseif ($c -eq 0x3015) { [void]$b.Append(')') }
        elseif ($c -eq 0x201C -or $c -eq 0x201D) { [void]$b.Append('"') }
        else { [void]$b.Append($ch) }
    }
    return ($b.ToString().ToLower() -replace '\s','')
}
function NormLoose([string]$s) {
    if ([string]::IsNullOrEmpty($s)) { return "" }
    $b = New-Object System.Text.StringBuilder
    foreach ($ch in $s.ToCharArray()) {
        if ([char]::IsLetterOrDigit($ch)) { [void]$b.Append([char]::ToLowerInvariant($ch)) }
    }
    return $b.ToString()
}
function Dice([string]$a, [string]$b) {
    if ($a.Length -lt 2 -or $b.Length -lt 2) { if ($a -eq $b) { return 1.0 } else { return 0.0 } }
    $ga = @{}; for ($i=0; $i -lt $a.Length-1; $i++) { $k=$a.Substring($i,2); if ($ga.ContainsKey($k)) {$ga[$k]++} else {$ga[$k]=1} }
    $gb = @{}; for ($i=0; $i -lt $b.Length-1; $i++) { $k=$b.Substring($i,2); if ($gb.ContainsKey($k)) {$gb[$k]++} else {$gb[$k]=1} }
    $inter = 0
    foreach ($k in $ga.Keys) { if ($gb.ContainsKey($k)) { $inter += [Math]::Min($ga[$k], $gb[$k]) } }
    $tot = ($a.Length-1) + ($b.Length-1)
    if ($tot -le 0) { return 0.0 }
    return (2.0 * $inter / $tot)
}

$lines = @(); foreach ($l in $res.Lines) { $lines += $l.Text }
$nLine = $lines.Count
$bmp = New-Object System.Drawing.Bitmap($Image); $w = $bmp.Width; $h = $bmp.Height; $bmp.Dispose()
$sizesOk = if ($Mode -eq "any") { ($w -ge 400 -and $h -ge 40) } else { ($w -ge 400 -and $h -ge 40 -and $h -le $MaxHeight) }
$nonEmpty = ($nLine -ge 2)

$headScore = 0.0; $headIdx = -1
if ($Head -ne "") {
    $na = Norm $Head
    $pool = if ($Mode -eq "any") { $lines } else { $lines | Select-Object -First $ScanLines }
    $i = 0
    foreach ($c0 in $pool) {
        $sc = Dice (Norm $c0) $na
        if ($sc -gt $headScore) { $headScore = $sc; $headIdx = $i }
        $i++
    }
}
$tailHit = $false
if ($Tail -ne "") {
    $nt = Norm $Tail
    foreach ($c0 in $lines) {
        $cn = Norm $c0
        if ($cn.Length -ge $nt.Length -and $cn.Contains($nt)) { $tailHit = $true; break }
        if ((Dice $cn $nt) -ge 0.62) { $tailHit = $true; break }
    }
}

# forbidden words live in a UTF-8 data file so this script stays pure ASCII
$forbid = @("Error","Traceback","cannot open","not found")
if ($ForbidFile -eq "") {
    $cand = Join-Path $PSScriptRoot 'forbid.txt'
    if (Test-Path $cand) { $ForbidFile = $cand }
}
if ($ForbidFile -ne "" -and (Test-Path $ForbidFile)) {
    $forbid = @()
    foreach ($ln in [System.IO.File]::ReadAllLines($ForbidFile, [System.Text.Encoding]::UTF8)) {
        if ($ln.Trim() -ne "") { $forbid += $ln.Trim() }
    }
}
$all = Norm ($lines -join "`n")
$hitForbid = @()
foreach ($f in $forbid) { if ($f -ne "" -and $all.Contains((Norm $f))) { $hitForbid += $f } }

$headContains = $false
if ($Head -ne "") {
    $nh = Norm $Head
    $hp = if ($Mode -eq "any") { $lines } else { $lines | Select-Object -First $ScanLines }
    foreach ($c0 in $hp) { if ((NormLoose $c0).Contains((NormLoose $Head))) { $headContains = $true; break } }
}
$headOk = ($Head -eq "" -or $headScore -ge $MinScore -or $headContains)
$act = ""; $why = ""
if (-not $sizesOk) { $act = "RETRY"; $why = "L0-SIZE" }
elseif (-not $nonEmpty) { $act = "RETRY"; $why = "L1-EMPTY" }
elseif ($hitForbid.Count -gt 0) { $act = "RETRY"; $why = "L3-FORBID" }
elseif ($headOk -and ($Tail -eq "" -or $tailHit)) {
    if ($headIdx -ge 0 -and $headIdx -gt ($ScanLines - 1) -and $Mode -ne "any") { $act = "SPLIT"; $why = "HEAD-DEEP" }
    else { $act = "OK"; $why = "" }
}
elseif ($headOk -and -not $tailHit) { $act = "RETRY"; $why = "L4-TAIL" }
elseif (-not $headOk -and $tailHit) { $act = "SPLIT"; $why = "HEAD-LOST-BUT-TAIL-PRESENT" }
else { $act = "RETRY"; $why = "L2-ANCHOR" }
if ($act -eq "RETRY" -and $RetryUsed -ge 1) { $act = "FAIL"; $why = $why + "+BUDGET" }

Write-Output ("ACT=" + $act)
if ($why -ne "") { Write-Output ("WHY=" + $why) }
Write-Output ("IMG=" + (Split-Path $Image -Leaf))
Write-Output ("SIZE={0}x{1}" -f $w, $h)
Write-Output ("LINES=" + $nLine)
Write-Output ("HEAD={0:N2}@{1}" -f $headScore, $headIdx)
Write-Output ("TAIL=" + $(if ($Tail -eq "") { "skip" } elseif ($tailHit) { "1" } else { "0" }))
Write-Output ("FORBIDN=" + @($hitForbid).Count)
if (@($hitForbid).Count -gt 0) { Write-Output ("FORBID=" + ($hitForbid -join ",")) }
