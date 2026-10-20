# The text editor is a real EDIT child, and it used to paint its background with
# the average colour sampled from behind it: an opaque block while you typed,
# turning transparent only once the edit closed. It also grew sideways to the
# screen's right edge rather than the region's, and never wrapped.
#
# Four things are checked. The backdrop: a red rectangle is drawn first and the
# editor is opened across its top stroke, so a transparent backdrop has to show
# that stroke and an opaque one cannot. The wrap: a long string pushes the box's
# right edge onto the region's and grows it downwards. The stop: past the region's
# bottom the control takes no more characters. The committed label: double-clicking
# it brings its box back with the width it was left at, dragging the right marker
# of that box re-wraps it, and the rows that no longer fit are not drawn below it.
Add-Type -AssemblyName System.Drawing, System.Windows.Forms
Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class TW {
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

# Mirrors annot::kTextPadY. The single-line box is one whole line cell plus this
# much, so subtracting it from a measured box height yields the line pitch -- which
# is what every growth assertion below needs. It is a mirror and not a measurement
# only because the alternative is to derive the pitch from two box heights and lose
# the assertion's meaning if the box never grows.
$PADY = 3

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
function Down { [void][TW]::mouse_event($LEFTDOWN, 0, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 150 }
function Up { [void][TW]::mouse_event($LEFTUP, 0, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 350 }
function Walk([int]$x1, [int]$y1, [int]$x2, [int]$y2, [int]$steps) {
    for ($i = 1; $i -le $steps; $i++) {
        MoveTo ([int]($x1 + ($x2-$x1) * $i / $steps)) ([int]($y1 + ($y2-$y1) * $i / $steps))
    }
}
function Drag([int]$x1, [int]$y1, [int]$x2, [int]$y2) {
    MoveTo $x1 $y1; Down; Walk $x1 $y1 $x2 $y2 20; Up
}
function Click([int]$x, [int]$y) { MoveTo $x $y; Down; Up }
function DblClick([int]$x, [int]$y) {
    MoveTo $x $y
    [void][TW]::mouse_event($LEFTDOWN, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 60
    [void][TW]::mouse_event($LEFTUP, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 60
    [void][TW]::mouse_event($LEFTDOWN, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 60
    [void][TW]::mouse_event($LEFTUP, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 450
}
# Not `Type`: that is the built-in alias for Get-Content, and an alias beats a
# function, so a function of that name is never called.
function Keys([string]$s) { [void][System.Windows.Forms.SendKeys]::SendWait($s) }
function Find-Wins([string]$title) {
    $found = New-Object System.Collections.ArrayList
    $cb = [TW+EnumProc] {
        param($h, $l)
        $t = New-Object System.Text.StringBuilder 256
        [void][TW]::GetWindowText($h, $t, 256)
        if ($t.ToString() -eq $title) { [void]$found.Add($h) }
        return $true
    }
    [void][TW]::EnumWindows($cb, [IntPtr]::Zero)
    return $found.ToArray()
}
function Find-Kids([IntPtr]$parent, [string]$title) {
    $found = New-Object System.Collections.ArrayList
    $cb = [TW+EnumProc] {
        param($h, $l)
        $t = New-Object System.Text.StringBuilder 256
        [void][TW]::GetWindowText($h, $t, 256)
        if ($t.ToString() -eq $title -and [TW]::IsWindowVisible($h)) { [void]$found.Add($h) }
        return $true
    }
    [void][TW]::EnumChildWindows($parent, $cb, [IntPtr]::Zero)
    return $found.ToArray()
}
function Rect-Of([IntPtr]$h) {
    $r = New-Object TW+RECT
    [void][TW]::GetWindowRect($h, [ref]$r)
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
function IsRed($c) { return ($c.R -gt 190 -and $c.G -lt 120 -and $c.B -lt 130) }
function RedCount($bmp, [int]$x0, [int]$y0, [int]$x1, [int]$y1) {
    $n = 0
    for ($y = $y0; $y -le $y1; $y++) {
        for ($x = $x0; $x -le $x1; $x++) { if (IsRed ($bmp.GetPixel($x, $y))) { $n++ } }
    }
    return $n
}
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
function Editor() {
    $e = @(Find-Kids $ov[0] 'WinShotTextEditor')
    if ($e.Count -eq 0) { return $null }
    return $e[0]
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
[void][TW]::PostMessage($sink[0], 0x8002, [IntPtr]::Zero, [IntPtr]::Zero)
Start-Sleep -Seconds 2
$ov = @(Find-Wins 'WinShotOverlay')
if ($ov.Count -eq 0) { 'FAIL: no overlay window'; exit 1 }

Drag $sel[0] $sel[1] $sel[2] $sel[3]
# The still under the frame is the desktop as it was, and the desktop has its own
# red in it -- a ClearType glyph here once read as 42px of undo residue. What an
# undo has to answer for is the difference from this, never an absolute zero.
Start-Sleep -Milliseconds 300
$b0 = Grab ''
$baseRed = RedCount $b0 890 690 1510 1010
$b0.Dispose()
$p = Slot 0
if (-not $p) { 'FAIL: no toolbar'; exit 1 }
Click $p[0] $p[1]              # the rectangle tool
Drag 900 700 1500 1000
$p = Slot 5
Click $p[0] $p[1]              # the text tool

# --- the backdrop while typing -----------------------------------------------
# The editor opens at 950,690, so its box straddles the rectangle's top stroke at
# y 698..702. A transparent backdrop shows that stroke across the whole width of
# the box; the old sampled block shows none of it. The same rows just left of the
# box, over the same stroke, are the control.
Click 950 690
$ed = Editor
if (-not $ed) { 'FAIL: clicking with the text tool opened no editor'; exit 1 }
Keys 'abc'
Start-Sleep -Milliseconds 600
MoveTo 2300 1800; Start-Sleep -Milliseconds 400
$er = Edit-Box $ed

$a = Grab 'D:\Project\winshot\obj\tw_backdrop.png'
$in = RedCount $a ($er.left + 3) 698 ($er.right - 3) 702
$out = RedCount $a 905 698 945 702
$a.Dispose()
$span = ($er.right - 3) - ($er.left + 3) + 1
"editor at $($er.left),$($er.top) .. $($er.right),$($er.bottom); stroke rows: $in red px of $($span * 5) inside, $out red px of 205 outside"
if ($out -lt 150) { $fail += "the control window has no stroke ($out), so the backdrop check proves nothing" }
if ($in -lt [int](0.6 * $span * 5)) {
    $fail += "the editor's backdrop is opaque: only $in of $($span * 5) px on the stroke's rows are red"
}
Keys '{ESC}'
Start-Sleep -Milliseconds 500

# --- clear the canvas so the label is the only ink ---------------------------
Keys '^z'
Start-Sleep -Milliseconds 500
$c = Grab 'D:\Project\winshot\obj\tw_cleared.png'
$rest = RedCount $c 890 690 1510 1010
$c.Dispose()
"ink left after undo: $rest red px, against $baseRed in the still itself"
if ($rest -gt $baseRed) {
    $fail += "undo left $($rest - $baseRed) red px over the $baseRed the still already had, so the label measurements are contaminated"
}

# --- a long string wraps into the region instead of past its right edge --------
Click 950 690
$ed = Editor
if (-not $ed) { 'FAIL: no editor for the long string'; exit 1 }
$r0 = Edit-Box $ed

$h0 = $r0.bottom - $r0.top
Keys ('abcdefghij ' * 13)
Start-Sleep -Milliseconds 900
$r1 = Edit-Box $ed

"after 143 chars: box $($r1.left),$($r1.top) .. $($r1.right),$($r1.bottom), height $h0 -> $($r1.bottom - $r1.top)"
# The right limit is 1595 for the same reason the bottom one is 1395 further down.
if ($r1.right -gt 1597) { $fail += "the box ran past the region's right edge: right=$($r1.right), limit 1595" }
if ($r1.right -lt 1575) { $fail += "the box stopped at $($r1.right) instead of using the region's width" }
# The single-line box is one line cell plus $PADY, so $h0 - $PADY is the line pitch
# exactly and two more lines is the least wrapping 143 characters at this width can
# produce. Asserting against the pitch rather than a fraction of the box height
# matters now that the box is only a line tall: the old bound was a third of it.
$h1 = $r1.bottom - $r1.top
$lh = $h0 - $PADY
if ($h1 - $h0 -lt 2 * $lh) {
    $fail += "the box did not grow down: height $h0 -> $h1, want at least two more lines"
}

# --- commit, then narrow the label from its right marker ---------------------
# More text first: the narrowing test wants enough of it that rows genuinely stop
# fitting. The box the editor ends on is the label's box, so its markers are known
# exactly. The inset has to stay clear of the eight markers, which reach 5px inside
# the box edge, and still hold every line of ink, which since the padding was
# tightened ends 5px above the bottom edge as well. The two constraints meet, so the
# bottom inset sits inside the marker band and lets the bottom marker's row merge
# into the last ink band; that is cheaper than cutting the last line, and every
# assertion here compares the same window before and after, so the markers cancel.
Keys ('abcdefghij ' * 10)
Start-Sleep -Milliseconds 900
$box = Edit-Box $ed

$il = $box.left + 8; $it = $box.top + 8; $ir = $box.right - 9; $ib = $box.bottom - 4
MoveTo 2300 1800; Start-Sleep -Milliseconds 300
$g0 = Grab 'D:\Project\winshot\obj\tw_before_narrow.png'
$n0 = RedCount $g0 $il $it $ir $ib
$ink0 = Ink-Box $g0 $il $it $ir $ib
$g0.Dispose()
if (-not $ink0) { 'FAIL: no text ink to narrow'; exit 1 }
"label before commit: box $($box.left),$($box.top) .. $($box.right),$($box.bottom), $($ink0.n) red px in the inset, ink right edge at $($ink0.r)"

# Enter belongs to the control now -- it inserts a line break. Ctrl+Enter is what
# closes the edit.
Keys '^({ENTER})'
Start-Sleep -Milliseconds 700
Click $p[0] $p[1]              # disarm, so a press on the label selects it
# The band just below the box. The selection rings sit on the box's corners and
# edge midpoints and reach 5px past it, and the bottom midpoint moves when the box
# is narrowed, so the window stops short of where either midpoint can land. The
# assertion is a comparison rather than a zero: whatever the frozen desktop shows
# down there, narrowing must not add to it.
$bl0 = $box.left + 8; $bl1 = $box.left + 180
$g1 = Grab 'D:\Project\winshot\obj\tw_committed.png'
$below0 = RedCount $g1 $bl0 ($box.bottom + 2) $bl1 ($box.bottom + 6)
$g1.Dispose()
"committed label: $below0 red px in the band below the box"

# A label that is only selected wears no markers -- the whole box is one move
# handle then. The eight squares appear on the box when it is being edited, and
# that is the state its width is changed from.
DblClick ($ink0.l + 20) ($ink0.t + 5)
$midY = [int](($box.top + $box.bottom) / 2)
Drag $box.right $midY ($box.right - 250) $midY
# Narrowing re-wraps the text into more lines, and the box grows taller to keep
# them: one left at its old height would drop the new last line off the bottom, so
# a gesture meant only to re-wrap would delete the end of the text. The band that
# has to stay clean is therefore the one below where the box ends now, and the
# editor is still open to read that from.
$edN = Editor
if (-not $edN) { 'FAIL: the double click did not re-open the editor to narrow' ; exit 1 }
$boxN = Edit-Box $edN
Keys '^({ENTER})'                      # commit the narrowed label
Start-Sleep -Milliseconds 700
MoveTo 2300 1800; Start-Sleep -Milliseconds 300
$g2 = Grab 'D:\Project\winshot\obj\tw_narrowed.png'
$n1 = RedCount $g2 $il $it $ir $ib
$ink1 = Ink-Box $g2 $il $it $ir $ib
$below1 = RedCount $g2 $bl0 ($boxN.bottom + 2) $bl1 ($boxN.bottom + 6)
$g2.Dispose()
"after narrowing 250px: box now $($boxN.left),$($boxN.top) .. $($boxN.right),$($boxN.bottom), height $($box.bottom - $box.top) -> $($boxN.bottom - $boxN.top), $($ink1.n) red px in the inset, ink right edge at $($ink1.r), $below1 px below the new box"
if ($ink1.r -gt $ink0.r - 100) {
    $fail += "narrowing the box moved the text only from $($ink0.r) to $($ink1.r): it did not re-wrap"
}
if ($n1 -gt ($n0 - 300)) { $fail += "narrowing the box removed only $($n0 - $n1) red px of $n0" }
if ($boxN.bottom -le $box.bottom) {
    $fail += "narrowing the box left its bottom at $($boxN.bottom): the lines the narrower width asked for have nowhere to be drawn"
}
if ($ink1.r -gt $boxN.right - 4) {
    $fail += "the narrowed label drew ink out to $($ink1.r), past its own right edge at $($boxN.right)"
}
if ($below1 -gt $below0 + 20) {
    $fail += "the narrowed label drew $below1 px below its box at $($boxN.bottom) where the same band had ${below0}: rows that stopped fitting are still painted"
}

# --- and past the region's bottom it stops taking characters ------------------
# A fresh label, below the first so the two boxes do not overlap. Rounds of 440
# characters until the box can no longer grow: at about 50 characters a line and one
# line cell ($lh px) a line this needs on the order of 1000 of them to reach 1400.
Click $p[0] $p[1]              # re-arm the text tool
Click 950 900
$ed2 = Editor
if (-not $ed2) { 'FAIL: no editor for the bottom test'; exit 1 }
$prevBottom = 0
for ($round = 0; $round -lt 12; $round++) {
    Keys ('klmnopqrst ' * 40)
    Start-Sleep -Milliseconds 500
    $rb = Edit-Box $ed2
    if ($rb.bottom -le $prevBottom) { break }
    $prevBottom = $rb.bottom
}
# The box stops growing at the region's bottom, but the last round of 400 usually
# leaves a line or two of the box empty, because the box keeps the tallest it ever
# reached while a batch that did not fit is rolled back. So the next batch is not
# automatically the refused one: fill until the ink stops moving and only then ask
# whether more text is refused. The caret blinks, so the count gets a tolerance.
$inkA = 0; $inkPrev = -1; $r3 = $null; $stable = $false
for ($round = 0; $round -lt 6; $round++) {
    Keys ('uvwxyz ' * 40)
    Start-Sleep -Milliseconds 900
    $r3 = Edit-Box $ed2
    $gA = Grab ('D:\Project\winshot\obj\tw_at_bottom' + $round + '.png')
    # -4 and not -9 on the bottom: the last line's ink now ends 5px above the box,
    # so a deeper inset would stop counting the very line this loop is watching.
    $inkA = RedCount $gA ($r3.left + 8) ($r3.top + 8) ($r3.right - 9) ($r3.bottom - 4)
    $gA.Dispose()
    if ([Math]::Abs($inkA - $inkPrev) -le 60) { $stable = $true; break }
    $inkPrev = $inkA
}
Keys ('uvwxyz ' * 40)
Start-Sleep -Milliseconds 900
$r4 = Edit-Box $ed2
$gB = Grab 'D:\Project\winshot\obj\tw_past_bottom.png'
$inkB = RedCount $gB ($r4.left + 8) ($r4.top + 8) ($r4.right - 9) ($r4.bottom - 4)
$gB.Dispose()
# The limit is 1395, not 1400: the region's own frame owns the pixel just inside
# the selection and the label's red frame is stroked 3px outside the box, so
# CTextEditor::Limit works to a rect inset by both. The box grows a whole line cell
# at a time, so how far short of the limit its bottom lands is the remainder of the
# label's height against that cell and can be a full cell -- what must not happen is
# the box crossing the limit or stopping a cell short of it.
$floorBottom = 1395 - $lh + 1
"at the bottom: box bottom $($r3.bottom) (limit 1395, floor $floorBottom), $inkA red px; after 280 more: bottom $($r4.bottom), $inkB red px"
if ($r3.bottom -lt $floorBottom) {
    $fail += "the box stopped growing at bottom $($r3.bottom) instead of reaching the region's bottom limit at 1395, one line cell ($lh px) of slack"
}
if ($r4.bottom -gt 1397) { $fail += "the box ran past the region's bottom: bottom=$($r4.bottom), limit 1395" }
if (-not $stable) {
    $fail += "after 2400 more characters the box was still taking text at the region's bottom, so nothing refuses what no longer fits"
}
elseif ([Math]::Abs($inkB - $inkA) -gt 60) {
    $fail += "the box had stopped taking text at bottom $($r3.bottom) and $inkA red px, and 280 more characters still drew $inkB"
}

[void][System.Windows.Forms.SendKeys]::SendWait('{ESC}')
Start-Sleep -Milliseconds 400
if (-not $proc.HasExited) { $proc.Kill() }
if ($fail.Count) { "FAILURES: $($fail.Count)"; $fail | ForEach-Object { "  $_" }; exit 1 }
'PASS'
