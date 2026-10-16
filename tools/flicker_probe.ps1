# Is the flicker a brightness oscillation or just lag? Drags the selection in
# small steps and samples fixed screen points at every step: one in the dimmed
# ground outside the selection, one inside the hole, one on the frame's left
# edge. A dim ground that should be a constant colour but reads 40,41,40,41 is
# flickering; one that reads 40,40,40 while the frame lags behind the cursor is
# not.
param([int]$Steps = 24)
Add-Type -AssemblyName System.Drawing, System.Windows.Forms
Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class FP {
    public delegate bool EnumProc(IntPtr h, IntPtr l);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
    [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint msg, IntPtr w, IntPtr l);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint dx, uint dy, uint d, UIntPtr e);
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int left, top, right, bottom; }
}
"@
$LEFTDOWN = 0x0002; $LEFTUP = 0x0004
function Find-Win([string]$title) {
    $found = New-Object System.Collections.ArrayList
    $cb = [FP+EnumProc] {
        param($h, $l)
        $t = New-Object System.Text.StringBuilder 256
        [void][FP]::GetWindowText($h, $t, 256)
        if ($t.ToString() -eq $title) { [void]$found.Add($h) }
        return $true
    }
    [void][FP]::EnumWindows($cb, [IntPtr]::Zero)
    return @($found)
}
function Grab([int]$x, [int]$y, [int]$n) {
    $b = New-Object System.Drawing.Bitmap $n, 1
    $g = [System.Drawing.Graphics]::FromImage($b)
    $g.CopyFromScreen($x, $y, 0, 0, $b.Size)
    $o = @()
    for ($i = 0; $i -lt $n; $i++) { $c = $b.GetPixel($i, 0); $o += , @($c.R, $c.G, $c.B) }
    $g.Dispose(); $b.Dispose()
    return , $o
}
Get-Process winshot -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 600
$p = Start-Process -FilePath 'D:\Project\winshot\x64\Debug\winshot.exe' -PassThru
Start-Sleep -Seconds 2
$sink = @(Find-Win 'WinShotSink')
if (-not $sink.Count) { 'FAIL: no sink'; exit 1 }
[void][FP]::PostMessage($sink[0], 0x8002, [IntPtr]::Zero, [IntPtr]::Zero)
Start-Sleep -Seconds 2
if (-not @(Find-Win 'WinShotOverlay').Count) { 'FAIL: no overlay'; exit 1 }

# The drag runs from 900,700 rightward/downward; the samples sit where the hole
# edge sweeps past them, so each one crosses from dimmed to undimmed once.
[System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point(900, 700)
Start-Sleep -Milliseconds 200
[void][FP]::mouse_event($LEFTDOWN, 0, 0, 0, [UIntPtr]::Zero)
$lines = @()
for ($i = 1; $i -le $Steps; $i++) {
    $x = 900 + $i * 30; $y = 700 + $i * 20
    [System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point($x, $y)
    Start-Sleep -Milliseconds 40
    # A fixed point well outside the selection: the dim over the still, which
    # must not change colour as the selection moves.
    $dim = Grab 400 400 1
    # A fixed point just inside the top-left of the frame's left edge.
    $fr = Grab ($x - 2) ([int](($y + 700) / 2)) 5
    $d = $dim[0]; $f = $fr[2]
    $lines += ("step {0,2} cursor {1},{2}  dim@400,400 = {3},{4},{5}  frame@{6} = {7},{8},{9}" -f
               $i, $x, $y, $d[0], $d[1], $d[2], ($x - 2), $f[0], $f[1], $f[2])
}
[void][FP]::mouse_event($LEFTUP, 0, 0, 0, [UIntPtr]::Zero)
$lines
[void][System.Windows.Forms.SendKeys]::SendWait('{ESC}')
Start-Sleep -Milliseconds 300
if (-not $p.HasExited) { $p.Kill() }
