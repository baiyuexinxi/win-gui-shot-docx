param(
  [Parameter(Mandatory=$true)][string]$Manifest,
  [Parameter(Mandatory=$true)][string]$Out,
  [string]$Title = "",
  [string]$Pandoc = "",
  [double]$WidthIn = 5.8,
  [switch]$NoCaption
)
$ErrorActionPreference = 'Stop'

# ---------- 找 pandoc ----------
function Find-Pandoc {
    if ($Pandoc -ne "") {
        if (Test-Path $Pandoc) { return $Pandoc }
        throw ("pandoc not found at " + $Pandoc)
    }
    $cmd = Get-Command pandoc -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    foreach ($p in @(
        "$env:ProgramFiles\RStudio\resources\app\bin\quarto\bin\tools\pandoc.exe",
        "$env:ProgramFiles\Pandoc\pandoc.exe",
        "$env:LOCALAPPDATA\Pandoc\pandoc.exe")) {
        if (Test-Path $p) { return $p }
    }
    throw "pandoc not found; pass -Pandoc <path> (RStudio bundles one under resources\app\bin\quarto\bin\tools)"
}
$exe = Find-Pandoc

# ---------- 生成 markdown ----------
$md = New-Object System.Collections.Generic.List[string]
if ($Title -ne "") { $md.Add("# " + $Title); $md.Add("") }
$imgs = 0
foreach ($ln in [System.IO.File]::ReadAllLines($Manifest, [System.Text.Encoding]::UTF8)) {
    if ($ln.Trim() -eq "") { continue }
    if ($ln.TrimStart().StartsWith("#")) { $md.Add($ln.Trim()); $md.Add(""); continue }
    $p = $ln -split "`t"
    $img = $p[0].Trim()
    $cap = if ($p.Count -gt 1) { $p[1].Trim() } else { "" }
    if (-not (Test-Path $img)) { throw ("image not found: " + $img) }
    $full = (Resolve-Path $img).Path -replace '\\','/'
    if ($NoCaption -or $cap -eq "") { $md.Add(('![]({0}){{width={1}in}}' -f $full, $WidthIn)) }
    else { $md.Add(('![{0}]({1}){{width={2}in}}' -f $cap, $full, $WidthIn)) }
    $md.Add("")
    $imgs++
}
if ($imgs -eq 0) { throw "manifest has no images" }

$tmp = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), ("shot_" + [Guid]::NewGuid().ToString('N') + ".md"))
[System.IO.File]::WriteAllLines($tmp, $md, (New-Object System.Text.UTF8Encoding($false)))

# ---------- 转 docx ----------
& $exe $tmp -o $Out --resource-path=.
if ($LASTEXITCODE -ne 0) { throw ("pandoc failed with exit " + $LASTEXITCODE) }
Remove-Item $tmp -Force -ErrorAction SilentlyContinue
if (-not (Test-Path $Out)) { throw "docx not produced" }

# ---------- 中文字体补丁（宋体正文 / 黑体标题） ----------
try {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $song = [string][char]0x5B8B + [char]0x4F53
    $hei  = [string][char]0x9ED1 + [char]0x4F53
    $dengL = [string][char]0x7B49 + [char]0x7EBF + " Light"
    $deng  = [string][char]0x7B49 + [char]0x7EBF
    $zip = [System.IO.Compression.ZipFile]::Open($Out, 'Update')
    $e = $zip.GetEntry('word/theme/theme1.xml')
    if ($e) {
        $sr = New-Object System.IO.StreamReader($e.Open()); $xml = $sr.ReadToEnd(); $sr.Close()
        $i1 = $xml.IndexOf('<a:ea typeface=""/>')
        if ($i1 -ge 0) { $xml = $xml.Remove($i1,20).Insert($i1, ('<a:ea typeface="{0}"/>' -f $hei)) }
        $i2 = $xml.IndexOf('<a:ea typeface=""/>')
        if ($i2 -ge 0) { $xml = $xml.Remove($i2,20).Insert($i2, ('<a:ea typeface="{0}"/>' -f $song)) }
        $xml = $xml.Replace(('<a:font script="Hans" typeface="{0}"/>' -f $dengL), ('<a:font script="Hans" typeface="{0}"/>' -f $hei))
        $xml = $xml.Replace(('<a:font script="Hans" typeface="{0}"/>' -f $deng),  ('<a:font script="Hans" typeface="{0}"/>' -f $song))
        $e.Delete()
        $ne = $zip.CreateEntry('word/theme/theme1.xml')
        $sw = New-Object System.IO.StreamWriter($ne.Open(), (New-Object System.Text.UTF8Encoding($false)))
        $sw.Write($xml); $sw.Close()
    }
    $zip.Dispose()
    Write-Output "FONT_PATCH=ok"
} catch {
    Write-Output ("FONT_PATCH=skip (" + $_.Exception.Message + ")")
}

$kb = [Math]::Round((Get-Item $Out).Length / 1KB)
Write-Output ("DOCX_OK {0} images={1} size={2}KB" -f (Split-Path $Out -Leaf), $imgs, $kb)
