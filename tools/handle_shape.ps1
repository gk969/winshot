# The selection used to mark every handle of every shape with the same white-
# cored red circle at one fixed size: an 8px rect outline grabbed by a 5px dot,
# and an ellipse or a label ringed by markers bigger than the box they sit on.
# The request is squares, sized per kind - rect and arrow tracking the stroke
# they are grabbing, ellipse and label at half what they were, and pen, mosaic
# and badge left with no markers at all.
#
# A marker is measured at the shape's top-left corner, out above and left of the
# box, where neither the guide line nor the shape's own stroke reaches: they run
# along the edges. The marker is the only red out there, and its outer edge is
# the outermost red pixel of the walk.
#
#   radius  straight up the corner's column. The shape's stroke is always
#           thinner than the marker that grabs it and lies inside, so this reads
#           the marker's radius outright: 3, 4 and 6 for the three widths.
#   side    how far left the red reaches one pixel under that outer edge. This
#           is the square test: a square's edge runs straight down, so it
#           reaches the same distance, while a circle of radius r has curved in
#           to sqrt(2r-1) by then - 3 against 6.
#
# The diagonal would seem the natural place to tell a square from a circle, but
# Gdi+ leaves the ring's corner pixel unpainted when the radius falls on a half
# pixel, which is exactly the ellipse's and the label's case, so the diagonal
# reads zero for the two markers that matter most. Measured, not assumed.
#
# Rect and arrow are drawn at all three widths, so their growth is a comparison
# between three measurements of the same thing. Ellipse and label are checked
# against the rect's own default marker, which is what they are meant to be half
# of. Mosaic is a stroke with no handles, so it gets no marker at all: what it
# does get is the 1px bounding box, whose corner sits a couple of pixels outside
# the drag because the band is round-capped - the absence of a white core is the
# thing to assert, not the absence of red.
Add-Type -AssemblyName System.Drawing, System.Windows.Forms
Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class HS {
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
# without error once Windows starts flagging the script's process "(未响应)", and
# then every later click lands wherever the pointer happened to be.
function MoveTo([int]$x, [int]$y) {
    [void][HS]::mouse_event(0x8001, [uint32][int][Math]::Floor(65535 * $x / 3840),
                            [uint32][int][Math]::Floor(65535 * $y / 2160), 0,
                            [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 90
}
function Down { [void][HS]::mouse_event($LEFTDOWN, 0, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 150 }
function Up { [void][HS]::mouse_event($LEFTUP, 0, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 350 }
# Two presses inside the double-click time, which is what makes the shell pair
# them into WM_LBUTTONDBLCLK rather than two single clicks.
function DblClick([int]$x, [int]$y) {
    MoveTo $x $y
    [void][HS]::mouse_event($LEFTDOWN, 0, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 60
    [void][HS]::mouse_event($LEFTUP, 0, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 60
    [void][HS]::mouse_event($LEFTDOWN, 0, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 60
    [void][HS]::mouse_event($LEFTUP, 0, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 450
}
function Walk([int]$x1, [int]$y1, [int]$x2, [int]$y2, [int]$steps) {
    for ($i = 1; $i -le $steps; $i++) {
        MoveTo ([int]($x1 + ($x2-$x1) * $i / $steps)) ([int]($y1 + ($y2-$y1) * $i / $steps))
    }
}
function Drag([int]$x1, [int]$y1, [int]$x2, [int]$y2) {
    MoveTo $x1 $y1; Down; Walk $x1 $y1 $x2 $y2 20; Up
}
function Click([int]$x, [int]$y) { MoveTo $x $y; Down; Up }
# Not `Type`: that is the built-in alias for Get-Content, and an alias beats a
# function, so a function of that name is never called.
function Keys([string]$s) { [void][System.Windows.Forms.SendKeys]::SendWait($s) }
function Find-Wins([string]$title) {
    $found = New-Object System.Collections.ArrayList
    $cb = [HS+EnumProc] {
        param($h, $l)
        $t = New-Object System.Text.StringBuilder 256
        [void][HS]::GetWindowText($h, $t, 256)
        if ($t.ToString() -eq $title) { [void]$found.Add($h) }
        return $true
    }
    [void][HS]::EnumWindows($cb, [IntPtr]::Zero)
    return $found.ToArray()
}
function Find-Kids([IntPtr]$parent, [string]$title) {
    $found = New-Object System.Collections.ArrayList
    $cb = [HS+EnumProc] {
        param($h, $l)
        $t = New-Object System.Text.StringBuilder 256
        [void][HS]::GetWindowText($h, $t, 256)
        if ($t.ToString() -eq $title -and [HS]::IsWindowVisible($h)) { [void]$found.Add($h) }
        return $true
    }
    [void][HS]::EnumChildWindows($parent, $cb, [IntPtr]::Zero)
    return $found.ToArray()
}
function Rect-Of([IntPtr]$h) {
    $r = New-Object HS+RECT
    [void][HS]::GetWindowRect($h, [ref]$r)
    return $r
}
# The editor window is the input surface, and it stops 4px short of the label's box
# on every side so the eight square markers and the red frame stay outside it and
# the overlay can paint them whole. The box the label draws is this rect inflated by
# that inset, and every measurement here is about that box.
function Edit-Box([IntPtr]$h) {
    $r = Rect-Of $h
    $r.left -= 4; $r.top -= 4; $r.right += 4; $r.bottom += 4
    return $r
}
# annot::kSel is (250,55,58).
function IsFull($c) { return ($c.R -gt 190 -and $c.G -lt 120 -and $c.B -lt 130) }
function IsWhite($c) { return ($c.R -gt 200 -and $c.G -gt 200 -and $c.B -gt 200) }
# Outermost fully covered red pixel walking away from a point in one direction.
# The white core sits between that point and the ring, so the walk has to cross
# a run of white before it finds any red: it only stops once it has been red and
# then not red for three pixels running, which also rides out the anti-aliased
# pixel on the ring's outer edge.
function Outer($bmp, [int]$x, [int]$y, [int]$dx, [int]$dy) {
    $last = 0; $gap = 0
    for ($k = 1; $k -le 16; $k++) {
        if (IsFull ($bmp.GetPixel($x + $dx * $k, $y + $dy * $k))) {
            $last = $k; $gap = 0
        } else {
            $gap++
            if ($last -gt 0 -and $gap -ge 3) { break }
        }
    }
    return $last
}
function Marker($bmp, [int]$x, [int]$y, [string]$tag) {
    $up = Outer $bmp $x $y 0 -1
    $side = 0
    if ($up -gt 1) { $side = Outer $bmp $x ($y - $up + 1) -1 0 }
    $white = IsWhite ($bmp.GetPixel($x - 1, $y - 1))
    "$tag marker at $x,$y : radius=$up side=$side coreWhite=$white"
    return @{ up = $up; side = $side; white = $white }
}
# The two kinds whose handles sit on a box the user can already see take half the
# default marker, square as the rest. `$ref` is the rect's own default marker
# measured earlier in the same run: it is the number these are meant to be half
# of, and comparing against it survives a pixel of rasterisation that an absolute
# threshold would not.
function Check-Half($m, [string]$what, $ref) {
    "$what marker radius $($m.up) against the rect's own default $($ref.up)"
    if (-not $m.white) { $script:fail += "the $what marker has no white core" }
    # The half-side is 2.5 and the ring is stroked 1.5 wide on top of it, so the
    # outer edge sits at 3.25 and anti-aliasing carries it to 4. What the request
    # asks is half the 5px these used to cover, and the comparison against the
    # rect's own marker below is what says that.
    if ($m.up -gt 4) {
        $script:fail += "the $what marker reaches $($m.up) px out from the corner, want 4 or less (half the 5px it used to cover)"
    }
    if ($m.up -ge $ref.up) {
        $script:fail += "the $what marker is $($m.up) px, no smaller than the rect's default $($ref.up): it did not shrink"
    }
    if ($m.up -gt 1 -and $m.side -lt $m.up - 1) {
        $script:fail += "the $what marker reaches $($m.up) px out but only $($m.side) px across just under that edge: it is still round"
    }
}
function Ink-Box($bmp, [int]$x0, [int]$y0, [int]$x1, [int]$y1) {
    $l = -1; $t = -1; $r = -1; $b = -1; $n = 0
    for ($y = $y0; $y -le $y1; $y++) {
        for ($x = $x0; $x -le $x1; $x++) {
            if (-not (IsFull ($bmp.GetPixel($x, $y)))) { continue }
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
$ov = $null
$bar = $null
function Slot([int]$i) {
    $t = @(Find-Kids $ov[0] 'WinShotToolbar')
    if ($t.Count -eq 0) { return $null }
    $tr = Rect-Of $t[0]
    $s = ($tr.bottom - $tr.top) / 32.0
    $cell = [int][Math]::Round(27 * $s); $pad = [int][Math]::Round(4 * $s)
    return @(($tr.left + $pad + [int]($cell / 2) + $i * $cell),
             [int](($tr.top + $tr.bottom) / 2))
}
# The property bar's width dots: centres at bar x + 13 + i * 25, the bar's own
# height. Arming a tool opens the bar, so this runs right after the slot click.
function Width-Dot([int]$i) {
    $pb = @(Find-Kids $ov[0] 'WinShotPropBar')
    if ($pb.Count -eq 0) { return $null }
    $b = Rect-Of $pb[0]
    return @(($b.left + 13 + $i * 25), [int](($b.top + $b.bottom) / 2))
}
# Arm a tool, pick its width, draw, disarm, then click the ink to select. The
# click lands away from every handle so it selects rather than grabs.
function Draw-And-Select([int]$slot, [int]$dot, [int]$x1, [int]$y1, [int]$x2, [int]$y2,
                         [int]$sx, [int]$sy) {
    $p = Slot $slot
    if (-not $p) { return $null }
    Click $p[0] $p[1]
    $d = Width-Dot $dot
    if (-not $d) { return $null }
    Click $d[0] $d[1]
    Drag $x1 $y1 $x2 $y2
    Click $p[0] $p[1]          # disarm, so a press on the ink selects it
    Click $sx $sy
    Start-Sleep -Milliseconds 400
    return $p
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
[void][HS]::PostMessage($sink[0], 0x8002, [IntPtr]::Zero, [IntPtr]::Zero)
Start-Sleep -Seconds 2
$ov = @(Find-Wins 'WinShotOverlay')
if ($ov.Count -eq 0) { 'FAIL: no overlay window'; exit 1 }

Drag 700 500 2000 1400
if (-not (Slot 0)) { 'FAIL: no toolbar'; exit 1 }

# --- rect: the marker has to grow with the outline it is grabbing --------------
# Same box, three widths, undo between them so each measurement is of one shape.
$rx = @(0, 0, 0)
for ($dot = 0; $dot -le 2; $dot++) {
    if (-not (Draw-And-Select 0 $dot 800 600 1300 800 900 600)) {
        "FAIL: could not draw the rect at width dot $dot"; exit 1
    }
    $g = Grab "D:\Project\winshot\obj\hs_rect$dot.png"
    $m = Marker $g 800 600 "rect dot$dot"
    $g.Dispose()
    $rx[$dot] = $m
    if (-not $m.white) { $fail += "the rect dot$dot marker has no white core at 1px out from the corner" }
    Keys '^z'                  # back to an empty canvas for the next width
    Start-Sleep -Milliseconds 500
}
"rect marker radius by width: $($rx[0].up) -> $($rx[1].up) -> $($rx[2].up)"
if (-not ($rx[0].up -lt $rx[1].up -and $rx[1].up -lt $rx[2].up)) {
    $fail += "the rect marker does not grow with the outline: $($rx[0].up), $($rx[1].up), $($rx[2].up)"
}
if ($rx[2].up -lt 5) { $fail += "the thickest rect's marker reaches only $($rx[2].up) px out, want 5 or more" }
# Square rather than round. A circle of the same radius has curved back to 3 px
# by the time it is one pixel under its own outer edge; a square is still at 6.
"rect thickest: edge runs $($rx[2].side) px across, 1 px under a $($rx[2].up) px radius"
if ($rx[2].side -lt $rx[2].up - 1) {
    $fail += "the thickest rect's marker reaches $($rx[2].up) px out but only $($rx[2].side) px across just under that edge: it is still round"
}

# --- arrow: same, on the tail handle ------------------------------------------
$ax = @(0, 0, 0)
for ($dot = 0; $dot -le 2; $dot++) {
    if (-not (Draw-And-Select 2 $dot 800 1100 1300 1300 1050 1200)) {
        "FAIL: could not draw the arrow at width dot $dot"; exit 1
    }
    $g = Grab "D:\Project\winshot\obj\hs_arrow$dot.png"
    $m = Marker $g 800 1100 "arrow dot$dot"
    $g.Dispose()
    $ax[$dot] = $m
    Keys '^z'
    Start-Sleep -Milliseconds 500
}
"arrow marker radius by width: $($ax[0].up) -> $($ax[1].up) -> $($ax[2].up)"
if (-not ($ax[0].up -lt $ax[1].up -and $ax[1].up -lt $ax[2].up)) {
    $fail += "the arrow marker does not grow with the shaft: $($ax[0].up), $($ax[1].up), $($ax[2].up)"
}
if (-not $ax[2].white) { $fail += 'the arrow marker has no white core' }
if ($ax[2].side -lt $ax[2].up - 1) {
    $fail += "the thickest arrow's marker reaches $($ax[2].up) px out but only $($ax[2].side) px across just under that edge: it is still round"
}

# --- ellipse and label: half of what every marker used to be -------------------
if (-not (Draw-And-Select 1 1 800 850 1300 1050 873 879)) {
    'FAIL: could not draw the ellipse'; exit 1
}
$g = Grab 'D:\Project\winshot\obj\hs_ellipse.png'
$el = Marker $g 800 850 'ellipse'
$g.Dispose()
Check-Half $el 'ellipse' $rx[1]

if (-not (Draw-And-Select 4 1 1400 600 1900 800 1650 700)) {
    'FAIL: could not draw the mosaic'; exit 1
}
$g = Grab 'D:\Project\winshot\obj\hs_mosaic.png'
$mo = Marker $g 1400 600 'mosaic'
$g.Dispose()
"mosaic at its drag corner: radius=$($mo.up) coreWhite=$($mo.white) (the 1px bounding box is the only chrome it gets)"
if ($mo.white) {
    $fail += 'the mosaic has a marker: its corner is white-cored like a handle, and a stroke has no handles to mark'
}

# A label: the editor's own box is the label's, so the corner to measure is known.
# A label is the one kind whose markers come and go: a single click selects it and
# draws only the red frame, because there is nothing to resize until the edit
# opens, and the eight squares appear on that same box when a double click opens
# it. Both states are measured, because "half size and square" only means
# something once they exist.
$p = Slot 5
Click $p[0] $p[1]
Click 1400 900
$ed = @(Find-Kids $ov[0] 'WinShotTextEditor')
if ($ed.Count -eq 0) { 'FAIL: clicking with the text tool opened no editor'; exit 1 }
$eb = Edit-Box $ed[0]
Keys 'HANDLESHAPE'
Start-Sleep -Milliseconds 700
# Plain Enter belongs to the control and inserts a newline; Ctrl+Enter commits.
Keys '^({ENTER})'
Start-Sleep -Milliseconds 600
Click $p[0] $p[1]              # disarm
$g = Grab 'D:\Project\winshot\obj\hs_label_ink.png'
# Inset past the box edge: the frame is stroked 2px outside it and the markers
# straddle it, so a shallow inset would report the selection chrome as ink and
# the click below would land on a handle instead of on a glyph. The ink itself
# starts 6px below the top edge, so any deeper and the glyphs get clipped.
$ink = Ink-Box $g ($eb.left + 4) ($eb.top + 4) ($eb.right - 5) ($eb.bottom - 5)
$g.Dispose()
if (-not $ink) { 'FAIL: the label drew no ink'; exit 1 }
Click ($ink.l + 20) ($ink.t + 5)
Start-Sleep -Milliseconds 400
$g = Grab 'D:\Project\winshot\obj\hs_label_sel.png'
$sel = Marker $g $eb.left $eb.top 'label selected'
$g.Dispose()
"selected label: radius=$($sel.up) coreWhite=$($sel.white) (the frame is the only chrome here)"
if ($sel.white) {
    $fail += 'a selected label that is not being edited shows a marker: it has no handles to mark until the edit opens'
}
DblClick ($ink.l + 20) ($ink.t + 5)
Start-Sleep -Milliseconds 400
$g = Grab 'D:\Project\winshot\obj\hs_label.png'
$tx = Marker $g $eb.left $eb.top 'label editing'
$g.Dispose()
Check-Half $tx 'label' $rx[1]

Keys '{ESC}'
Start-Sleep -Milliseconds 400
if (-not $proc.HasExited) { $proc.Kill() }
if ($fail.Count) { "FAILURES: $($fail.Count)"; $fail | ForEach-Object { "  $_" }; exit 1 }
'PASS'
