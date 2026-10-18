# Dragging the region used to slide it straight over the shapes drawn in it, and
# whatever fell outside stopped being part of the export -- the rectangle looked
# like it had been deleted. The request is that the frame stops at the drawings:
# push the whole region down and its top edge halts on the top of the shape, and
# the same for a single edge, in every direction.
#
# The frame is a 2px blue line on the region's own rectangle, so a scan for it
# reads the region's position directly. The shape's ink is measured alongside to
# show it is the frame that stopped and not the shape that moved.
Add-Type -AssemblyName System.Drawing, System.Windows.Forms
Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class SK {
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
function Down { [void][SK]::mouse_event($LEFTDOWN, 0, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 150 }
function Up { [void][SK]::mouse_event($LEFTUP, 0, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 350 }
# Enough steps that the last one lands a few px from wherever the drag was
# heading: the clamp stops at the last position that still fits, and a coarse
# path would stop a whole step short of it and prove less.
function Drag([int]$x1, [int]$y1, [int]$x2, [int]$y2, [int]$steps = 40) {
    MoveTo $x1 $y1; Down
    for ($i = 1; $i -le $steps; $i++) {
        MoveTo ([int]($x1 + ($x2-$x1) * $i / $steps)) ([int]($y1 + ($y2-$y1) * $i / $steps))
    }
    Up
}
function Click([int]$x, [int]$y) { MoveTo $x $y; Down; Up }
function Find-Wins([string]$title) {
    $found = New-Object System.Collections.ArrayList
    $cb = [SK+EnumProc] {
        param($h, $l)
        $t = New-Object System.Text.StringBuilder 256
        [void][SK]::GetWindowText($h, $t, 256)
        if ($t.ToString() -eq $title) { [void]$found.Add($h) }
        return $true
    }
    [void][SK]::EnumWindows($cb, [IntPtr]::Zero)
    return $found.ToArray()
}
function Find-Kids([IntPtr]$parent, [string]$title) {
    $found = New-Object System.Collections.ArrayList
    $cb = [SK+EnumProc] {
        param($h, $l)
        $t = New-Object System.Text.StringBuilder 256
        [void][SK]::GetWindowText($h, $t, 256)
        if ($t.ToString() -eq $title -and [SK]::IsWindowVisible($h)) { [void]$found.Add($h) }
        return $true
    }
    [void][SK]::EnumChildWindows($parent, $cb, [IntPtr]::Zero)
    return $found.ToArray()
}
function Rect-Of([IntPtr]$h) {
    $r = New-Object SK+RECT
    [void][SK]::GetWindowRect($h, [ref]$r)
    return $r
}
function IsRed($c) { return ($c.R -gt 190 -and $c.G -lt 120 -and $c.B -lt 130) }
# kFrame is (30,159,212).
function IsFrame($c) {
    return ([Math]::Abs($c.R - 30) -le 40 -and [Math]::Abs($c.G - 159) -le 40 -and
            [Math]::Abs($c.B - 212) -le 40)
}
function Solid($bmp, [int]$x, [int]$y) {
    foreach ($d in @(-1, 1)) {
        if (-not (IsRed ($bmp.GetPixel($x + $d, $y)))) { return $false }
        if (-not (IsRed ($bmp.GetPixel($x, $y + $d)))) { return $false }
    }
    return $true
}
function In-Bars([int]$x, [int]$y, $bars) {
    foreach ($b2 in $bars) {
        if ($x -ge $b2.left -and $x -lt $b2.right -and
            $y -ge $b2.top -and $y -lt $b2.bottom) { return $true }
    }
    return $false
}
function Ink-Box($bmp, [int]$x0, [int]$y0, [int]$x1, [int]$y1, $skip = @()) {
    $l = -1; $t = -1; $r = -1; $b = -1; $n = 0
    for ($y = $y0; $y -le $y1; $y++) {
        for ($x = $x0; $x -le $x1; $x++) {
            if (In-Bars $x $y $skip) { continue }
            if (-not (IsRed ($bmp.GetPixel($x, $y)))) { continue }
            if (-not (Solid $bmp $x $y)) { continue }
            $n++
            if ($l -lt 0 -or $x -lt $l) { $l = $x }
            if ($x -gt $r) { $r = $x }
            if ($t -lt 0) { $t = $y }
            $b = $y
        }
    }
    if ($l -lt 0) { return $null }
    return @{ l = $l; t = $t; r = $r; b = $b; n = $n }
}
# The frame line, searched only near where it is expected so nothing else blue
# can answer. The scan line is kept off the eight grips, which sit on the
# corners and the edge midpoints.
function FrameRow($bmp, [int]$x, [int]$y0, [int]$y1) {
    for ($y = $y0; $y -le $y1; $y++) { if (IsFrame ($bmp.GetPixel($x, $y))) { return $y } }
    return -1
}
function FrameCol($bmp, [int]$y, [int]$x0, [int]$x1) {
    for ($x = $x0; $x -le $x1; $x++) { if (IsFrame ($bmp.GetPixel($x, $y))) { return $x } }
    return -1
}

$sel = @(800, 600, 1600, 1100)
$shape = @(1000, 700, 1300, 900)
$fail = @()
$ov = $null

MoveTo 3000 1900
Start-Sleep -Milliseconds 400
Get-Process winshot -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 600
$proc = Start-Process -FilePath 'D:\Project\winshot\x64\Debug\winshot.exe' -PassThru
Start-Sleep -Seconds 2

$sink = @(Find-Wins 'WinShotSink')
if ($sink.Count -eq 0) { 'FAIL: no sink window'; exit 1 }
[void][SK]::PostMessage($sink[0], 0x8002, [IntPtr]::Zero, [IntPtr]::Zero)
Start-Sleep -Seconds 2
$ov = @(Find-Wins 'WinShotOverlay')
if ($ov.Count -eq 0) { 'FAIL: no overlay window'; exit 1 }

Drag $sel[0] $sel[1] $sel[2] $sel[3]
$t = @(Find-Kids $ov[0] 'WinShotToolbar')
if ($t.Count -eq 0) { 'FAIL: no toolbar'; exit 1 }
$tr = Rect-Of $t[0]
$s = ($tr.bottom - $tr.top) / 32.0
$cell = [int][Math]::Round(27 * $s); $pad = [int][Math]::Round(4 * $s)
$p = @(($tr.left + $pad + [int]($cell / 2)), [int](($tr.top + $tr.bottom) / 2))
Click $p[0] $p[1]              # the rectangle tool
Drag $shape[0] $shape[1] $shape[2] $shape[3]
Click $p[0] $p[1]              # disarm

function Bars() {
    $r = @(Rect-Of (@(Find-Kids $ov[0] 'WinShotToolbar'))[0])
    $pb = @(Find-Kids $ov[0] 'WinShotPropBar')
    if ($pb.Count) { $r += @(Rect-Of $pb[0]) }
    return $r
}
$m = Grab 'D:\Project\winshot\obj\keep_base.png'
$ink0 = Ink-Box $m 950 650 1350 950 (Bars)
$m.Dispose()
if (-not $ink0) { 'FAIL: the rectangle was never drawn'; exit 1 }
"shape at $($ink0.l),$($ink0.t) .. $($ink0.r),$($ink0.b) ($($ink0.n) px); region starts at $($sel[0]),$($sel[1])"

# Each case: move the frame, then read where its edge actually stopped and check
# the shape never budged. The scan window is only a few tens of px wide, so an
# edge that ended up anywhere else -- including where it started -- reads as no
# frame line at all rather than as a pass.
function Check([string]$tag, [string]$path, [bool]$row, [int]$scanAt, [int]$from, [int]$to,
               [int]$want, [int]$wouldBe) {
    $m = Grab $path
    $got = 0
    if ($row) { $got = FrameRow $m $scanAt $from $to } else { $got = FrameCol $m $scanAt $from $to }
    $ink = Ink-Box $m 950 650 1350 950 (Bars)
    $m.Dispose()
    "$tag`: frame edge at $got (want $want; unclamped it would be $wouldBe), shape $(if ($ink) { "$($ink.l),$($ink.t) .. $($ink.r),$($ink.b)" } else { 'GONE' })"
    if ($got -lt 0) {
        $fail += "$tag`: no frame line between $from and $to, so the edge is not at $want (unclamped it would be $wouldBe)"
        return
    }
    if ([Math]::Abs($got - $want) -gt 8) {
        $fail += "$tag`: the frame edge stopped at $got, want $want"
    }
    if (-not $ink) { $fail += "$tag`: the shape vanished"; return }
    if ($ink.l -ne $ink0.l -or $ink.t -ne $ink0.t -or $ink.r -ne $ink0.r -or $ink.b -ne $ink0.b) {
        $fail += "$tag`: the shape moved ($($ink0.l),$($ink0.t) .. $($ink0.r),$($ink0.b) -> $($ink.l),$($ink.t) .. $($ink.r),$($ink.b))"
    }
}

# --- the whole region, pushed 300px down -------------------------------------
# The pointer starts inside the region and clear of the shape, so the press moves
# the region. Its top would go to 900; the shape's top at 700 is what stops it.
Drag 1500 1050 1500 1350
Check 'region dragged down' 'D:\Project\winshot\obj\keep_down.png' $true 975 660 740 700 900

# --- the top edge alone, pulled up clear and then pushed back down -----------
# From 500 the edge has 500px of room and the shape is the only thing in the way,
# so this shows the clamp engaging rather than the edge already sitting there.
# The top-mid grip at 1200,700 sits on the shape's own stroke, but the frame's
# grips are hit-tested first, so the press resizes the region.
Drag 1200 700 1200 500
Check 'top edge pulled up' 'D:\Project\winshot\obj\keep_up.png' $true 975 460 540 500 500
Drag 1200 500 1200 1000
Check 'top edge pushed down' 'D:\Project\winshot\obj\keep_top.png' $true 975 660 740 700 1000

# --- the left edge alone, pushed right ---------------------------------------
# The region is 800,700 .. 1600,1200 by now, so its left edge midpoint is 800,950.
# Row 800 crosses that edge and is clear of the top frame line at 700.
Drag 800 950 1400 950
Check 'left edge pushed right' 'D:\Project\winshot\obj\keep_left.png' $false 800 960 1040 1000 1400

[void][System.Windows.Forms.SendKeys]::SendWait('{ESC}')
Start-Sleep -Milliseconds 400
if (-not $proc.HasExited) { $proc.Kill() }
if ($fail.Count) { "FAILURES: $($fail.Count)"; $fail | ForEach-Object { "  $_" }; exit 1 }
'PASS'
