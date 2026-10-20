# Two reports about typing in a text label, both of which looked right the moment
# the edit closed:
#
#   Backspacing deleted a character but left it on the screen.
#   Pressing Enter in the middle of a line broke the line while the first line kept
#   the glyphs it had and the second line showed two sets of glyphs on top of each
#   other.
#
# The glyphs while editing are drawn by the real EDIT control, over a frozen still of
# the screen it paints as its background. The control erases that background only when
# its window is resized, and the box only ever grows: a backspace cannot shrink it, and
# an Enter inside a box already tall enough for the new line cannot grow it. Both
# change the text with no resize at all, so the control repaints the lines it believes
# changed against a background it never cleared, and because that background is
# transparent the new glyphs land on top of the old ones.
#
# So every round here ends the same way: mutate, grab while the edit is still open,
# commit, grab again, and the two must agree. The committed label is drawn from the
# text alone, so anything the live grab shows beyond it is a glyph the control failed
# to erase.
#
# The comparison is per line, at the right edge, and not over the whole box. One
# deleted character is a hundred-odd pixels of stale ink, while the same text painted
# by the editing control (GDI) and by the committed label (GDI+) disagrees along every
# glyph edge -- the middle round measures that floor and it is larger than one
# character. What a stale glyph cannot hide is where the line ends: the live line
# reaches a whole character's advance past where the same text drawn once ends.
Add-Type -AssemblyName System.Drawing, System.Windows.Forms
Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class TER {
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

# How much further right the live line is allowed to reach than the same line drawn
# once. The characters here advance 11px, so a glyph left behind moves the end by that
# much, while edge-to-edge disagreement between the two paint engines is a pixel or two.
$SLACK = 6

# A band shorter than this is not a line of text. The glyphs of a line at this font
# cover 14 rows; the caret is a 1-2px bar as tall as a whole line cell, so when it
# lands past the last glyph it paints a handful of rows on their own.
$MIN_ROWS = 6

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
# error once Windows starts flagging the script's process as not responding. Round,
# and divide by 3839 rather than 3840: the pointer's 0..65535 range maps onto pixels
# 0..3839, so this is the exact inverse of what Windows does.
function MoveTo([int]$x, [int]$y) {
    [void][TER]::mouse_event(0x8001, [uint32][int][Math]::Round(65535 * $x / 3839),
                             [uint32][int][Math]::Round(65535 * $y / 2159), 0,
                             [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 90
}
function Down { [void][TER]::mouse_event($LEFTDOWN, 0, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 150 }
function Up { [void][TER]::mouse_event($LEFTUP, 0, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 350 }
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
    [void][TER]::mouse_event($LEFTDOWN, 0, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 60
    [void][TER]::mouse_event($LEFTUP, 0, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 60
    [void][TER]::mouse_event($LEFTDOWN, 0, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 60
    [void][TER]::mouse_event($LEFTUP, 0, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 450
}
# Not `Type`: that is the built-in alias for Get-Content, and an alias beats a
# function of the same name, so a function of that name is never called.
function Keys([string]$s) { [void][System.Windows.Forms.SendKeys]::SendWait($s) }
function Find-Wins([string]$title) {
    $found = New-Object System.Collections.ArrayList
    $cb = [TER+EnumProc] {
        param($h, $l)
        $t = New-Object System.Text.StringBuilder 256
        [void][TER]::GetWindowText($h, $t, 256)
        if ($t.ToString() -eq $title) { [void]$found.Add($h) }
        return $true
    }
    [void][TER]::EnumWindows($cb, [IntPtr]::Zero)
    return $found.ToArray()
}
function Find-Kids([IntPtr]$parent, [string]$title) {
    $found = New-Object System.Collections.ArrayList
    $cb = [TER+EnumProc] {
        param($h, $l)
        $t = New-Object System.Text.StringBuilder 256
        [void][TER]::GetWindowText($h, $t, 256)
        if ($t.ToString() -eq $title -and [TER]::IsWindowVisible($h)) { [void]$found.Add($h) }
        return $true
    }
    [void][TER]::EnumChildWindows($parent, $cb, [IntPtr]::Zero)
    return $found.ToArray()
}
function Rect-Of([IntPtr]$h) {
    $r = New-Object TER+RECT
    [void][TER]::GetWindowRect($h, [ref]$r)
    return $r
}
# The editor window is the input surface and stops 4px short of the label's box on
# every side, so the red frame and the eight square markers stay outside it and the
# overlay can paint them whole. Every measurement here is about the box.
function Edit-Box([IntPtr]$h) {
    $r = Rect-Of $h
    $r.left -= 4; $r.top -= 4; $r.right += 4; $r.bottom += 4
    return $r
}
$ov = $null
function Editor() {
    $e = @(Find-Kids $ov[0] 'WinShotTextEditor')
    if ($e.Count -eq 0) { return $null }
    return $e[0]
}
function Slot([int]$i) {
    $t = @(Find-Kids $ov[0] 'WinShotToolbar')
    if ($t.Count -eq 0) { return $null }
    $tr = Rect-Of $t[0]
    $s = ($tr.bottom - $tr.top) / 32.0
    $cell = [int][Math]::Round(27 * $s); $pad = [int][Math]::Round(4 * $s)
    return @(($tr.left + $pad + [int]($cell / 2) + $i * $cell),
             [int](($tr.top + $tr.bottom) / 2))
}
function IsInk($c) { return ($c.R -gt 190 -and $c.G -lt 120 -and $c.B -lt 130) }
# Rows that carry ink, grouped into bands: one text line is one band, and the line
# pitch leaves rows between them that no glyph reaches. Four px in from every edge of
# the box keeps the chrome out -- the eight markers straddle the edge and their
# outline, not their white core, is what passes IsInk, reaching 3px inside, and the
# frame is stroked 2px outside.
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
function Line-Bands($bmp, $box) {
    $all = Ink-Bands $bmp ($box.left + 4) ($box.top + 4) ($box.right - 5) ($box.bottom - 5)
    return ,@($all | Where-Object { ($_.b - $_.t + 1) -ge $MIN_ROWS })
}
# Pixels that are ink in one grab and not the other. Printed every round as context
# for the per-line comparison, which is what the assertions actually rest on.
function Diff-Ink($live, $done, $box) {
    $l = $box.left + 4; $t = $box.top + 4; $r = $box.right - 5; $b = $box.bottom - 5
    $onlyLive = 0; $onlyDone = 0; $both = 0
    for ($y = $t; $y -le $b; $y++) {
        for ($x = $l; $x -le $r; $x++) {
            $ia = IsInk ($live.GetPixel($x, $y))
            $ib = IsInk ($done.GetPixel($x, $y))
            if ($ia -and $ib) { $both++ } elseif ($ia) { $onlyLive++ } elseif ($ib) { $onlyDone++ }
        }
    }
    return @{ live = $onlyLive; done = $onlyDone; both = $both }
}
# The assertion every round makes: line i of the live grab must not reach further
# right than line i of the committed label, which knows where that line ends. A glyph
# the control failed to erase sits past the end. Returns both sets of bands so the
# caller can check the line count against what the text should hold.
function Compare-Lines([string]$what, $live, $done, $box) {
    $bl = Line-Bands $live $box
    $bc = Line-Bands $done $box
    # Write-Host and not the pipeline: this function returns a hashtable, and a bare
    # string here would land in front of it and the caller would get an array.
    $notes = @()
    Write-Host "$what live line(s) $($bl.Count), committed line(s) $($bc.Count)"
    foreach ($x in $bl) { Write-Host "  live y $($x.t)..$($x.b)  x $($x.l)..$($x.r)" }
    foreach ($x in $bc) { Write-Host "  done y $($x.t)..$($x.b)  x $($x.l)..$($x.r)" }
    if ($bl.Count -ne $bc.Count) {
        $notes += "$what the edit showed $($bl.Count) line(s) and the committed label $($bc.Count)"
    } else {
        for ($i = 0; $i -lt $bl.Count; $i++) {
            if ($bl[$i].r -gt $bc[$i].r + $SLACK) {
                $notes += "$what line $($i + 1) drew ink out to x $($bl[$i].r) while the committed label stops at $($bc[$i].r): glyphs left from before the edit"
            }
        }
    }
    return @{ live = $bl; done = $bc; notes = $notes }
}
$fail = @()
function Bail([string]$msg) {
    if ($proc -and -not $proc.HasExited) { $proc.Kill() }
    $all = @($msg) + $fail
    "FAILURES: $($all.Count)"
    $all | ForEach-Object { "  $_" }
    exit 1
}

MoveTo 3000 1900
Start-Sleep -Milliseconds 400
Get-Process winshot -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 600
$proc = Start-Process -FilePath 'D:\Project\winshot\x64\Debug\winshot.exe' -PassThru
Start-Sleep -Seconds 2

$sink = @(Find-Wins 'WinShotSink')
if ($sink.Count -eq 0) { 'FAIL: no sink window'; exit 1 }
[void][TER]::PostMessage($sink[0], 0x8002, [IntPtr]::Zero, [IntPtr]::Zero)
Start-Sleep -Seconds 2
$ov = @(Find-Wins 'WinShotOverlay')
if ($ov.Count -eq 0) { 'FAIL: no overlay window'; exit 1 }

# The region text_wrap uses: its right edge at 1600 is what makes 143 characters wrap
# into three lines instead of running off the screen as one.
Drag 800 600 1600 1400
$p = Slot 5
if (-not $p) { Bail 'no toolbar' }
Click $p[0] $p[1]              # the text tool
Click 950 690
$ed = Editor
if (-not $ed) { Bail 'clicking with the text tool opened no editor' }
Keys ('abcdefghij ' * 13)
Start-Sleep -Milliseconds 900
$box = Edit-Box $ed
$g = Grab 'D:\Project\winshot\obj\ter_start.png'
$bands = Line-Bands $g $box
$g.Dispose()
"label: box $($box.left),$($box.top) .. $($box.right),$($box.bottom), $($bands.Count) line(s)"
foreach ($x in $bands) { "  band y $($x.t)..$($x.b)  x $($x.l)..$($x.r)" }
if ($bands.Count -lt 3) { Bail "the label holds $($bands.Count) line(s); both reports were about a wrapped one" }
$line0 = $bands[0]

# --- 1: backspace at the end, which cannot resize the box ---------------------
# The caret opens at the end of the text, so this is the plain case from the report:
# one character gone, the box the same height it was, nothing to make the control
# erase what it has drawn.
Keys '{BACKSPACE}'
Start-Sleep -Milliseconds 700
MoveTo 2300 1800; Start-Sleep -Milliseconds 400
$gL = Grab 'D:\Project\winshot\obj\ter_bs_live.png'
$boxB = Edit-Box $ed
if (($boxB.bottom - $boxB.top) -ne ($box.bottom - $box.top)) {
    $gL.Dispose()
    Bail "the backspace resized the box from $($box.bottom - $box.top) to $($boxB.bottom - $boxB.top), so this is not the case the report describes"
}
Keys '^({ENTER})'
Start-Sleep -Milliseconds 700
$gC = Grab 'D:\Project\winshot\obj\ter_bs_done.png'
$r1 = Compare-Lines 'backspace:' $gL $gC $boxB
$d = Diff-Ink $gL $gC $boxB
$gL.Dispose(); $gC.Dispose()
"backspace: box still $($boxB.bottom - $boxB.top) px tall; live-only $($d.live) px, committed-only $($d.done) px, shared $($d.both)"
$fail += $r1.notes
if ($r1.done.Count -ne $bands.Count) {
    $fail += "backspace: the committed label has $($r1.done.Count) line(s) where it had $($bands.Count): one keystroke should not have removed a line"
}

# --- 2: a whole line at the end, which does resize the box --------------------
# The control. Adding a line grows the box, and a resize erases the whole client, so
# this path was correct before the fix too -- which makes its numbers the floor the
# other two are read against: the two paint engines and the caret, nothing else.
Click $p[0] $p[1]              # disarm, so the double click lands on the label
DblClick ([int](($boxB.left + $boxB.right) / 2)) ([int](($boxB.top + $boxB.bottom) / 2))
$ed2 = Editor
if (-not $ed2) { Bail 'double-clicking the label did not re-open it' }
$boxP = Edit-Box $ed2
Keys ('abcdefghij ' * 6)
Start-Sleep -Milliseconds 900
$box2 = Edit-Box $ed2
if (($box2.bottom - $box2.top) -le ($boxP.bottom - $boxP.top)) {
    Bail "typing a line left the box at $($box2.bottom - $box2.top) px, so this round is not the resize case"
}
MoveTo 2300 1800; Start-Sleep -Milliseconds 400
$gL = Grab 'D:\Project\winshot\obj\ter_ch_live.png'
Keys '^({ENTER})'
Start-Sleep -Milliseconds 700
$gC = Grab 'D:\Project\winshot\obj\ter_ch_done.png'
$r2 = Compare-Lines 'grew a line:' $gL $gC $box2
$d = Diff-Ink $gL $gC $box2
$gL.Dispose(); $gC.Dispose()
"grew a line: box height $($boxP.bottom - $boxP.top) -> $($box2.bottom - $box2.top); live-only $($d.live) px, committed-only $($d.done) px, shared $($d.both)"
$fail += $r2.notes

# --- 3: Enter in the middle of the first line --------------------------------
# The other report, and it needs a box already taller than its text: the break adds a
# line, and if the box has to grow for it the resize erases the client and the bug
# cannot show. So the label is pushed a line or two longer and then taken back below
# where it started -- the box keeps the height it reached -- and only then is the
# break inserted.
Click $p[0] $p[1]
DblClick ([int](($box2.left + $box2.right) / 2)) ([int](($box2.top + $box2.bottom) / 2))
$ed3 = Editor
if (-not $ed3) { Bail 'double-clicking the label did not re-open it for the Enter test' }
Keys ('abcdefghij ' * 8)
Start-Sleep -Milliseconds 900
$boxTall = Edit-Box $ed3
$gT = Grab 'D:\Project\winshot\obj\ter_tall.png'
$bandsTall = Line-Bands $gT $boxTall
$gT.Dispose()
Keys ('{BACKSPACE}' * 110)
Start-Sleep -Milliseconds 1200
$box3 = Edit-Box $ed3
if (($box3.bottom - $box3.top) -ne ($boxTall.bottom - $boxTall.top)) {
    Bail "deleting the text shrank the box to $($box3.bottom - $box3.top) px from $($boxTall.bottom - $boxTall.top), so the box no longer has slack for a new line"
}
$gS = Grab 'D:\Project\winshot\obj\ter_short.png'
$bands3 = Line-Bands $gS $box3
$gS.Dispose()
"grown to $($bandsTall.Count) line(s) in a $($boxTall.bottom - $boxTall.top) px box, then back to $($bands3.Count) line(s) in the same $($box3.bottom - $box3.top) px box"
if ($bands3.Count -ge $bandsTall.Count) {
    Bail "deleting 110 characters left $($bands3.Count) line(s) where the box holds $($bandsTall.Count), so the Enter below would still have to grow the box"
}
# Into the first line, a few characters in: the caret goes where the press lands.
Click ($line0.l + 60) ($line0.t + 8)
Start-Sleep -Milliseconds 300
Keys '{ENTER}'
Start-Sleep -Milliseconds 800
$box3b = Edit-Box $ed3
if (($box3b.bottom - $box3b.top) -ne ($box3.bottom - $box3.top)) {
    Bail "the Enter grew the box from $($box3.bottom - $box3.top) to $($box3b.bottom - $box3b.top), so it resized and this is not the case the report describes"
}
MoveTo 2300 1800; Start-Sleep -Milliseconds 400
$gL = Grab 'D:\Project\winshot\obj\ter_enter_live.png'
Keys '^({ENTER})'
Start-Sleep -Milliseconds 700
$gC = Grab 'D:\Project\winshot\obj\ter_enter_done.png'
$r3 = Compare-Lines 'enter mid-line:' $gL $gC $box3b
$d = Diff-Ink $gL $gC $box3b
$gL.Dispose(); $gC.Dispose()
"enter mid-line: box still $($box3b.bottom - $box3b.top) px tall; live-only $($d.live) px, committed-only $($d.done) px, shared $($d.both)"
$fail += $r3.notes
if ($r3.done.Count -ne $bands3.Count + 1) {
    $fail += "enter mid-line: the committed label has $($r3.done.Count) line(s) where the text before the break had $($bands3.Count): the break did not take effect"
}

[void][System.Windows.Forms.SendKeys]::SendWait('{ESC}')
Start-Sleep -Milliseconds 400
if ($proc -and -not $proc.HasExited) { $proc.Kill() }
if ($fail.Count) { "FAILURES: $($fail.Count)"; $fail | ForEach-Object { "  $_" }; exit 1 }
'PASS'
