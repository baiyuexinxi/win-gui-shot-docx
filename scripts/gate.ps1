param(
  [Parameter(Mandatory=$true)][string]$GateFile,
  [Parameter(Mandatory=$true)][string]$AnswersFile
)
$ErrorActionPreference = 'Stop'
$gate = [System.IO.File]::ReadAllText($GateFile, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
$ans  = [System.IO.File]::ReadAllText($AnswersFile, [System.Text.Encoding]::UTF8) | ConvertFrom-Json

function Get-Field($obj, [string]$name) {
    if ($null -eq $obj) { return $null }
    $p = $obj.PSObject.Properties[$name]
    if ($null -eq $p) { return $null }
    return $p.Value
}

$deny = @(); $warn = @(); $pass = @()
foreach ($r in $gate.rules) {
    $a = Get-Field $ans $r.id
    $ok = $false
    if ($null -ne $a) {
        $v = Get-Field $a 'ok'
        if ($null -ne $v) { $ok = [bool]$v }
    }
    if ($r.enforced) {
        if ($ok) { $pass += $r.id } else { $deny += ($r.id + ":" + $r.code) }
    } else {
        if ($ok) { $pass += ($r.id + "(advisory)") } else { $warn += ($r.id + ":" + $r.code + "(advisory)") }
    }
}
if ($deny.Count -eq 0) { Write-Output "VERDICT=ALLOW" } else { Write-Output ("VERDICT=DENY " + ($deny -join ",")) }
Write-Output ("PASS=" + ($pass -join ","))
if ($warn.Count -gt 0) { Write-Output ("WARN=" + ($warn -join ",")) }
foreach ($r in $gate.rules) {
    $a = Get-Field $ans $r.id
    $n = Get-Field $a 'note'
    if ($n) { Write-Output ("NOTE " + $r.id + ": " + $n) }
}
