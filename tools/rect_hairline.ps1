# The thin 粗细 dot selects a 2px pen for every tool. The request is that a
# rectangle read that dot as 1px instead, and annot::RectPen does it at both entry
# points -- the fresh shape and one re-styled from the bar.
#
#   rect at the thin dot    one column of ink across its left edge, and that column
#                           solid rather than half-lit
#   ellipse at the same dot three columns of red, so the mapping stayed per-tool
#
# prop_dots already drags a rect at each dot and measures the left edge, but with a
# +-1 tolerance: a 2px rect at the thin dot is inside its band, so it would have
# passed unchanged either way. This is the exact assertion, and the ellipse is the
# control that says the change did not leak into the other tools.
#
# Only the rect can take a 1px pen: it is the one outline drawn without
# SetSmoothingMode, so the stroke binarises into a single crisp column, while an
# anti-aliased 1px pen feathers across two half-lit ones and reads as a grey smear.
# Measured, that difference is the whole reason the two shapes are counted two ways:
# the rect's 1px aliased stroke is 1 solid column and 1 red column, while the
# ellipse's 2px smoothed one straddles three columns at 50/100/50 and is solid on only
# the middle. Counting the ellipse on the solid predicate alone called it 1px and
# reported the change as a leak when nothing had leaked, so the control is counted on
# the red footprint and the rect on both.
Add-Type -AssemblyName System.Drawing, System.Windows.Forms
Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class RH {
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
# Absolute mouse_event rather than Cursor.Position: the latter stops moving
# without error once Windows starts flagging the script's process "(未响应)".
function MoveTo([int]$x, [int]$y) {
    [void][RH]::mouse_event(0x8001, [uint32][int][Math]::Round(65535 * $x / 3839),
                            [uint32][int][Math]::Round(65535 * $y / 2159), 0,
                            [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 90
}
function Down { [void][RH]::mouse_event($LEFTDOWN, 0, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 150 }
function Up { [void][RH]::mouse_event($LEFTUP, 0, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 350 }
function Walk([int]$x1, [int]$y1, [int]$x2, [int]$y2, [int]$steps) {
    for ($i = 1; $i -le $steps; $i++) {
        MoveTo ([int]($x1 + ($x2-$x1) * $i / $steps)) ([int]($y1 + ($y2-$y1) * $i / $steps))
    }
}
function Drag([int]$x1, [int]$y1, [int]$x2, [int]$y2) {
    MoveTo $x1 $y1; Down; Walk $x1 $y1 $x2 $y2 20; Up
}
function Click([int]$x, [int]$y) { MoveTo $x $y; Down; Up }
function Keys([string]$s) { [void][System.Windows.Forms.SendKeys]::SendWait($s) }
function Find-Wins([string]$title) {
    $found = New-Object System.Collections.ArrayList
    $cb = [RH+EnumProc] {
        param($h, $l)
        $t = New-Object System.Text.StringBuilder 256
        [void][RH]::GetWindowText($h, $t, 256)
        if ($t.ToString() -eq $title) { [void]$found.Add($h) }
        return $true
    }
    [void][RH]::EnumWindows($cb, [IntPtr]::Zero)
    return $found.ToArray()
}
function Find-Kids([IntPtr]$parent, [string]$title) {
    $found = New-Object System.Collections.ArrayList
    $cb = [RH+EnumProc] {
        param($h, $l)
        $t = New-Object System.Text.StringBuilder 256
        [void][RH]::GetWindowText($h, $t, 256)
        if ($t.ToString() -eq $title -and [RH]::IsWindowVisible($h)) { [void]$found.Add($h) }
        return $true
    }
    [void][RH]::EnumChildWindows($parent, $cb, [IntPtr]::Zero)
    return $found.ToArray()
}
function Rect-Of([IntPtr]$h) {
    $r = New-Object RH+RECT
    [void][RH]::GetWindowRect($h, [ref]$r)
    return $r
}
$ov = $null
# Toolbar slots 0..6 are plain cells before the first separator: rect, ellipse,
# arrow, pen, mosaic, text, badge.
function Slot([int]$i) {
    $t = @(Find-Kids $ov[0] 'WinShotToolbar')
    if ($t.Count -eq 0) { return $null }
    $tr = Rect-Of $t[0]
    $s = ($tr.bottom - $tr.top) / 32.0
    $cell = [int][Math]::Round(27 * $s); $pad = [int][Math]::Round(4 * $s)
    return @(($tr.left + $pad + [int]($cell / 2) + $i * $cell),
             [int](($tr.top + $tr.bottom) / 2))
}
# Dot i's centre: tb::kPropPad in from the property bar's left edge, tb::kDotPitch
# apart, at the bar's own height.
function Width-Dot([int]$i) {
    $pb = @(Find-Kids $ov[0] 'WinShotPropBar')
    if ($pb.Count -eq 0) { return $null }
    $b = Rect-Of $pb[0]
    $s = ($b.bottom - $b.top) / 37.0
    return @(($b.left + [Math]::Round(13 * $s) + $i * [Math]::Round(25 * $s)),
             [int](($b.top + $b.bottom) / 2))
}
# tb::kPalette's default is (247,56,64). Solid means solid: a pixel half covered by
# red over the light bar reads about (251,155,159), so the green bound is what
# separates the core of a stroke from its anti-aliased fringe.
function IsInk($c) { return ($c.R -gt 190 -and $c.G -lt 120 -and $c.B -lt 130) }
# Anything noticeably redder than the bar, fringe included. Red dominating green by
# this much is nothing else on screen here: the bar is light grey, the 选区's frame is
# blue, and the loupe's crosshair is cyan.
function IsRed($c) { return ($c.R -gt 150 -and ($c.R - $c.G) -gt 40) }
# The columns in x0..x1 that carry the stroke anywhere in a +-3 band at $y, counted
# either by the solid core or by the whole red footprint. Scanned across a window
# rather than at the drag's own x, because the press lands a pixel either side of the
# coordinate asked for; the count is the stroke width, the positions say where it
# actually went.
#
# Both counts matter and they are the two shapes' difference made visible. The rect
# is drawn without smoothing, so its 1px pen has no fringe: solid and red agree. The
# ellipse is smoothed, so its 2px pen straddles three columns at 50/100/50 and only
# the middle one is solid -- measuring the ellipse on the solid predicate alone would
# have called it 1px and reported the change as a leak when nothing leaked.
function Edge-Columns($bmp, [int]$x0, [int]$x1, [int]$y, [bool]$solid) {
    $cols = @()
    for ($x = $x0; $x -le $x1; $x++) {
        for ($k = -3; $k -le 3; $k++) {
            $c = $bmp.GetPixel($x, $y + $k)
            $hit = if ($solid) { IsInk $c } else { IsRed $c }
            if ($hit) { $cols += $x; break }
        }
    }
    return $cols
}
# One shape at the thin dot, measured across its left edge at the vertical middle,
# where a rect's edge is a straight run and an ellipse's tangent is vertical. Both
# corners are 200px away, and a freshly drawn shape is not selected, so there are no
# markers on the edge to count.
#
# The report travels back in the same hashtable as the count: a bare string here
# would join the function's output stream and arrive at the caller glued to the
# number.
function Measure-Edge([string]$what, [int]$slot, [int]$x1, [int]$y1, [int]$x2, [int]$y2) {
    $s = Slot $slot
    if (-not $s) {
        $script:fail += "no toolbar slot $slot for the $what"
        return @{ n = 0; msg = "${what}: no toolbar" }
    }
    Click $s[0] $s[1]
    Start-Sleep -Milliseconds 400
    $d = Width-Dot 0
    if (-not $d) {
        $script:fail += "no property bar to pick the thin dot for the $what"
        return @{ n = 0; msg = "${what}: no property bar" }
    }
    Click $d[0] $d[1]
    Start-Sleep -Milliseconds 300
    Drag $x1 $y1 $x2 $y2
    $g = Grab "D:\Project\winshot\obj\rh_$what.png"
    $mid = [int](($y1 + $y2) / 2)
    $solid = @(Edge-Columns $g ($x1 - 10) ($x1 + 20) $mid $true)
    $red = @(Edge-Columns $g ($x1 - 10) ($x1 + 20) $mid $false)
    $g.Dispose()
    $msg = "${what} at the thin dot: $($solid.Count) solid and $($red.Count) red column(s) " +
           "across its left edge, at $(if ($red.Count) { $red -join ',' } else { 'none' })"
    # Undo rather than delete: the tool stays armed, and the next shape has to be
    # drawn with the same dot still selected.
    Keys '^z'
    Start-Sleep -Milliseconds 500
    return @{ n = $red.Count; solid = $solid.Count; msg = $msg }
}

$fail = @()

MoveTo 3000 1900
Start-Sleep -Milliseconds 400
Get-Process winshot -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 600
$proc = Start-Process -FilePath 'D:\Project\winshot\x64\Debug\winshot.exe' -PassThru
Start-Sleep -Seconds 2

$sink = @(Find-Wins 'WinShotSink')
if ($sink.Count -eq 0) { 'FAIL: no sink window'; exit 1 }
[void][RH]::PostMessage($sink[0], 0x8002, [IntPtr]::Zero, [IntPtr]::Zero)
Start-Sleep -Seconds 2
$ov = @(Find-Wins 'WinShotOverlay')
if ($ov.Count -eq 0) { 'FAIL: no overlay window'; exit 1 }

# A region first: the bar and its property bar only exist once one is picked.
Drag 700 500 2200 1500

$rect = Measure-Edge 'rect' 0 900 700 1500 1100
$elli = Measure-Edge 'ellipse' 1 900 700 1500 1100
$rect.msg
$elli.msg

# The rect is the whole request: one column, not "about one".
if ($rect.n -eq 0) {
    $fail += 'the thin dot drew a rect with no ink on its left edge at all: nothing was measured'
} elseif ($rect.n -ne 1) {
    $fail += "the thin dot drew a $($rect.n) column rect stroke, want exactly 1: annot::RectPen is not mapping the 2px dot to 1px"
}
# The mechanism, not just the width: a 1px pen that were smoothed would feather into
# a second half-lit column and read as a grey smear, which is the whole reason only
# the rect -- the one outline drawn without SetSmoothingMode -- is allowed to take it.
if ($rect.n -gt 0 -and $rect.solid -ne $rect.n) {
    $fail += "the rect's stroke is solid on only $($rect.solid) of its $($rect.n) columns: the rectangle is being anti-aliased, so 1px on it is a fringe rather than a line"
}
# And the control: the same dot has to stay a 2px pen everywhere else.
if ($elli.n -eq 0) {
    $fail += 'the thin dot drew an ellipse with no ink on its left edge at all: the control measured nothing'
} elseif ($elli.n -lt 2) {
    $fail += "the thin dot drew a $($elli.n) column ellipse stroke, want at least 2: the 1px mapping leaked past the rectangle"
}

Keys '{ESC}'
Start-Sleep -Milliseconds 400
if (-not $proc.HasExited) { $proc.Kill() }
if ($fail.Count) { "FAILURES: $($fail.Count)"; $fail | ForEach-Object { "  $_" }; exit 1 }
'PASS'
