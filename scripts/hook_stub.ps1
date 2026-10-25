param(
  [Parameter(Mandatory=$true)][string]$CodeFile,
  [Parameter(Mandatory=$true)][string]$OutPng,
  [int]$Wait = 4,
  [int]$Attempt = 1
)
# 测试用钩子：把 fixtures 里的同名图片当作"刚截到的图"
# 若存在 <name>_bad.png 且是第 1 次尝试，就故意给一张坏图（模拟真实采集失败）
$ErrorActionPreference = 'Stop'
$dir = Join-Path $PSScriptRoot 'fixtures'
if (-not (Test-Path $dir)) { $dir = Join-Path (Split-Path $PSScriptRoot -Parent) 'fixtures' }
$bad = Join-Path $dir ("{0}_bad.png" -f $CodeFile)
$good = Join-Path $dir ("{0}.png" -f $CodeFile)
if ($Attempt -eq 1 -and (Test-Path $bad)) { Copy-Item $bad $OutPng -Force }
elseif (Test-Path $good) { Copy-Item $good $OutPng -Force }
else { throw ("no fixture for " + $CodeFile) }
Start-Sleep -Milliseconds 50
