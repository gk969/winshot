# Measures the paint path under a scripted drag: one drag to size the selection
# and one to draw a rect, both far faster than a hand moves. The app stamps every
# paint into obj\paint.log while WINSHOT_PAINTLOG is set, which the child picks up
# from this process's environment. Run it once per configuration to compare.
param([string]$Exe = 'D:\Project\winshot\x64\Debug\winshot.exe')

Add-Type -AssemblyName System.Drawing, System.Windows.Forms
Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class WP {
    public delegate bool EnumProc(IntPtr h, IntPtr l);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
    [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr p, EnumProc cb, IntPtr l);
    [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint msg, IntPtr w, IntPtr l);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint dx, uint dy, uint d, UIntPtr e);
    [DllImport("kernel32.dll")] public static extern bool QueryPerformanceFrequency(out long f);
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int left, top, right, bottom; }
}
"@

$LEFTDOWN = 0x0002; $LEFTUP = 0x0004
$freq = [long]0
[void][WP]::QueryPerformanceFrequency([ref]$freq)

function Find-Win([string]$title) {
    $found = New-Object System.Collections.ArrayList
    $cb = [WP+EnumProc] {
        param($h, $l)
        $t = New-Object System.Text.StringBuilder 256
        [void][WP]::GetWindowText($h, $t, 256)
        if ($t.ToString() -eq $title) { [void]$found.Add($h) }
        return $true
    }
    [void][WP]::EnumWindows($cb, [IntPtr]::Zero)
    return @($found)
}
function VisibleBars($parent) {
    $list = New-Object System.Collections.ArrayList
    $cb = [WP+EnumProc] {
        param($h, $l)
        if ([WP]::IsWindowVisible($h)) {
            $r = New-Object WP+RECT
            if ([WP]::GetWindowRect($h, [ref]$r)) {
                if (($r.right - $r.left) -gt 40 -and ($r.bottom - $r.top) -gt 10) {
                    [void]$list.Add(@{ left = $r.left; top = $r.top;
                                       right = $r.right; bottom = $r.bottom })
                }
            }
        }
        return $true
    }
    [void][WP]::EnumChildWindows($parent, $cb, [IntPtr]::Zero)
    return @($list)
}
function MoveTo([int]$x, [int]$y) {
    [System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point($x, $y)
}
# Steps spaced at $gapMs, which is the whole point: a slower cadence would let the
# app finish each paint before the next move arrived and hide the cost.
function Drag([int]$x0, [int]$y0, [int]$x1, [int]$y1, [int]$steps, [int]$gapMs) {
    MoveTo $x0 $y0
    Start-Sleep -Milliseconds $gapMs
    [void][WP]::mouse_event($LEFTDOWN, 0, 0, 0, [UIntPtr]::Zero)
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    for ($i = 1; $i -le $steps; $i++) {
        MoveTo ([int]($x0 + ($x1 - $x0) * $i / $steps)) ([int]($y0 + ($y1 - $y0) * $i / $steps))
        Start-Sleep -Milliseconds $gapMs
    }
    [void][WP]::mouse_event($LEFTUP, 0, 0, 0, [UIntPtr]::Zero)
    $sw.Stop()
    return $sw.Elapsed.TotalMilliseconds
}
function Click([int]$x, [int]$y) {
    MoveTo $x $y
    [void][WP]::mouse_event($LEFTDOWN, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 120
    [void][WP]::mouse_event($LEFTUP, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 350
}
function Stats([string]$label, [double[]]$v, [double]$scale) {
    if (-not $v -or $v.Count -eq 0) { "${label}: no samples"; return }
    $s = @($v | Sort-Object)
    $mean = ($s | Measure-Object -Average).Average * $scale
    $med = $s[[int](($s.Count - 1) * 0.5)] * $scale
    $p95 = $s[[int](($s.Count - 1) * 0.95)] * $scale
    $max = $s[$s.Count - 1] * $scale
    "{0}: mean {1:N2}  median {2:N2}  p95 {3:N2}  max {4:N2} ms" -f
        $label, $mean, $med, $p95, $max
}

Get-Process winshot -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 600
Remove-Item 'D:\Project\winshot\obj\paint.log' -ErrorAction SilentlyContinue
$env:WINSHOT_PAINTLOG = '1'

$p = Start-Process -FilePath $Exe -PassThru
Start-Sleep -Seconds 2
$sink = @(Find-Win 'WinShotSink')
if ($sink.Count -eq 0) { "FAIL: no sink window"; exit 1 }
[void][WP]::PostMessage($sink[0], 0x8002, [IntPtr]::Zero, [IntPtr]::Zero)
Start-Sleep -Seconds 2
$ov = @(Find-Win 'WinShotOverlay')
if ($ov.Count -eq 0) { "FAIL: no overlay window"; exit 1 }

$t0 = [System.Diagnostics.Stopwatch]::StartNew()
$selMs = Drag 900 700 2100 1500 40 8
Start-Sleep -Milliseconds 400

$bars = @(VisibleBars $ov[0]) | Sort-Object { ($_.right - $_.left) } -Descending
if ($bars.Count -eq 0) { "FAIL: no toolbar"; exit 1 }
$bar = $bars[0]
Click ($bar.left + 4 + 13) ([int](($bar.top + $bar.bottom) / 2))
Start-Sleep -Milliseconds 300
$drawMs = Drag 1100 900 1900 1300 40 8
$t1 = $t0.Elapsed.TotalMilliseconds
Start-Sleep -Milliseconds 400

[void][System.Windows.Forms.SendKeys]::SendWait('{ESC}')
Start-Sleep -Milliseconds 400
if (-not $p.HasExited) { $p.Kill() }

"exe: $Exe"
"selection drag: 40 moves in $([Math]::Round($selMs, 0)) ms"
"rect drag:    40 moves in $([Math]::Round($drawMs, 0)) ms"
"interaction wall time: $([Math]::Round($t1, 0)) ms"

if (-not (Test-Path 'D:\Project\winshot\obj\paint.log')) { "FAIL: no paint.log"; exit 1 }
# The app logs absolute offsets from each paint's start; the phases below are the
# differences between consecutive ones.
$markNames = 'begin', 'base', 'blit', 'dim', 'annos', 'frame+labels', 'loupe',
             'blend', 'end'
$rows = @(Get-Content 'D:\Project\winshot\obj\paint.log' | ForEach-Object {
    $f = $_ -split ' '
    $o = [ordered]@{ dur = [long]$f[0]; w = [int]$f[1]; h = [int]$f[2];
                     gap = [long]$f[3]; wait = [long]$f[4]; base = [int]$f[5] }
    $prev = [long]0
    for ($i = 0; $i -lt $markNames.Count; $i++) {
        $now = [long]$f[6 + $i]
        $o['p_' + $i] = $now - $prev
        $prev = $now
    }
    [pscustomobject]$o
})
"paints: $($rows.Count)  (base redraws: $(@($rows | Where-Object { $_.base }).Count))"
$full = @($rows | Where-Object { $_.w -ge 3800 -and $_.h -ge 2100 })
"full-window updates: $($full.Count) of $($rows.Count)"
$sc = 1000.0 / $freq
'phases, mean ms per paint (all / full-window only):'
for ($i = 0; $i -lt $markNames.Count; $i++) {
    $p = 'p_' + $i
    $s = ($rows | Measure-Object -Sum -Property $p).Sum * $sc / $rows.Count
    $fs = 0.0
    if ($full.Count) { $fs = ($full | Measure-Object -Sum -Property $p).Sum * $sc / $full.Count }
    '  {0,-14} {1,7:N1} {2,9:N1}' -f $markNames[$i], $s, $fs
}
Stats 'paint duration' @($rows | ForEach-Object { [double]$_.dur }) (1000.0 / $freq)
Stats 'paint duration (full window)' @($full | ForEach-Object { [double]$_.dur }) (1000.0 / $freq)
Stats 'frame interval' @($rows | Where-Object { $_.gap -gt 0 } |
                          ForEach-Object { [double]$_.gap }) (1000.0 / $freq)
Stats 'move to paint' @($rows | Where-Object { $_.wait -gt 0 } |
                         ForEach-Object { [double]$_.wait }) (1000.0 / $freq)
$gaps = @($rows | Where-Object { $_.gap -gt 0 } | ForEach-Object { [double]$_.gap })
if ($gaps.Count) {
    $fps = ($freq / (($gaps | Measure-Object -Average).Average))
    "effective frame rate: $([Math]::Round($fps, 1)) fps"
}
