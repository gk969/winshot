# Screenshots the overlay mid-interaction so the composite can be judged by eye:
# the chrome now reaches the window through an alpha blend, and a wrong
# premultiplication would show up as cards that are too bright or a black box.
param([switch]$DrawRect)
Add-Type -AssemblyName System.Drawing, System.Windows.Forms
Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class SM {
    public delegate bool EnumProc(IntPtr h, IntPtr l);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
    [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint msg, IntPtr w, IntPtr l);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr p, EnumProc cb, IntPtr l);
    [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint dx, uint dy, uint d, UIntPtr e);
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int left, top, right, bottom; }
}
"@
$LEFTDOWN = 0x0002; $LEFTUP = 0x0004
function Find-Win([string]$title) {
    $found = New-Object System.Collections.ArrayList
    $cb = [SM+EnumProc] {
        param($h, $l)
        $t = New-Object System.Text.StringBuilder 256
        [void][SM]::GetWindowText($h, $t, 256)
        if ($t.ToString() -eq $title) { [void]$found.Add($h) }
        return $true
    }
    [void][SM]::EnumWindows($cb, [IntPtr]::Zero)
    return @($found)
}
function Click([int]$x, [int]$y) {
    [System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point($x, $y)
    Start-Sleep -Milliseconds 150
    [void][SM]::mouse_event($LEFTDOWN, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 120
    [void][SM]::mouse_event($LEFTUP, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 350
}
Get-Process winshot -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 600
$p = Start-Process -FilePath 'D:\Project\winshot\x64\Debug\winshot.exe' -PassThru
Start-Sleep -Seconds 2
$sink = @(Find-Win 'WinShotSink')
[void][SM]::PostMessage($sink[0], 0x8002, [IntPtr]::Zero, [IntPtr]::Zero)
Start-Sleep -Seconds 2
$ov = @(Find-Win 'WinShotOverlay')
function Grab([string]$path) {
    $b = New-Object System.Drawing.Bitmap 1920, 1080
    $g = [System.Drawing.Graphics]::FromImage($b)
    $g.CopyFromScreen(0, 0, 0, 0, $b.Size)
    $g.DrawImage($b, 0, 0, 1920, 1080)
    $b2 = New-Object System.Drawing.Bitmap $b, 1920, 1080
    $b2.Save($path)
    $g.Dispose(); $b.Dispose(); $b2.Dispose()
    "saved $path"
}
Grab 'D:\Project\winshot\obj\mid_summon.png'
# A selection, held mid-drag so the size card and the frame are on screen.
[System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point(500, 400)
Start-Sleep -Milliseconds 200
[void][SM]::mouse_event($LEFTDOWN, 0, 0, 0, [UIntPtr]::Zero)
[System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point(1300, 950)
Start-Sleep -Milliseconds 300
Grab 'D:\Project\winshot\obj\mid_select.png'
[void][SM]::mouse_event($LEFTUP, 0, 0, 0, [UIntPtr]::Zero)
Start-Sleep -Milliseconds 400
if ($DrawRect) {
    $bars = New-Object System.Collections.ArrayList
    $cb = [SM+EnumProc] {
        param($h, $l)
        if ([SM]::IsWindowVisible($h)) {
            $r = New-Object SM+RECT
            if ([SM]::GetWindowRect($h, [ref]$r)) {
                if (($r.right - $r.left) -gt 40 -and ($r.bottom - $r.top) -gt 10) {
                    [void]$bars.Add(@{ l = $r.left; t = $r.top; r = $r.right; b = $r.bottom })
                }
            }
        }
        return $true
    }
    [void][SM]::EnumChildWindows($ov[0], $cb, [IntPtr]::Zero)
    $bar = @($bars | Sort-Object { ($_.r - $_.l) } -Descending)[0]
    Click ($bar.l + 4 + 13) ([int](($bar.t + $bar.b) / 2))   # 矩形
    [System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point(700, 550)
    Start-Sleep -Milliseconds 200
    [void][SM]::mouse_event($LEFTDOWN, 0, 0, 0, [UIntPtr]::Zero)
    [System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point(1200, 800)
    Start-Sleep -Milliseconds 300
    Grab 'D:\Project\winshot\obj\mid_rect.png'
    [void][SM]::mouse_event($LEFTUP, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 400
    Grab 'D:\Project\winshot\obj\mid_rect_done.png'
}
[void][System.Windows.Forms.SendKeys]::SendWait('{ESC}')
Start-Sleep -Milliseconds 300
if (-not $p.HasExited) { $p.Kill() }
