# Narrowing a text box used to break a line far too early: the label drew its ink
# flush at the box's left edge while wrapping at box.Width - 2*PadX, so both
# paddings ended up on the right, and the width was measured with GDI+
# MeasureString, which over-measures this face by about 0.4em. Measured at the
# time, a line broke with close to two characters still open on the right.
#
# The request is one line: a line breaks when the right gap would fall below the
# left inset. So the test measures the ink first and then narrows the box to
# exactly what the ink plus the two insets needs, which is the width the new rule
# says still fits:
#
#   A  the text on one line in the box it grew to - the ink's own width, and the
#      left inset, which is the other half of the fix.
#   B  the box dragged to ink + 2*PadX + 3 - still one line, with the right gap
#      at about PadX. The old rule broke this one: its limit was about 15px
#      narrower than the ink.
#   C  the box dragged one glyph narrower again - two lines, and the gap left on
#      the first line under one glyph wide. The old rule left roughly a glyph and
#      a half there, which is the "接近2个字符" of the report.
#
# Everything is measured off the ink rather than assumed from font metrics: the
# ink's left edge is where the label actually puts PadX, and its width is what the
# wrap has to hold room for. The box comes from the input control's own window,
# which is the label's box exactly, and is read while the edit is open, before the
# commit paints over it. A committed label carries no chrome at all, so the ink
# inside the box is the only red out there.
Add-Type -AssemblyName System.Drawing, System.Windows.Forms
Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class TWF {
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
$PADX = 4        # annot::kTextPadX at 100% scaling
$GLYPH = 16      # an upper-case W at 18px, generously

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
#
# Round, and divide by 3839 rather than 3840: the pointer's 0..65535 range maps
# onto pixels 0..3839, so this is the exact inverse of what Windows does. Flooring
# by 3840 lands every coordinate one pixel low, and here that is the difference
# between a press on the box's right marker and a press one pixel inside the input
# control, which swallows it instead of starting the drag.
function MoveTo([int]$x, [int]$y) {
    [void][TWF]::mouse_event(0x8001, [uint32][int][Math]::Round(65535 * $x / 3839),
                             [uint32][int][Math]::Round(65535 * $y / 2159), 0,
                             [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 90
}
function Down { [void][TWF]::mouse_event($LEFTDOWN, 0, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 150 }
function Up { [void][TWF]::mouse_event($LEFTUP, 0, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 350 }
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
    [void][TWF]::mouse_event($LEFTDOWN, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 60
    [void][TWF]::mouse_event($LEFTUP, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 60
    [void][TWF]::mouse_event($LEFTDOWN, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 60
    [void][TWF]::mouse_event($LEFTUP, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 450
}
# Not `Type`: that is the built-in alias for Get-Content, and an alias beats a
# function, so a function of that name is never called.
function Keys([string]$s) { [void][System.Windows.Forms.SendKeys]::SendWait($s) }
function Find-Wins([string]$title) {
    $found = New-Object System.Collections.ArrayList
    $cb = [TWF+EnumProc] {
        param($h, $l)
        $t = New-Object System.Text.StringBuilder 256
        [void][TWF]::GetWindowText($h, $t, 256)
        if ($t.ToString() -eq $title) { [void]$found.Add($h) }
        return $true
    }
    [void][TWF]::EnumWindows($cb, [IntPtr]::Zero)
    return $found.ToArray()
}
function Find-Kids([IntPtr]$parent, [string]$title) {
    $found = New-Object System.Collections.ArrayList
    $cb = [TWF+EnumProc] {
        param($h, $l)
        $t = New-Object System.Text.StringBuilder 256
        [void][TWF]::GetWindowText($h, $t, 256)
        if ($t.ToString() -eq $title -and [TWF]::IsWindowVisible($h)) { [void]$found.Add($h) }
        return $true
    }
    [void][TWF]::EnumChildWindows($parent, $cb, [IntPtr]::Zero)
    return $found.ToArray()
}
function Rect-Of([IntPtr]$h) {
    $r = New-Object TWF+RECT
    [void][TWF]::GetWindowRect($h, [ref]$r)
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
function Editor() {
    $e = @(Find-Kids $ov[0] 'WinShotTextEditor')
    if ($e.Count -eq 0) { return $null }
    return $e[0]
}
function IsInk($c) { return ($c.R -gt 190 -and $c.G -lt 120 -and $c.B -lt 130) }
# Rows that carry ink, grouped into bands: one committed text line is one band,
# and the line pitch leaves rows between them that no glyph reaches.
function Ink-Bands($bmp, [int]$l, [int]$t, [int]$r, [int]$b) {
    $bands = @()
    $t0 = -1; $l0 = 0; $r0 = 0
    for ($y = $t; $y -le $b; $y++) {
        $rowL = -1; $rowR = -1
        for ($x = $l; $x -le $r; $x++) {
            if (IsInk ($bmp.GetPixel($x, $y))) { if ($rowL -lt 0) { $rowL = $x }; $rowR = $x }
        }
        if ($rowL -ge 0) {
            if ($t0 -lt 0) { $t0 = $y; $l0 = $rowL; $r0 = $rowR }
            else { if ($rowL -lt $l0) { $l0 = $rowL }; if ($rowR -gt $r0) { $r0 = $rowR } }
        } elseif ($t0 -ge 0) {
            $bands += @{ t = $t0; b = $y - 1; l = $l0; r = $r0 }
            $t0 = -1
        }
    }
    if ($t0 -ge 0) { $bands += @{ t = $t0; b = $b; l = $l0; r = $r0 } }
    # The comma keeps this an array: a bare `return $bands` of one band hands back
    # the hashtable itself, whose Count is its four keys and reads as four lines.
    return ,$bands
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

$fail = @()

MoveTo 3000 1900
Start-Sleep -Milliseconds 400
Get-Process winshot -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 600
$proc = Start-Process -FilePath 'D:\Project\winshot\x64\Debug\winshot.exe' -PassThru
Start-Sleep -Seconds 2

$sink = @(Find-Wins 'WinShotSink')
if ($sink.Count -eq 0) { 'FAIL: no sink window'; exit 1 }
[void][TWF]::PostMessage($sink[0], 0x8002, [IntPtr]::Zero, [IntPtr]::Zero)
Start-Sleep -Seconds 2
$ov = @(Find-Wins 'WinShotOverlay')
if ($ov.Count -eq 0) { 'FAIL: no overlay window'; exit 1 }

Drag 700 500 2200 1500
$p = Slot 5
if (-not $p) { 'FAIL: no toolbar'; exit 1 }
Click $p[0] $p[1]              # the text tool
Click 900 700
$ed = Editor
if (-not $ed) { 'FAIL: clicking with the text tool opened no editor'; exit 1 }
# One glyph repeated: every character the same width, no spaces for the wrap to
# prefer, so where a line breaks follows from the width alone.
Keys ('W' * 16)
Start-Sleep -Milliseconds 900
$box1 = Edit-Box $ed
# Plain Enter belongs to the control and inserts a newline; Ctrl+Enter is the
# commit.
Keys '^({ENTER})'
Start-Sleep -Milliseconds 700
Click $p[0] $p[1]              # disarm

# --- A: the text as first committed -------------------------------------------
MoveTo 2300 1800; Start-Sleep -Milliseconds 400
$gA = Grab 'D:\Project\winshot\obj\twf_one.png'
$bandsA = Ink-Bands $gA ($box1.left + 2) ($box1.top + 2) ($box1.right - 3) ($box1.bottom - 3)
$gA.Dispose()
"box A: $($box1.left),$($box1.top) .. $($box1.right),$($box1.bottom)"
foreach ($x in $bandsA) { "  band y $($x.t)..$($x.b)  x $($x.l)..$($x.r)" }
if ($bandsA.Count -ne 1) {
    "FAIL: the freshly typed label drew $($bandsA.Count) lines in its own box, want 1"
    exit 1
}
$a = $bandsA[0]
$inkW = $a.r - $a.l + 1
"ink A: one line, x $($a.l)..$($a.r) ($inkW px), y $($a.t)..$($a.b)"
# The layout inset is PadX; the first glyph's own side bearing adds a pixel on top
# of that, which is why this is not an exact match.
if ([Math]::Abs(($a.l - $box1.left) - $PADX) -gt 1) {
    $fail += "the ink starts at $(($a.l - $box1.left)) px inside the box's left edge, want about ${PADX}: the left inset is missing"
}
$gapA = $box1.right - $a.r
"gap A: $($gapA) px from the last glyph to the right border (the box grew to fit, so this is padding plus the editor's slack)"

# --- B: narrowed to the ink plus the two insets -------------------------------
# The width the new rule says still holds the line: ink + PadX on each side, plus
# 3 for the difference between the advance the wrap measures and the ink that
# scan sees. The old rule's limit was about 15px narrower than this.
$wB = $inkW + 2 * $PADX + 3
DblClick ([int](($a.l + $a.r) / 2)) ([int](($a.t + $a.b) / 2))
$ed2 = Editor
if (-not $ed2) { 'FAIL: double-clicking the label did not re-open it'; exit 1 }
$boxR = Edit-Box $ed2
if ([Math]::Abs($boxR.right - $box1.right) -gt 2 -or [Math]::Abs($boxR.left - $box1.left) -gt 2) {
    "FAIL: re-opening the label moved its box from $($box1.left)..$($box1.right) to $($boxR.left)..$($boxR.right)"
    exit 1
}
# Handle 3 is the marker at the right edge's middle; pressing on it while the edit
# is open resizes the box being typed into rather than committing it. Two pixels
# out from the edge, because the input control ends at the edge and a press that
# lands inside it never reaches the marker.
$my = [int](($boxR.top + $boxR.bottom) / 2)
Drag ($boxR.right + 2) $my ($boxR.left + $wB) $my
Start-Sleep -Milliseconds 500
$ed2b = Editor
if (-not $ed2b) { "FAIL: dragging the box's right marker closed the edit"; exit 1 }
$box2 = Edit-Box $ed2b
"box B: $($box2.left),$($box2.top) .. $($box2.right),$($box2.bottom) (dragged to width $wB)"
if ([Math]::Abs(($box2.right - $box2.left) - $wB) -gt 2) {
    "FAIL: the drag left the box $(($box2.right - $box2.left)) px wide, want $wB"
    exit 1
}
Keys '^({ENTER})'
Start-Sleep -Milliseconds 700
Click $p[0] $p[1]
MoveTo 2300 1800; Start-Sleep -Milliseconds 400
$gB = Grab 'D:\Project\winshot\obj\twf_fit.png'
$bandsB = Ink-Bands $gB ($box2.left + 2) ($box2.top + 2) ($box2.right - 3) ($box2.bottom - 3)
$gB.Dispose()
if ($bandsB.Count -eq 0) {
    "FAIL: the narrowed label drew no ink at all in its own box"
    exit 1
}
$bB = $bandsB[0]
$gapB = $box2.right - $bB.r
"ink B: $($bandsB.Count) line(s), x $($bB.l)..$($bB.r), gap to the right border $($gapB) px (want 1 line, gap about ${PADX})"
if ($bandsB.Count -ne 1) {
    $fail += "a box only $(($bB.r - $bB.l + 1)) px of ink plus ${PADX} px on each side wide broke into $($bandsB.Count) lines: the line wraps while the right border is still over a character away"
} elseif ($gapB -lt $PADX -or $gapB -gt $PADX + 6) {
    $fail += "at that width the last glyph sits $($gapB) px from the right border, want about ${PADX}"
}

# --- C: one glyph narrower again ---------------------------------------------
$wC = $wB - $GLYPH
DblClick ([int](($bB.l + $bB.r) / 2)) ([int](($bB.t + $bB.b) / 2))
$ed3 = Editor
if (-not $ed3) { 'FAIL: double-clicking the narrowed label did not re-open it'; exit 1 }
$boxS = Edit-Box $ed3
$my2 = [int](($boxS.top + $boxS.bottom) / 2)
Drag ($boxS.right + 2) $my2 ($boxS.left + $wC) $my2
Start-Sleep -Milliseconds 500
$ed3b = Editor
if (-not $ed3b) { 'FAIL: the second drag closed the edit'; exit 1 }
$box3 = Edit-Box $ed3b
"box C: $($box3.left),$($box3.top) .. $($box3.right),$($box3.bottom) (dragged to width $wC)"
Keys '^({ENTER})'
Start-Sleep -Milliseconds 700
Click $p[0] $p[1]
MoveTo 2300 1800; Start-Sleep -Milliseconds 400
$gC = Grab 'D:\Project\winshot\obj\twf_wrap.png'
$bandsC = Ink-Bands $gC ($box3.left + 2) ($box3.top + 2) ($box3.right - 3) ($box3.bottom - 3)
$gC.Dispose()
if ($bandsC.Count -lt 2) {
    $fail += "narrowing the box by $GLYPH px did not break the line: still $($bandsC.Count) line(s)"
} else {
    $c1 = $bandsC[0]
    $gapC = $box3.right - $c1.r
    "ink C: $($bandsC.Count) lines; first line x $($c1.l)..$($c1.r), gap to the right border $($gapC) px (want ${PADX} to under $GLYPH)"
    if ($gapC -lt $PADX) {
        $fail += "the first line's last glyph is $($gapC) px from the right border, under the ${PADX} px left inset: it wrapped too late and the glyph is being clipped"
    }
    if ($gapC -ge $PADX + $GLYPH) {
        $fail += "the first line's last glyph is $($gapC) px from the right border, a whole glyph short of the wrap: it should have broken $GLYPH px earlier"
    }
}

Keys '{ESC}'
Start-Sleep -Milliseconds 400
if (-not $proc.HasExited) { $proc.Kill() }
if ($fail.Count) { "FAILURES: $($fail.Count)"; $fail | ForEach-Object { "  $_" }; exit 1 }
'PASS'
