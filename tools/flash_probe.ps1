# Catches a within-frame flash: samples one small patch of the dimmed ground as
# fast as it can while the selection is dragged. If DWM ever presents the window
# between the base blit and the dim blend, the patch reads the undimmed still for
# an instant and the max comes out well above the steady value.
param([int]$Samples = 300)
Add-Type -AssemblyName System.Drawing, System.Windows.Forms
Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class FL {
    public delegate bool EnumProc(IntPtr h, IntPtr l);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
    [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint msg, IntPtr w, IntPtr l);
    [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint dx, uint dy, uint d, UIntPtr e);
}
"@
$LEFTDOWN = 0x0002; $LEFTUP = 0x0004
function Find-Win([string]$title) {
    $found = New-Object System.Collections.ArrayList
    $cb = [FL+EnumProc] {
        param($h, $l)
        $t = New-Object System.Text.StringBuilder 256
        [void][FL]::GetWindowText($h, $t, 256)
        if ($t.ToString() -eq $title) { [void]$found.Add($h) }
        return $true
    }
    [void][FL]::EnumWindows($cb, [IntPtr]::Zero)
    return @($found)
}
Get-Process winshot -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 600
$p = Start-Process -FilePath 'D:\Project\winshot\x64\Debug\winshot.exe' -PassThru
Start-Sleep -Seconds 2
$sink = @(Find-Win 'WinShotSink')
if (-not $sink.Count) { 'FAIL: no sink'; exit 1 }
[void][FL]::PostMessage($sink[0], 0x8002, [IntPtr]::Zero, [IntPtr]::Zero)
Start-Sleep -Seconds 2
if (-not @(Find-Win 'WinShotOverlay').Count) { 'FAIL: no overlay'; exit 1 }

# Steady reading before anything moves.
$b = New-Object System.Drawing.Bitmap 32, 32
$g = [System.Drawing.Graphics]::FromImage($b)
$g.CopyFromScreen(400, 400, 0, 0, $b.Size)
$c = $b.GetPixel(16, 16)
"steady at 400,400 = $($c.R),$($c.G),$($c.B)"

# Drag slowly enough that the sampler sees many frames of the same ground.
[System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point(900, 700)
Start-Sleep -Milliseconds 200
[void][FL]::mouse_event($LEFTDOWN, 0, 0, 0, [UIntPtr]::Zero)
$minR = 999; $maxR = -1; $hist = @{}
$sw = [System.Diagnostics.Stopwatch]::StartNew()
for ($i = 0; $i -lt $Samples; $i++) {
    $x = 900 + ($i * 400 / $Samples)
    [System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point([int]$x, 700)
    $g.CopyFromScreen(400, 400, 0, 0, $b.Size)
    $c = $b.GetPixel(16, 16)
    if ($c.R -lt $minR) { $minR = $c.R }
    if ($c.R -gt $maxR) { $maxR = $c.R }
    $k = "$($c.R),$($c.G),$($c.B)"
    if ($hist.ContainsKey($k)) { $hist[$k]++ } else { $hist[$k] = 1 }
}
$sw.Stop()
[void][FL]::mouse_event($LEFTUP, 0, 0, 0, [UIntPtr]::Zero)
$g.Dispose(); $b.Dispose()
"samples: $Samples in $([Math]::Round($sw.Elapsed.TotalMilliseconds,0)) ms  (one every $([Math]::Round($sw.Elapsed.TotalMilliseconds/$Samples,2)) ms)"
"red range during drag: $minR .. $maxR"
'distinct readings (count):'
$hist.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 8 |
    ForEach-Object { "  {0,-16} {1}" -f $_.Key, $_.Value }
[void][System.Windows.Forms.SendKeys]::SendWait('{ESC}')
Start-Sleep -Milliseconds 300
if (-not $p.HasExited) { $p.Kill() }
