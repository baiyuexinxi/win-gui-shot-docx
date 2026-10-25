param(
  [Parameter(Mandatory=$true)][string]$CodeFile,
  [Parameter(Mandatory=$true)][string]$OutPng,
  [int]$Wait = 6,
  [int]$Attempt = 1,
  [double]$TopFrac = 0.645,
  [double]$RightFrac = 0.525,
  [int]$MaxWaitSec = 90
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public class RsHook {
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowTextW(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);
  [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr a, int x, int y, int cx, int cy, uint f);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern void SwitchToThisWindow(IntPtr h, bool fAltTab);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
  public static IntPtr Find() {
    IntPtr found = IntPtr.Zero;
    EnumWindows((h, l) => {
      var sb = new StringBuilder(512); GetWindowTextW(h, sb, sb.Capacity);
      if (sb.ToString().IndexOf("RStudio", StringComparison.OrdinalIgnoreCase) >= 0 && IsWindowVisible(h)) { found = h; return false; }
      return true;
    }, IntPtr.Zero);
    return found;
  }
  public static void Restore(IntPtr h) {
    if (IsIconic(h)) { SendMessage(h, 0x0112, (IntPtr)0xF120, IntPtr.Zero); ShowWindow(h, 9); }
    RECT r; GetWindowRect(h, out r);
    if ((r.R - r.L) < 400) { ShowWindow(h, 3); SetWindowPos(h, IntPtr.Zero, 0, 0, 1920, 1160, 0x0040); }
    SetForegroundWindow(h);
  }
}
"@
[RsHook]::SetProcessDPIAware() | Out-Null

$h = [RsHook]::Find()
if ($h -eq [IntPtr]::Zero) { Write-Output "HOOK_NO_WINDOW"; exit 2 }
[RsHook]::Restore($h)
Start-Sleep -Milliseconds 700
if ([RsHook]::GetForegroundWindow() -ne $h) {
    [System.Windows.Forms.SendKeys]::SendWait("%")   # release foreground lock
    Start-Sleep -Milliseconds 200
    [RsHook]::SetForegroundWindow($h) | Out-Null
    Start-Sleep -Milliseconds 400
}
if ([RsHook]::GetForegroundWindow() -ne $h) {
    [RsHook]::SwitchToThisWindow($h, $true)
    Start-Sleep -Milliseconds 700
}
if ([RsHook]::GetForegroundWindow() -ne $h) { Write-Output ("HOOK_NOT_FOREGROUND fg=" + [RsHook]::GetForegroundWindow() + " want=" + $h); exit 3 }

$r = New-Object RsHook+RECT
[RsHook]::GetWindowRect($h, [ref]$r) | Out-Null
$W = $r.R - $r.L; $H = $r.B - $r.T
if ($W -lt 400) { Write-Output "HOOK_BAD_RECT"; exit 4 }
$rx = $r.L; $ry = $r.T + [int]($H * $TopFrac)
$rw = [int]($W * $RightFrac); $rh = $H - [int]($H * $TopFrac)
if ($rh -lt 40) { Write-Output "HOOK_BAD_REGION"; exit 5 }

function Grab([int]$x, [int]$y, [int]$w2, [int]$h2) {
    $b = New-Object System.Drawing.Bitmap($w2, $h2)
    $g = [System.Drawing.Graphics]::FromImage($b)
    $g.CopyFromScreen($x, $y, 0, 0, $b.Size)
    $g.Dispose()
    return $b
}
function HashBmp($bmp, [string]$tmp) {
    $bmp.Save($tmp, [System.Drawing.Imaging.ImageFormat]::Png)
    return (Get-FileHash -Path $tmp -Algorithm MD5).Hash
}

# ---- 清屏 + 粘贴 ----
[System.Windows.Forms.SendKeys]::SendWait("^2")
Start-Sleep -Milliseconds 600
[System.Windows.Forms.SendKeys]::SendWait("^l")
Start-Sleep -Milliseconds 700
$code = [System.IO.File]::ReadAllText($CodeFile, [System.Text.Encoding]::UTF8)
$clipOk = $false
for ($i = 0; $i -lt 25; $i++) { try { Set-Clipboard -Value $code; $clipOk = $true; break } catch { Start-Sleep -Milliseconds 250 } }
if (-not $clipOk) { Write-Output "HOOK_CLIPBOARD_FAIL"; exit 6 }
Start-Sleep -Milliseconds 300
[System.Windows.Forms.SendKeys]::SendWait("^v")
Start-Sleep -Milliseconds 800
[System.Windows.Forms.SendKeys]::SendWait("{ENTER}")

# ---- 帧稳定检测（代替死等）----
$tmpA = Join-Path $env:TEMP ("hook_{0}.png" -f $PID)
$prev = ""; $stable = 0
$t0 = Get-Date
$bmp = $null
while ($true) {
    if ($bmp) { $bmp.Dispose() }
    $bmp = Grab $rx $ry $rw $rh
    $hsh = HashBmp $bmp $tmpA
    if ($hsh -eq $prev) { $stable++ } else { $stable = 0 }
    $prev = $hsh
    $elapsed = ((Get-Date) - $t0).TotalSeconds
    if ($stable -ge 2 -and $elapsed -ge 1.2) { break }
    if ($elapsed -ge $MaxWaitSec) { break }
    Start-Sleep -Milliseconds 400
}
$bmp.Save($OutPng, [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()
Remove-Item $tmpA -Force -ErrorAction SilentlyContinue
Write-Output ("HOOK_OK {0} {1}x{2} {3:N1}s" -f (Split-Path $OutPng -Leaf), $rw, $rh, $elapsed)
