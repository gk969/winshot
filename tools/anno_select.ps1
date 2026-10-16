# Shapes drawn earlier must stay selectable: click one and drag it.
# Each shape is drawn, then other shapes are drawn on top of it so it is no
# longer the selected one, then it is grabbed by a point on its own ink and
# dragged. The assertion is the ink bounding box moving by the drag delta —
# which only happens if the press selected that shape rather than starting a
# new one.
Add-Type -AssemblyName System.Drawing, System.Windows.Forms
Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class AS {
    public delegate bool EnumProc(IntPtr h, IntPtr l);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
    [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint msg, IntPtr w, IntPtr l);
    [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint dx, uint dy, uint d, UIntPtr e);
}
"@

$LEFTDOWN = 0x0002; $LEFTUP = 0x0004

function Grab([string]$path) {
    $b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    $bmp = New-Object System.Drawing.Bitmap $b.Width, $b.Height
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen($b.Location, [System.Drawing.Point]::Empty, $bmp.Size)
    $bmp.Save($path)
    $g.Dispose()
    return $bmp
}
function MoveTo([int]$x, [int]$y) {
    [System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point($x, $y)
    Start-Sleep -Milliseconds 90
}
function Drag([int]$x1, [int]$y1, [int]$x2, [int]$y2) {
    MoveTo $x1 $y1
    [void][AS]::mouse_event($LEFTDOWN, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 120
    for ($i = 1; $i -le 12; $i++) {
        MoveTo ([int]($x1 + ($x2-$x1) * $i / 12)) ([int]($y1 + ($y2-$y1) * $i / 12))
    }
    Start-Sleep -Milliseconds 150
    [void][AS]::mouse_event($LEFTUP, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 300
}
function Click([int]$x, [int]$y) {
    MoveTo $x $y
    [void][AS]::mouse_event($LEFTDOWN, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 120
    [void][AS]::mouse_event($LEFTUP, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 350
}
function IsBack($c) {
    return ([Math]::Abs($c.R - 235) -le 8 -and [Math]::Abs($c.G - 239) -le 8 -and
            [Math]::Abs($c.B - 243) -le 8)
}
function Band($bmp, [int]$x, [int]$y0, [int]$y1) {
    $top = -1
    for ($y = $y0; $y -le $y1; $y++) { if (IsBack ($bmp.GetPixel($x, $y))) { $top = $y; break } }
    if ($top -lt 0) { return $null }
    $bot = $top
    while ($bot + 1 -le $y1 -and (IsBack ($bmp.GetPixel($x, ($bot + 1))))) { $bot++ }
    return @($top, $bot)
}
function IsRed($c) { return ($c.R -gt 190 -and $c.G -lt 120 -and $c.B -lt 130) }
# Ink bounds inside a window, or $null when the window holds no ink at all.
function Ink-Box($bmp, [int]$x0, [int]$y0, [int]$x1, [int]$y1) {
    $l = -1; $t = -1; $r = -1; $b = -1
    for ($y = $y0; $y -le $y1; $y++) {
        for ($x = $x0; $x -le $x1; $x++) {
            if (IsRed ($bmp.GetPixel($x, $y))) {
                # Every bound is a real min/max: the topmost red row of an
                # ellipse starts near its middle, so "first x seen" is not its
                # left edge.
                if ($l -lt 0 -or $x -lt $l) { $l = $x }
                if ($x -gt $r) { $r = $x }
                if ($t -lt 0) { $t = $y }
                $b = $y
            }
        }
    }
    if ($l -lt 0) { return $null }
    return @{ l = $l; t = $t; r = $r; b = $b }
}
# A point that lies on the shape's own ink but not on one of its eight bbox
# handles: a quarter of the way across, on the first inked row of that column.
# Handles sit at the corners and the edge midpoints, so a quarter column never
# holds one.
function Ink-Point($bmp, $box) {
    $qx = [int]($box.l + ($box.r - $box.l) / 4)
    for ($y = $box.t; $y -le $box.b; $y++) {
        for ($dx = -2; $dx -le 2; $dx++) {
            if (IsRed ($bmp.GetPixel($qx + $dx, $y))) { return @(($qx + $dx), $y) }
        }
    }
    return @($qx, $box.t)
}

$sel = @(800, 600, 1500, 1050)
$fail = @()

MoveTo 3000 1900
Start-Sleep -Milliseconds 400

Get-Process winshot -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 600
$proc = Start-Process -FilePath 'D:\Project\winshot\x64\Debug\winshot.exe' -PassThru
Start-Sleep -Seconds 2

$sink = New-Object System.Collections.ArrayList
$cb = [AS+EnumProc] {
    param($h, $l)
    $t = New-Object System.Text.StringBuilder 256
    [void][AS]::GetWindowText($h, $t, 256)
    if ($t.ToString() -eq 'WinShotSink') { [void]$sink.Add($h) }
    return $true
}
[void][AS]::EnumWindows($cb, [IntPtr]::Zero)
if ($sink.Count -eq 0) { 'FAIL: no sink window'; exit 1 }
[void][AS]::PostMessage($sink[0], 0x8002, [IntPtr]::Zero, [IntPtr]::Zero)
Start-Sleep -Seconds 2

Drag $sel[0] $sel[1] $sel[2] $sel[3]
$s0 = Grab 'D:\Project\winshot\obj\as_bar.png'
$b0 = Band $s0 ($sel[0] + 6) ($sel[3] + 1) ($sel[3] + 90)
if (-not $b0) { 'FAIL: no toolbar under the selection'; exit 1 }
$midY = [int](($b0[0] + $b0[1]) / 2)
# The last light pixel on the row is not the toolbar's right edge — the dimmed
# desktop behind it can be light too. Walk right from the left edge and stop at
# the first gap wider than a separator.
function Run-Right($bmp, [int]$row, [int]$x0, [int]$x1) {
    $last = $x0; $gap = 0
    for ($x = $x0; $x -le $x1; $x++) {
        if (IsBack ($bmp.GetPixel($x, $row))) { $last = $x; $gap = 0 }
        elseif (++$gap -gt 6) { break }
    }
    return $last
}
$tbL = $sel[0] + 1
# Scan a row above the icons: across the icons the row is broken by glyph
# strokes wider than a separator, which would stop the walk early.
$tbR = Run-Right $s0 ($b0[0] + 2) $tbL ($sel[2] + 300)
# 15 slots, separators after slot 6 and slot 12, 4px padding each end.
$cell = [int](($tbR - $tbL - 8 - 2 * 14) / 15)
$slot0 = $tbL + 4 + [int]($cell / 2)
"toolbar x=$tbL..$tbR y=$($b0[0])..$($b0[1]) cell=$cell"
if ($cell -lt 20 -or $cell -gt 34) { "FAIL: implausible cell width $cell"; exit 1 }
function Slot([int]$i) {
    $sep = 0
    if ($i -gt 6) { $sep += 14 }
    if ($i -gt 12) { $sep += 14 }
    return @(($slot0 + $i * $cell + $sep), $midY)
}

# --- four shapes, each drawn after the one before -----------------------------
$tRect = Slot 0; $tEll = Slot 1; $tArr = Slot 2; $tTxt = Slot 5
Click $tRect[0] $tRect[1]; Drag 900 700 1100 800
Click $tEll[0] $tEll[1];   Drag 1220 700 1420 800
Click $tArr[0] $tArr[1];   Drag 900 880 1100 960
Click $tTxt[0] $tTxt[1];   Click 1220 880
Start-Sleep -Milliseconds 300
[void][System.Windows.Forms.SendKeys]::SendWait('AB')
Start-Sleep -Milliseconds 300
[void][System.Windows.Forms.SendKeys]::SendWait('{ENTER}')
Start-Sleep -Milliseconds 500

# Windows chosen so each shape's ink, before and after a (+60,+40) drag, stays
# clear of its neighbours.
# Is the selection still where it was? A press that finds no ink and no armed
# tool drags the selection instead of the shape, so the frame's position tells
# the two failures apart.
function Frame-X($bmp, [int]$row) {
    $xs = @()
    for ($x = $sel[0] - 40; $x -le $sel[2] + 40; $x++) {
        $c = $bmp.GetPixel($x, $row)
        if ($c.B -gt 170 -and $c.R -lt 110 -and $c.G -gt 110 -and $c.G -lt 200) { $xs += $x }
    }
    if (-not $xs.Count) { return 'none' }
    return "$($xs[0])..$($xs[-1])"
}
$cases = @(
    @{ name = 'rect';    win = @(880, 680, 1180, 860) },
    @{ name = 'ellipse'; win = @(1200, 680, 1495, 860) },
    @{ name = 'arrow';   win = @(880, 860, 1180, 1030) },
    @{ name = 'text';    win = @(1200, 860, 1495, 1030) }
)
$DX = 60; $DY = 40
foreach ($c in $cases) {
    $w = $c.win
    $s = Grab "D:\Project\winshot\obj\as_$($c.name)_probe.png"
    $probe = Ink-Box $s $w[0] $w[1] $w[2] $w[3]
    if (-not $probe) {
        $s.Dispose()
        "$($c.name): FAIL no ink before the drag"; $fail += "$($c.name) was never drawn"; continue
    }
    $p = Ink-Point $s $probe
    $s.Dispose()
    # Select it, then measure. Both snapshots then carry the same selection
    # rings, so the box delta is the shape delta; measuring an unselected
    # "before" against a selected "after" reads short on every axis, by the
    # ring radius for a rect and by the whole layout-rect padding for text.
    Click $p[0] $p[1]
    $s = Grab "D:\Project\winshot\obj\as_$($c.name)_before.png"
    $before = Ink-Box $s $w[0] $w[1] $w[2] $w[3]
    $frame0 = Frame-X $s 620
    $s.Dispose()
    "grabbing $($c.name) ink at ($($p[0]),$($p[1]))  selection frame x=$frame0"
    Drag $p[0] $p[1] ($p[0] + $DX) ($p[1] + $DY)
    $s2 = Grab "D:\Project\winshot\obj\as_$($c.name)_after.png"
    $after = Ink-Box $s2 $w[0] $w[1] $w[2] $w[3]
    "  after: selection frame x=$(Frame-X $s2 620)"
    $s2.Dispose()
    if (-not $after) { "$($c.name): FAIL no ink after the drag"; $fail += "$($c.name) vanished when dragged"; continue }
    $mx = $after.l - $before.l; $my = $after.t - $before.t
    $ok = ([Math]::Abs($mx - $DX) -le 4 -and [Math]::Abs($my - $DY) -le 4)
    "{0,-8} ink box ({1},{2})..({3},{4}) -> ({5},{6})..({7},{8})  moved ({9},{10})  {11}" -f `
        $c.name, $before.l, $before.t, $before.r, $before.b, $after.l, $after.t, $after.r, $after.b, `
        $mx, $my, $(if ($ok) { 'OK' } else { 'FAIL' })
    if (-not $ok) { $fail += "$($c.name) did not follow the drag (moved $mx,$my want $DX,$DY)" }
}

# --- and the selected rect still resizes from its corner handle ---------------
# The rect where its own drag left it, in a window clear of the ellipse
# (x >= 1280), the arrow (y >= 920) and the text.
$w = @(880, 680, 1270, 900)
$s2 = Grab 'D:\Project\winshot\obj\as_sel.png'
$box = Ink-Box $s2 $w[0] $w[1] $w[2] $w[3]
$s2.Dispose()
if ($box) {
    # Only the selected annotation has handles, and the last case left the text
    # selected, so the rect has to be clicked first.
    Click ([int]($box.l + ($box.r - $box.l) / 4)) ([int]($box.t + 4))
    $box = Ink-Box (Grab 'D:\Project\winshot\obj\as_sel.png') $w[0] $w[1] $w[2] $w[3]
    # The measured corner is the outer edge of the ring; the handle center sits
    # a few px inside it.
    $cx = [int]($box.r - 4); $cy = [int]($box.b - 4)
    Drag $cx $cy ($cx + 50) ($cy + 30)
    $box2 = Ink-Box (Grab 'D:\Project\winshot\obj\as_grown.png') $w[0] $w[1] $w[2] $w[3]
    $gw = $box2.r - $box.r; $gh = $box2.b - $box.b
    $ok = ([Math]::Abs($gw - 50) -le 4 -and [Math]::Abs($gh - 30) -le 4)
    "rect corner handle: box right/bottom ({0},{1}) -> ({2},{3})  grew ({4},{5})  {6}" -f `
        $box.r, $box.b, $box2.r, $box2.b, $gw, $gh, $(if ($ok) { 'OK' } else { 'FAIL' })
    if (-not $ok) { $fail += "corner handle grew $gw,$gh want 50,30" }
} else { $fail += 'no rect to resize' }

[void][System.Windows.Forms.SendKeys]::SendWait('{ESC}')
Start-Sleep -Milliseconds 400
[void][System.Windows.Forms.SendKeys]::SendWait('{ESC}')
Start-Sleep -Milliseconds 400
if (-not $proc.HasExited) { $proc.Kill() }

if ($fail.Count) { "FAILURES: $($fail.Count)"; $fail | ForEach-Object { "  $_" } }
else { 'PASS' }
