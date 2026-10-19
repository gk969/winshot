# The three stroke-width dots were drawn at the pen width they stand for, which in
# a 37px bar made the 2px one a speck. The request is to draw them half again as
# large without changing what they select, so this measures both halves of that:
#
#   the dots   a vertical scan down each dot's own centre column, counting the
#              accent-blue pixels. tb::kDotDraw is 3/6/12.
#   the pens   a horizontal scan across the left edge of a rect drawn at each
#              width, counting the solidly inked pixels. tb::kDotSizes is 2/4/8,
#              and those are what every stroke, the mosaic band and the handle
#              sizes resolve from - if the dots had simply been made into the new
#              pen widths, these numbers would have grown by half too.
#
# The selected dot sits in a 24px frame filled with an 8% black wash, which is grey
# rather than blue, so the accent test does not see it; the frame's edge is 12px
# out from the centre, well clear of the largest dot's 6px radius.
Add-Type -AssemblyName System.Drawing, System.Windows.Forms
Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class PDX {
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
    [void][PDX]::mouse_event(0x8001, [uint32][int][Math]::Floor(65535 * $x / 3840),
                             [uint32][int][Math]::Floor(65535 * $y / 2160), 0,
                             [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 90
}
function Down { [void][PDX]::mouse_event($LEFTDOWN, 0, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 150 }
function Up { [void][PDX]::mouse_event($LEFTUP, 0, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 350 }
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
    $cb = [PDX+EnumProc] {
        param($h, $l)
        $t = New-Object System.Text.StringBuilder 256
        [void][PDX]::GetWindowText($h, $t, 256)
        if ($t.ToString() -eq $title) { [void]$found.Add($h) }
        return $true
    }
    [void][PDX]::EnumWindows($cb, [IntPtr]::Zero)
    return $found.ToArray()
}
function Find-Kids([IntPtr]$parent, [string]$title) {
    $found = New-Object System.Collections.ArrayList
    $cb = [PDX+EnumProc] {
        param($h, $l)
        $t = New-Object System.Text.StringBuilder 256
        [void][PDX]::GetWindowText($h, $t, 256)
        if ($t.ToString() -eq $title -and [PDX]::IsWindowVisible($h)) { [void]$found.Add($h) }
        return $true
    }
    [void][PDX]::EnumChildWindows($parent, $cb, [IntPtr]::Zero)
    return $found.ToArray()
}
function Rect-Of([IntPtr]$h) {
    $r = New-Object PDX+RECT
    [void][PDX]::GetWindowRect($h, [ref]$r)
    return $r
}
# tb::kAccent is (46,146,225). Blue dominating red by this much is nothing else on
# the bar: the bar is light grey, the frame around the selected dot is an 8% black
# wash, and the ink is red.
function IsAccent($c) { return ($c.B -gt 150 -and ($c.B - $c.R) -gt 80) }
# tb::kPalette's default is (247,56,64).
function IsInk($c) { return ($c.R -gt 190 -and $c.G -lt 120 -and $c.B -lt 130) }
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
# Dot i's centre: tb::kPropPad in from the bar's left edge, tb::kDotPitch apart,
# the bar's own height.
function Width-Dot([int]$i) {
    $pb = @(Find-Kids $ov[0] 'WinShotPropBar')
    if ($pb.Count -eq 0) { return $null }
    $b = Rect-Of $pb[0]
    $s = ($b.bottom - $b.top) / 37.0
    return @(($b.left + [Math]::Round(13 * $s) + $i * [Math]::Round(25 * $s)),
             [int](($b.top + $b.bottom) / 2))
}
# The longest run of accent pixels straight down a column: the dot's diameter.
function Accent-Run($bmp, [int]$x, [int]$y, [int]$half) {
    $best = 0; $run = 0
    for ($k = -$half; $k -le $half; $k++) {
        if (IsAccent ($bmp.GetPixel($x, $y + $k))) { $run++; if ($run -gt $best) { $best = $run } }
        else { $run = 0 }
    }
    return $best
}
# The longest run of ink pixels across a stroke: its width.
function Ink-Run($bmp, [int]$x, [int]$y, [int]$half) {
    $best = 0; $run = 0
    for ($k = -$half; $k -le $half; $k++) {
        if (IsInk ($bmp.GetPixel($x + $k, $y))) { $run++; if ($run -gt $best) { $best = $run } }
        else { $run = 0 }
    }
    return $best
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
[void][PDX]::PostMessage($sink[0], 0x8002, [IntPtr]::Zero, [IntPtr]::Zero)
Start-Sleep -Seconds 2
$ov = @(Find-Wins 'WinShotOverlay')
if ($ov.Count -eq 0) { 'FAIL: no overlay window'; exit 1 }

Drag 700 500 2200 1500
$p = Slot 0
if (-not $p) { 'FAIL: no toolbar'; exit 1 }
Click $p[0] $p[1]              # the rect tool arms the width dots
Start-Sleep -Milliseconds 500

# --- the dots themselves -------------------------------------------------------
$dots = @(0, 0, 0)
$g = Grab 'D:\Project\winshot\obj\pdx_bar.png'
for ($i = 0; $i -le 2; $i++) {
    $d = Width-Dot $i
    if (-not $d) { 'FAIL: no property bar'; exit 1 }
    $dots[$i] = Accent-Run $g $d[0] $d[1] 14
    "dot $i at $($d[0]),$($d[1]): $($dots[$i]) px of accent down its centre column"
}
$g.Dispose()
"dot diameters: $($dots[0]) -> $($dots[1]) -> $($dots[2]) (tb::kDotDraw is 3/6/12)"
for ($i = 0; $i -le 2; $i++) {
    $want = @(3, 6, 12)[$i]
    if ([Math]::Abs($dots[$i] - $want) -gt 1) {
        $fail += "dot $i is drawn $($dots[$i]) px across, want about $want"
    }
}
if (-not ($dots[0] -lt $dots[1] -and $dots[1] -lt $dots[2])) {
    $fail += "the dots do not grow with the width they stand for: $($dots -join ', ')"
}

# --- and the pens behind them --------------------------------------------------
# One rect per width, undone between, so each measurement is of a single stroke.
# The scan crosses the left edge at the rect's vertical middle, where the edge is
# a straight run and the corners are far away.
$pen = @(0, 0, 0)
for ($i = 0; $i -le 2; $i++) {
    $d = Width-Dot $i
    if (-not $d) { 'FAIL: no property bar'; exit 1 }
    Click $d[0] $d[1]
    Drag 900 700 1500 1100
    $g = Grab "D:\Project\winshot\obj\pdx_rect$i.png"
    $pen[$i] = Ink-Run $g 900 900 12
    $g.Dispose()
    "rect drawn at width dot ${i}: $($pen[$i]) px of ink across its left edge"
    # Undo rather than delete, and the tool stays armed: disarming closes the
    # property bar, and the next width has to be picked out of it.
    Keys '^z'
    Start-Sleep -Milliseconds 500
}
"pen widths: $($pen[0]) -> $($pen[1]) -> $($pen[2]) (tb::kDotSizes is 2/4/8)"
for ($i = 0; $i -le 2; $i++) {
    $want = @(2, 4, 8)[$i]
    if ([Math]::Abs($pen[$i] - $want) -gt 1) {
        $fail += "width dot $i draws a $($pen[$i]) px stroke, want about ${want}: the bigger dot changed the pen too"
    }
}
if (-not ($pen[0] -lt $pen[1] -and $pen[1] -lt $pen[2])) {
    $fail += "the strokes do not grow with the dot: $($pen -join ', ')"
}

Keys '{ESC}'
Start-Sleep -Milliseconds 400
if (-not $proc.HasExited) { $proc.Kill() }
if ($fail.Count) { "FAILURES: $($fail.Count)"; $fail | ForEach-Object { "  $_" }; exit 1 }
'PASS'
