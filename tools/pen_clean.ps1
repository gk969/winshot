# Drawing or dragging a pen stroke left a band of garbled pixels above and to the
# left of the stroke's box -- 出错截图/画笔工具拖动绘制时周围出现杂色残缺的线条.png
# marks both bands in green. The chrome buffer was cleared on one rectangle and
# blended on another, so the pixels between them kept whatever the last frame had
# left there.
#
# The stray pixels are not red, so counting red proves nothing. The frozen still
# behind them never changes, so the honest witness is a difference: grab the same
# bands before and during the gesture and count pixels that moved at all. The
# bands sit outside the stroke's own ink box, and for the drag they are cut short
# before the eight selection rings, which are legitimate chrome.
Add-Type -AssemblyName System.Drawing, System.Windows.Forms
Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class PC {
    public delegate bool EnumProc(IntPtr h, IntPtr l);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
    [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr p, EnumProc cb, IntPtr l);
    [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint msg, IntPtr w, IntPtr l);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint dx, uint dy, uint d, UIntPtr e);
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int left, top, right, bottom; }
}
"@

$LEFTDOWN = 0x0002; $LEFTUP = 0x0004

function Grab([string]$path) {
    $b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    $bmp = New-Object System.Drawing.Bitmap $b.Width, $b.Height
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen($b.Location, [System.Drawing.Point]::Empty, $bmp.Size)
    if ($path) { $bmp.Save($path) }
    $g.Dispose()
    return $bmp
}
function MoveTo([int]$x, [int]$y) {
    [System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point($x, $y)
    Start-Sleep -Milliseconds 90
}
function Down { [void][PC]::mouse_event($LEFTDOWN, 0, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 150 }
function Up { [void][PC]::mouse_event($LEFTUP, 0, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 350 }
function Walk([int]$x1, [int]$y1, [int]$x2, [int]$y2, [int]$steps) {
    for ($i = 1; $i -le $steps; $i++) {
        MoveTo ([int]($x1 + ($x2-$x1) * $i / $steps)) ([int]($y1 + ($y2-$y1) * $i / $steps))
    }
}
function Drag([int]$x1, [int]$y1, [int]$x2, [int]$y2) {
    MoveTo $x1 $y1; Down; Walk $x1 $y1 $x2 $y2 24; Up
}
function Click([int]$x, [int]$y) { MoveTo $x $y; Down; Up }
function Find-Wins([string]$title) {
    $found = New-Object System.Collections.ArrayList
    $cb = [PC+EnumProc] {
        param($h, $l)
        $t = New-Object System.Text.StringBuilder 256
        [void][PC]::GetWindowText($h, $t, 256)
        if ($t.ToString() -eq $title) { [void]$found.Add($h) }
        return $true
    }
    [void][PC]::EnumWindows($cb, [IntPtr]::Zero)
    return $found.ToArray()
}
function Find-Kids([IntPtr]$parent, [string]$title) {
    $found = New-Object System.Collections.ArrayList
    $cb = [PC+EnumProc] {
        param($h, $l)
        $t = New-Object System.Text.StringBuilder 256
        [void][PC]::GetWindowText($h, $t, 256)
        if ($t.ToString() -eq $title -and [PC]::IsWindowVisible($h)) { [void]$found.Add($h) }
        return $true
    }
    [void][PC]::EnumChildWindows($parent, $cb, [IntPtr]::Zero)
    return $found.ToArray()
}
function Rect-Of([IntPtr]$h) {
    $r = New-Object PC+RECT
    [void][PC]::GetWindowRect($h, [ref]$r)
    return $r
}
# Pixels that changed between two grabs of the same rectangle. The still behind
# the overlay is frozen, so anything that moved here moved because of the gesture.
function DiffCount($a, $b, [int]$x0, [int]$y0, [int]$x1, [int]$y1) {
    $n = 0
    for ($y = $y0; $y -le $y1; $y++) {
        for ($x = $x0; $x -le $x1; $x++) {
            $p = $a.GetPixel($x, $y); $q = $b.GetPixel($x, $y)
            if ([Math]::Abs($p.R - $q.R) -gt 12 -or [Math]::Abs($p.G - $q.G) -gt 12 -or
                [Math]::Abs($p.B - $q.B) -gt 12) { $n++ }
        }
    }
    return $n
}
$ov = $null
function Slot([int]$i) {
    $t = @(Find-Kids $ov[0] 'WinShotToolbar')
    if ($t.Count -eq 0) { return $null }
    $tr = Rect-Of $t[0]
    $s = ($tr.bottom - $tr.top) / 32.0
    $cell = [int][Math]::Round(27 * $s); $pad = [int][Math]::Round(4 * $s)
    return @(($tr.left + $pad + [int]($cell / 2) + $i * $cell),
             [int](($tr.top + $tr.bottom) / 2))
}

$sel = @(800, 600, 1600, 1400)
$fail = @()

MoveTo 3000 1900
Start-Sleep -Milliseconds 400
Get-Process winshot -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 600
$proc = Start-Process -FilePath 'D:\Project\winshot\x64\Debug\winshot.exe' -PassThru
Start-Sleep -Seconds 2

$sink = @(Find-Wins 'WinShotSink')
if ($sink.Count -eq 0) { 'FAIL: no sink window'; exit 1 }
[void][PC]::PostMessage($sink[0], 0x8002, [IntPtr]::Zero, [IntPtr]::Zero)
Start-Sleep -Seconds 2
$ov = @(Find-Wins 'WinShotOverlay')
if ($ov.Count -eq 0) { 'FAIL: no overlay window'; exit 1 }

Drag $sel[0] $sel[1] $sel[2] $sel[3]

# --- drawing a stroke --------------------------------------------------------
# Halfway along a stroke from 1000,700 to 1200,850. ShapeStroke::BBox pads the
# points by pen/2 + 0.5 and InkBBox by 1.5 more, so the cleared box is
# 996,696 .. 1204,854; the two bands are the 14px outside its top and left.
$pre = Grab 'D:\Project\winshot\obj\pen_pre.png'
$p = Slot 3
if (-not $p) { 'FAIL: no toolbar'; exit 1 }
Click $p[0] $p[1]              # the pen tool
MoveTo 1000 700; Down
Walk 1000 700 1200 850 12
$mid = Grab 'D:\Project\winshot\obj\pen_mid_draw.png'
$above = DiffCount $pre $mid 996 682 1204 695
$left = DiffCount $pre $mid 982 696 995 854
# The same difference inside the stroke's own box has to be large, or the two
# zeros above only say the grabs or the geometry are wrong.
$inked = DiffCount $pre $mid 1000 700 1200 850
$mid.Dispose()
Walk 1200 850 1400 1000 12
Up
Click $p[0] $p[1]              # disarm
"mid-draw bands: above $above changed px, left $left changed px (want 0); ink box $inked (want > 500)"
if ($above -gt 0) { $fail += "drawing left $above changed px in the band above the stroke's box" }
if ($left -gt 0) { $fail += "drawing left $left changed px in the band left of the stroke's box" }
if ($inked -lt 500) { $fail += "the stroke itself is missing from the mid-draw grab ($inked changed px), so the two bands prove nothing" }
$pre.Dispose()

# --- dragging that stroke ----------------------------------------------------
# The stroke now runs 1000,700 .. 1400,1000, so its ink box is 996,696 ..
# 1404,1004 and its guide box 997,697 .. 1402,1002. Halfway along a drag of
# -240,-120 the ink box is at 876,636 .. 1284,944 and the guide box at
# 877,637 .. 1282,942, both clear of where the committed stroke still sits in the
# before-image (x 998..1402, y 698..1002). The windows then stop short of the
# eight selection rings, which reach 5px past the guide box: the top-edge rings
# sit at x 877, 1080 and 1282, the left-edge ones at y 637, 790 and 942.
$pre2 = Grab 'D:\Project\winshot\obj\pen_pre_drag.png'
MoveTo 1100 775; Down          # on the stroke's ink, away from its ends
Walk 1100 775 980 715 12
$mid2 = Grab 'D:\Project\winshot\obj\pen_mid_drag.png'
$above2 = DiffCount $pre2 $mid2 895 622 1062 635
$left2 = DiffCount $pre2 $mid2 862 654 875 772
# Where the stroke has been dragged to: it was not there in the before-image, so
# this difference is large and the two band zeros mean something.
$inked2 = DiffCount $pre2 $mid2 900 645 1020 740
$mid2.Dispose()
Walk 980 715 860 655 12
Up
$pre2.Dispose()
"mid-drag bands: above $above2 changed px, left $left2 changed px (want 0); moved ink $inked2 (want > 300)"
if ($above2 -gt 0) { $fail += "dragging left $above2 changed px in the band above the stroke's box" }
if ($left2 -gt 0) { $fail += "dragging left $left2 changed px in the band left of the stroke's box" }
if ($inked2 -lt 300) { $fail += "the dragged stroke is missing from the mid-drag grab ($inked2 changed px), so the two bands prove nothing" }

[void][System.Windows.Forms.SendKeys]::SendWait('{ESC}')
Start-Sleep -Milliseconds 400
if (-not $proc.HasExited) { $proc.Kill() }
if ($fail.Count) { "FAILURES: $($fail.Count)"; $fail | ForEach-Object { "  $_" }; exit 1 }
'PASS'
