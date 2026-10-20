# The selection's own frame is a 2px pen centred on the selection's edge, so it owns the
# first pixel inside the selection -- column sel.left, column sel.right-1, and the
# two rows like them. It is also painted after every annotation, so an outline
# parked on that pixel is never read as its own line: it is the frame. The request
# is that an element keep at least one clear pixel from that frame, on a fresh drag,
# on a move, and for a text label's red edit frame as well.
#
# The arithmetic the code carries (annot::kFrameClearance = 2, kEditFramePad = 3):
#   a shape's ink          starts at sel.left + 2  -> one clear column at +1
#   a label's box          starts at sel.left + 5  -> its red frame, whose outermost
#                                                    pixel measures 3 columns off the
#                                                    box, lands at +2
#   a typed line           stops its box at sel.right - 5 for the same reason
#
# The selection's frame is drawn as a band that reaches 3px inside the selection and
# clears what it clips, so a label against the edge does not have its red frame
# covered by the blue one -- the near side of it is erased outright. Stages D and E
# read the frame's own columns back, so they fail if it goes missing again.
#
# Every stage parks one element hard against an edge and reads the columns back off
# the screen, so what is asserted is the pixels rather than the constants.
#
# The predicates are colour *dominance*, not colour match: red-dominance (R - B > 40)
# for ink and blue-dominance (B - R > 40) for the frame. Counting only solid ink
# would measure the gap from the core of an anti-aliased stroke and report a
# clearance the eye does not see, because the fringe is the part nearest the frame.
# The ground is a notepad page -- white inside the selection, greyed outside it -- so
# neither predicate can be satisfied by the desktop itself, and a clear pixel reads
# as neither.
Add-Type -AssemblyName System.Drawing, System.Windows.Forms
Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class AG {
    public delegate bool EnumProc(IntPtr h, IntPtr l);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
    [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr p, EnumProc cb, IntPtr l);
    [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint msg, IntPtr w, IntPtr l);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern bool MoveWindow(IntPtr h, int x, int y, int w, int ht, bool repaint);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
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
# Absolute mouse_event rather than Cursor.Position: the latter stops moving without
# error once Windows starts flagging the script's process as not responding.
function MoveTo([int]$x, [int]$y) {
    [void][AG]::mouse_event(0x8001, [uint32][int][Math]::Round(65535 * $x / 3839),
                            [uint32][int][Math]::Round(65535 * $y / 2159), 0,
                            [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 90
}
function Down { [void][AG]::mouse_event($LEFTDOWN, 0, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 150 }
function Up { [void][AG]::mouse_event($LEFTUP, 0, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 350 }
function Walk([int]$x1, [int]$y1, [int]$x2, [int]$y2, [int]$steps) {
    for ($i = 1; $i -le $steps; $i++) {
        MoveTo ([int]($x1 + ($x2-$x1) * $i / $steps)) ([int]($y1 + ($y2-$y1) * $i / $steps))
    }
}
# The step count matters here more than anywhere else in the suite: the clamp stops
# the element while the pointer keeps going, so a coarse drag leaves it parked up to
# one step short of the limit and a clearance measured there proves nothing.
function Drag([int]$x1, [int]$y1, [int]$x2, [int]$y2, [int]$steps = 20) {
    MoveTo $x1 $y1; Down; Walk $x1 $y1 $x2 $y2 $steps; Up
}
function Click([int]$x, [int]$y) { MoveTo $x $y; Down; Up }
function Keys([string]$s) { [void][System.Windows.Forms.SendKeys]::SendWait($s) }
function Find-Wins([string]$title) {
    $found = New-Object System.Collections.ArrayList
    $cb = [AG+EnumProc] {
        param($h, $l)
        $t = New-Object System.Text.StringBuilder 256
        [void][AG]::GetWindowText($h, $t, 256)
        if ($t.ToString() -eq $title) { [void]$found.Add($h) }
        return $true
    }
    [void][AG]::EnumWindows($cb, [IntPtr]::Zero)
    return $found.ToArray()
}
function Find-Kids([IntPtr]$parent, [string]$title) {
    $found = New-Object System.Collections.ArrayList
    $cb = [AG+EnumProc] {
        param($h, $l)
        $t = New-Object System.Text.StringBuilder 256
        [void][AG]::GetWindowText($h, $t, 256)
        if ($t.ToString() -eq $title -and [AG]::IsWindowVisible($h)) { [void]$found.Add($h) }
        return $true
    }
    [void][AG]::EnumChildWindows($parent, $cb, [IntPtr]::Zero)
    return $found.ToArray()
}
# The notepad's own top-level window: by pid and by class rather than by title,
# whose untitled form is localized and so not something this file can spell.
function Find-PidWindow([int]$pid_, [string]$cls) {
    $found = New-Object System.Collections.ArrayList
    $cb = [AG+EnumProc] {
        param($h, $l)
        $p = [uint32]0
        [void][AG]::GetWindowThreadProcessId($h, [ref]$p)
        if ($p -eq $pid_ -and [AG]::IsWindowVisible($h)) {
            $c = New-Object System.Text.StringBuilder 64
            [void][AG]::GetClassName($h, $c, 64)
            if ($c.ToString() -eq $cls) { [void]$found.Add($h) }
        }
        return $true
    }
    [void][AG]::EnumWindows($cb, [IntPtr]::Zero)
    $a = $found.ToArray()
    if ($a.Count -eq 0) { return $null }
    return $a[0]
}
function Rect-Of([IntPtr]$h) {
    $r = New-Object AG+RECT
    [void][AG]::GetWindowRect($h, [ref]$r)
    return $r
}
$ov = $null
# Toolbar slots 0..6 are plain cells before the first separator: rect, ellipse,
# arrow, pen, mosaic, text, badge. Clicking the armed one again disarms it, which is
# what makes a press on the ink move it instead of drawing another shape.
function Click-Slot([int]$i) {
    $t = @(Find-Kids $ov[0] 'WinShotToolbar')
    if ($t.Count -eq 0) { return $false }
    $tr = Rect-Of $t[0]
    $s = ($tr.bottom - $tr.top) / 32.0
    $cell = [int][Math]::Round(27 * $s); $pad = [int][Math]::Round(4 * $s)
    Click ($tr.left + $pad + $i * $cell + [int]($cell / 2)) ([int](($tr.top + $tr.bottom) / 2))
    Start-Sleep -Milliseconds 350
    return $true
}
function Editor() {
    $e = @(Find-Kids $ov[0] 'WinShotTextEditor')
    if ($e.Count -eq 0) { return $null }
    return $e[0]
}
# The editor window is the input surface and stops 4px short of the label's box on
# every side, so that the red frame and the eight square markers stay outside it and
# the overlay can paint them whole. The box the label draws is this rect inflated by
# that inset.
function Edit-Box([IntPtr]$h) {
    $r = Rect-Of $h
    $r.left -= 4; $r.top -= 4; $r.right += 4; $r.bottom += 4
    return $r
}

function IsBlue($c) { return ($c.B - $c.R -gt 40 -and $c.B -gt 120) }
function IsRed($c) { return ($c.R - $c.B -gt 40 -and $c.R -gt 120) }

# The red extent of one shape inside a window: what a drag has to press on, and what
# the clamp is measured against.
function Ink-Box($bmp, [int]$x0, [int]$y0, [int]$x1, [int]$y1) {
    $l = -1; $t = -1; $r = -1; $b = -1; $n = 0
    for ($y = $y0; $y -le $y1; $y++) {
        for ($x = $x0; $x -le $x1; $x++) {
            if (-not (IsRed ($bmp.GetPixel($x, $y)))) { continue }
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
function Red-In($bmp, [int]$x0, [int]$y0, [int]$x1, [int]$y1) {
    $n = 0
    for ($y = $y0; $y -le $y1; $y += 2) {
        for ($x = $x0; $x -le $x1; $x += 2) { if (IsRed ($bmp.GetPixel($x, $y))) { $n++ } }
    }
    return $n
}
# A point on the shape's own outline that is not one of its eight resize handles: a
# quarter along the top edge for a rect, the upper-left diagonal for an ellipse,
# whose outline only passes near the bbox's edge midpoints. A press on a handle
# resizes the shape, and the request is about moving it. Both are measured from the
# ink box, which is the stroke's own extent -- 2px past the geometric box at this
# pen width, well inside the +-8px the hit test allows.
function Grab-Point($box, [string]$kind) {
    if ($kind -eq 'ellipse') {
        $cx = ($box.l + $box.r) / 2.0; $cy = ($box.t + $box.b) / 2.0
        $rx = ($box.r - $box.l) / 2.0 - 2.0; $ry = ($box.b - $box.t) / 2.0 - 2.0
        return @([int][Math]::Round($cx - $rx * 0.7071),
                 [int][Math]::Round($cy - $ry * 0.7071))
    }
    return @([int][Math]::Round($box.l + ($box.r - $box.l) / 4.0), $box.t)
}
# One row across an edge: the innermost column of the selection's frame and the first
# column of ink on the far side of it. The clearance asked for is the count of
# columns that are neither, which is red - blue - 1.
function Edge-Gap($bmp, [int]$y, [int]$x0, [int]$x1, [bool]$fromLeft) {
    $blue = -1; $red = -1
    if ($fromLeft) {
        for ($x = $x0; $x -le $x1; $x++) { if (IsBlue ($bmp.GetPixel($x, $y))) { $blue = $x } }
        for ($x = $blue + 1; $x -le $x1; $x++) {
            if (IsRed ($bmp.GetPixel($x, $y))) { $red = $x; break }
        }
    } else {
        for ($x = $x1; $x -ge $x0; $x--) { if (IsBlue ($bmp.GetPixel($x, $y))) { $blue = $x } }
        for ($x = $blue - 1; $x -ge $x0; $x--) {
            if (IsRed ($bmp.GetPixel($x, $y))) { $red = $x; break }
        }
    }
    if ($blue -lt 0 -or $red -lt 0) { return @{ blue = $blue; red = $red; gap = -1; y = $y } }
    return @{ blue = $blue; red = $red; gap = [Math]::Abs($red - $blue) - 1; y = $y }
}
# The worst row of a band, because one row where the two lines touch is the defect
# and an average would hide it. `none` counts the rows that found no frame or no
# ink at all: those are a broken measurement, not a wide clearance.
function Band-Gap($bmp, [int]$y0, [int]$y1, [int]$x0, [int]$x1, [bool]$fromLeft) {
    $worst = $null; $none = 0
    for ($y = $y0; $y -le $y1; $y++) {
        $g = Edge-Gap $bmp $y $x0 $x1 $fromLeft
        if ($g.gap -lt 0) { $none++; continue }
        if (-not $worst -or $g.gap -lt $worst.gap) { $worst = $g }
    }
    if (-not $worst) { return @{ gap = -1; blue = -1; red = -1; y = -1; none = $none } }
    return @{ gap = $worst.gap; blue = $worst.blue; red = $worst.red; y = $worst.y; none = $none }
}

$sel = @(800, 600, 2400, 1600)
$LX0 = $sel[0] - 8; $LX1 = $sel[0] + 40
$RX0 = $sel[2] - 40; $RX1 = $sel[2] + 8
$fail = @()

function Bail([string]$msg) {
    if ($proc -and -not $proc.HasExited) { $proc.Kill() }
    if ($np -and -not $np.HasExited) { $np.Kill() }
    "FAIL: $msg"
    exit 1
}

MoveTo 3000 2000
Start-Sleep -Milliseconds 400
Get-Process winshot -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 600

# A notepad page under the whole selection, so the ground inside the frame is white and
# outside it greyed -- neither red-dominant nor blue-dominant, which is what makes a
# clear pixel identifiable as one.
$NOTEPAD = "$env:SystemRoot\System32\notepad.exe"
$np = Start-Process -FilePath $NOTEPAD -PassThru
Start-Sleep -Seconds 2
$nh = Find-PidWindow $np.Id 'Notepad'
if (-not $nh) { Bail 'could not find the notepad window' }
[void][AG]::MoveWindow($nh, 400, 300, 2400, 1600, $true)
[void][AG]::SetForegroundWindow($nh)
Start-Sleep -Milliseconds 800

$proc = Start-Process -FilePath 'D:\Project\winshot\x64\Debug\winshot.exe' -PassThru
Start-Sleep -Seconds 2
$sink = @(Find-Wins 'WinShotSink')
if ($sink.Count -eq 0) { Bail 'no sink window' }
[void][AG]::PostMessage($sink[0], 0x8002, [IntPtr]::Zero, [IntPtr]::Zero)
Start-Sleep -Seconds 2
$ov = @(Find-Wins 'WinShotOverlay')
if ($ov.Count -eq 0) { Bail 'no overlay window' }

Drag $sel[0] $sel[1] $sel[2] $sel[3]
MoveTo 3000 2000
Start-Sleep -Milliseconds 500

# The page has to be what is under the frame: a notepad that lost the foreground
# before the still was taken would put the desktop there instead, and the predicates
# would be reading wallpaper.
$g = Grab ''
$lit = 0
for ($k = 0; $k -lt 9; $k++) {
    # Well inside the frame on every side: the ground outside it is dimmed and the
    # frame itself is blue, and neither is the page.
    $c = $g.GetPixel(1000 + $k * 150, 800 + ($k % 3) * 300)
    if ($c.R -gt 200 -and $c.G -gt 200 -and $c.B -gt 200) { $lit++ }
}
$base = Red-In $g ($sel[0] + 4) ($sel[1] + 4) ($sel[2] - 4) ($sel[3] - 4)
$g.Dispose()
"page under the selection: $lit of 9 samples white, $base red px in the still itself"
if ($lit -lt 9) { Bail 'the selection is not over a white page: the notepad is not in front' }
if ($base -gt 40) { Bail "the still already carries $base red px, so nothing here can be attributed to a shape" }

# Each stage measures one shape, so the last one has to be gone before the next: ink
# left behind lands in the next stage's scan window, and a shape still under the press
# is grabbed there instead of a new one being drawn. How many records a stage leaves
# is not counted -- an edit that is cancelled and a move are not the same number -- so
# this undoes until the band is clean and says so if it will not clean.
function Clear-Canvas() {
    $left = 0
    for ($i = 0; $i -lt 5; $i++) {
        $g = Grab ''
        $left = Red-In $g ($LX0 - 4) 640 ($LX1 + 4) 1440
        $g.Dispose()
        if ($left -eq 0) { return }
        Keys '^z'
        Start-Sleep -Milliseconds 500
    }
    $script:fail += "undo left $left red px in the scan band, so the next measurement is contaminated"
}

# --- A. a rectangle dragged out from outside the selection --------------------------
# The press lands at 700,500, a hundred pixels outside the frame, and only the
# anchor clamp stands between this box's ink and the edge: a box recomputes from its
# anchor on every move, so an anchor parked on the frame would keep that edge no
# matter where the pointer went.
if (-not (Click-Slot 0)) { Bail 'no toolbar to arm the rectangle tool' }
Drag 700 500 1400 900
# Disarmed again here and not at the head of the next stage: a tool stays armed
# after the shape it drew, so the next stage's click would take it off rather than
# put it on.
if (-not (Click-Slot 0)) { Bail 'no toolbar to disarm the rectangle tool' }
MoveTo 3000 2000
Start-Sleep -Milliseconds 500
$a = Grab 'D:\Project\winshot\obj\ag_new_rect.png'
$gA = Band-Gap $a 700 820 $LX0 $LX1 $true
$boxA = Ink-Box $a ($LX0 - 4) 640 ($LX1 + 4) 940
$a.Dispose()
"new rect from outside: frame at $($gA.blue), ink at $($gA.red), gap $($gA.gap) px, worst row $($gA.y), $($gA.none) rows unread"
if ($gA.none -gt 0) {
    $fail += "stage A read no frame or no ink on $($gA.none) of 121 rows, so the clearance was never measured"
} else {
    if ($gA.blue -lt $sel[0] - 2 -or $gA.blue -gt $sel[0] + 1) {
        $fail += "the selection's frame was found at column $($gA.blue) instead of at the selection's own edge at $($sel[0])"
    }
    if ($gA.red - $sel[0] -gt 8) {
        $fail += "a rect dragged from outside stopped with its ink at $($gA.red), $($gA.red - $sel[0]) px in from the frame: the press point was never clamped"
    }
    if ($gA.gap -lt 1) {
        $fail += "a rect dragged out from outside the selection has $($gA.gap) clear px between its ink and the frame at row $($gA.y): the frame paints over it"
    }
}
Clear-Canvas

# --- B. moving a rectangle to the edge ----------------------------------------
# Drawn clear of every edge, so the only thing that can stop it here is the clamp on
# the move. The pointer travels 20px past where the ink has to stop, two pixels at a
# time.
if (-not (Click-Slot 0)) { Bail 'no toolbar to arm the rectangle tool' }
Drag 1000 950 1500 1150
if (-not (Click-Slot 0)) { Bail 'no toolbar to disarm the rectangle tool' }
$s = Grab 'D:\Project\winshot\obj\ag_rect_before.png'
$boxB = Ink-Box $s 960 910 1560 1200
$s.Dispose()
if (-not $boxB) { Bail 'the rectangle was never drawn' }
$p = Grab-Point $boxB 'rect'
$want = ($boxB.l - ($sel[0] + 2)) + 20
"rect at $($boxB.l),$($boxB.t) .. $($boxB.r),$($boxB.b): pressed at $($p[0]),$($p[1]), pointer travels $want px left"
Drag $p[0] $p[1] ($p[0] - $want) $p[1] ([int][Math]::Ceiling($want / 2.0))
MoveTo 3000 2000
Start-Sleep -Milliseconds 500
$b = Grab 'D:\Project\winshot\obj\ag_rect_moved.png'
$gB = Band-Gap $b 1020 1080 $LX0 $LX1 $true
$b.Dispose()
"moved rect: frame at $($gB.blue), ink at $($gB.red), gap $($gB.gap) px, worst row $($gB.y), $($gB.none) rows unread"
if ($gB.none -gt 0) {
    $fail += "stage B read no frame or no ink on $($gB.none) of 61 rows, so the clearance was never measured"
} else {
    if ($gB.red - $sel[0] -gt 8) {
        $fail += "a dragged rect stopped with its ink at $($gB.red), $($gB.red - $sel[0]) px in from the frame: it was stopped early, so the clearance it shows is not the one at the limit"
    }
    if ($gB.gap -lt 1) {
        $fail += "a rect moved against the selection has $($gB.gap) clear px between its ink and the frame at row $($gB.y)"
    }
}
Clear-Canvas

# --- C. moving an ellipse to the edge -----------------------------------------
# The other shape the request names by hand. Its leftmost ink is at the vertical
# middle, which is where the band sits; a row either side of it the curve has
# already moved inward, so the clearance there is wider, never narrower.
if (-not (Click-Slot 1)) { Bail 'no toolbar to arm the ellipse tool' }
Drag 1000 1200 1500 1400
if (-not (Click-Slot 1)) { Bail 'no toolbar to disarm the ellipse tool' }
$s = Grab 'D:\Project\winshot\obj\ag_ell_before.png'
$boxC = Ink-Box $s 960 1160 1560 1450
$s.Dispose()
if (-not $boxC) { Bail 'the ellipse was never drawn' }
$p = Grab-Point $boxC 'ellipse'
$want = ($boxC.l - ($sel[0] + 2)) + 20
"ellipse at $($boxC.l),$($boxC.t) .. $($boxC.r),$($boxC.b): pressed at $($p[0]),$($p[1]), pointer travels $want px left"
Drag $p[0] $p[1] ($p[0] - $want) $p[1] ([int][Math]::Ceiling($want / 2.0))
MoveTo 3000 2000
Start-Sleep -Milliseconds 500
$c = Grab 'D:\Project\winshot\obj\ag_ell_moved.png'
$gC = Band-Gap $c 1290 1310 $LX0 $LX1 $true
$c.Dispose()
"moved ellipse: frame at $($gC.blue), ink at $($gC.red), gap $($gC.gap) px, worst row $($gC.y), $($gC.none) rows unread"
if ($gC.none -gt 0) {
    $fail += "stage C read no frame or no ink on $($gC.none) of 21 rows, so the clearance was never measured"
} else {
    if ($gC.red - $sel[0] -gt 8) {
        $fail += "a dragged ellipse stopped with its ink at $($gC.red), $($gC.red - $sel[0]) px in from the frame: it was stopped early"
    }
    if ($gC.gap -lt 1) {
        $fail += "an ellipse moved against the selection has $($gC.gap) clear px between its ink and the frame at row $($gC.y)"
    }
}
Clear-Canvas

# --- D. a text label's red frame ----------------------------------------------
# The label's box is what the clamp holds, and the red frame's outermost pixel is 3
# columns outside it, so the box has to sit five pixels in for the frame to keep its
# one clear column. A label created on the edge is checked as window geometry,
# because that is the number the code decides; the drag is checked as pixels, because
# that is what the request is about.
if (-not (Click-Slot 5)) { Bail 'no toolbar to arm the text tool' }
Click 700 500
Start-Sleep -Milliseconds 600
$ed = Editor
if (-not $ed) { Bail 'clicking with the text tool outside the selection opened no editor' }
$nb = Edit-Box $ed
"new label from 700,500: box at $($nb.left),$($nb.top) .. $($nb.right),$($nb.bottom)"
if ([Math]::Abs($nb.left - ($sel[0] + 5)) -gt 2) {
    $fail += "a label created outside the selection got its box at x=$($nb.left), want $($sel[0] + 5): its red frame would start under the selection's own"
}
if ([Math]::Abs($nb.top - ($sel[1] + 5)) -gt 2) {
    $fail += "a label created outside the selection got its box at y=$($nb.top), want $($sel[1] + 5)"
}
Keys '{ESC}'
Start-Sleep -Milliseconds 600

Click 1000 700
Start-Sleep -Milliseconds 600
$ed = Editor
if (-not $ed) { Bail 'clicking with the text tool opened no editor' }
Keys 'abc'
Start-Sleep -Milliseconds 600
Keys '^({ENTER})'
Start-Sleep -Milliseconds 700
if (-not (Click-Slot 5)) { Bail 'no toolbar to disarm the text tool' }
$s = Grab 'D:\Project\winshot\obj\ag_text_before.png'
$boxD = Ink-Box $s 960 660 1120 790
$s.Dispose()
if (-not $boxD) { Bail 'the text label drew no red frame' }
$p = @([int](($boxD.l + $boxD.r) / 2), [int](($boxD.t + $boxD.b) / 2))
$want = ($boxD.l - ($sel[0] + 2)) + 20
"label frame at $($boxD.l),$($boxD.t) .. $($boxD.r),$($boxD.b): pressed at $($p[0]),$($p[1]), pointer travels $want px left"
Drag $p[0] $p[1] ($p[0] - $want) $p[1] ([int][Math]::Ceiling($want / 2.0))
MoveTo 3000 2000
Start-Sleep -Milliseconds 500
$d = Grab 'D:\Project\winshot\obj\ag_text_moved.png'
$gD = Band-Gap $d ([int](($boxD.t + $boxD.b) / 2) - 8) ([int](($boxD.t + $boxD.b) / 2) + 8) $LX0 $LX1 $true
$d.Dispose()
"moved label: frame at $($gD.blue), red frame at $($gD.red), gap $($gD.gap) px, worst row $($gD.y), $($gD.none) rows unread"
if ($gD.none -gt 0) {
    $fail += "stage D read no frame or no ink on $($gD.none) of 17 rows, so the clearance was never measured"
} else {
    if ($gD.red - $sel[0] -gt 8) {
        $fail += "a dragged label stopped with its red frame at $($gD.red), $($gD.red - $sel[0]) px in from the frame: it was stopped early"
    }
    if ($gD.gap -lt 1) {
        $fail += "a label moved against the selection has $($gD.gap) clear px between its red frame and the selection's own at row $($gD.y)"
    }
}
Clear-Canvas

# --- E. a typed line stops its box short of the frame -------------------------
# The box grows sideways as the text grows, and the editor's own limit is the
# selection inset by the same five pixels, so the line wraps instead of running under
# the frame. It has to be a line longer than the room available, or the box stops at
# its one-line width and never meets the limit. Read from the editor window, which is
# the box, and then off the screen.
if (-not (Click-Slot 5)) { Bail 'no toolbar to arm the text tool' }
Click 1000 1250
Start-Sleep -Milliseconds 600
$ed = Editor
if (-not $ed) { Bail 'no editor for the long line' }
Keys ('abcdefghij ' * 20)
Start-Sleep -Milliseconds 900
$ne = Edit-Box $ed
"long line: box at $($ne.left),$($ne.top) .. $($ne.right),$($ne.bottom), selection right edge $($sel[2])"
if ($ne.right -gt $sel[2] - 2) {
    $fail += "a typed line grew its box to x=$($ne.right), $(2400 - $ne.right) px from the selection's edge at $($sel[2]): the red frame is under the frame"
}
if ($ne.right -lt $sel[2] - 24) {
    $fail += "a typed line stopped its box at x=$($ne.right), $($sel[2] - $ne.right) px short of the edge: the limit is inset further than the two frames need"
}
$mid = [int](($ne.top + $ne.bottom) / 2)
MoveTo 3000 2000
Start-Sleep -Milliseconds 500
$e = Grab 'D:\Project\winshot\obj\ag_text_right.png'
$gE = Band-Gap $e ($mid - 8) ($mid + 8) $RX0 $RX1 $false
$e.Dispose()
"right edge: frame at $($gE.blue), red frame at $($gE.red), gap $($gE.gap) px, worst row $($gE.y), $($gE.none) rows unread"
if ($gE.none -gt 0) {
    $fail += "stage E read no frame or no ink on $($gE.none) of 17 rows, so the clearance was never measured"
} elseif ($gE.gap -lt 1) {
    $fail += "a typed line left $($gE.gap) clear px between the label's red frame and the selection's own at row $($gE.y)"
}

Keys '{ESC}'
Start-Sleep -Milliseconds 400
if (-not $proc.HasExited) { $proc.Kill() }
if ($np -and -not $np.HasExited) { $np.Kill() }
if ($fail.Count) { "FAILURES: $($fail.Count)"; $fail | ForEach-Object { "  $_" }; exit 1 }
'PASS'
