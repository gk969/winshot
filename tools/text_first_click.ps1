# Typing into a text label leaves the caret at the end of the text, which is what the
# user asked for when an edit opens. It also stayed there after the first click:
#
#   Clicking in the middle of a line sent the caret to the click and then straight
#   back to the end. Clicking the same place again worked. Every label, but only the
#   first click of each edit.
#
# The control is armed against the up of whatever opened the edit, because re-editing
# by double click releases the capture before the control exists, and that up would
# otherwise drop the caret on the double-click point instead of the end of the text.
# The arming used to be spent on the up, so the first click the user aimed was the one
# swallowed -- in this path the gesture that opened the edit was a press on bare
# canvas with the text tool, and the overlay answered that up itself.
#
# The fix spends the arming on the down instead: a click the user aims arrives as a
# down and an up, while the opening up arrives alone. So the double click's up is
# still absorbed -- round 3 below, the behaviour that must not regress -- while the
# first click into an edit that is already open lands where it was aimed -- rounds 1,
# 2 and 4.
#
# The caret comes from GetGUIThreadInfo in screen coords, as in text_edit_box.ps1:
# the control belongs to another process and cross-process EM_GETSEL returns
# self-contradictory answers. The bounce is synchronous -- the down positions the
# caret and the up moves it back -- so what is read here is what the user sees settle.
Add-Type -AssemblyName System.Drawing, System.Windows.Forms
Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class TFC {
    public delegate bool EnumProc(IntPtr h, IntPtr l);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
    [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr p, EnumProc cb, IntPtr l);
    [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint msg, IntPtr w, IntPtr l);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint dx, uint dy, uint d, UIntPtr e);
    [DllImport("user32.dll")] public static extern int GetWindowThreadProcessId(IntPtr h, out int pid);
    [DllImport("user32.dll")] public static extern bool GetGUIThreadInfo(int tid, ref GUITHREADINFO gi);
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int left, top, right, bottom; }
    [StructLayout(LayoutKind.Sequential)] public struct GUITHREADINFO {
        public int cbSize; public int flags;
        public IntPtr hwndActive; public IntPtr hwndFocus; public IntPtr hwndCapture;
        public IntPtr hwndMenuOwner; public IntPtr hwndMoveSize; public IntPtr hwndCaret;
        public RECT rcCaret;
    }
}
"@

$LEFTDOWN = 0x0002; $LEFTUP = 0x0004

# How far the caret may sit from the x that was clicked. The characters here advance
# 11 px, so the caret can land half an advance either side of the press plus a pixel
# for the difference between a glyph's ink edge and the caret position before it. A
# caret left at the end of the text is a hundred-odd px away.
$XSLACK = 16

# A band shorter than this is not a line of text: the caret is a 1-2 px bar as tall as
# a whole line cell and paints a handful of rows on its own once it sits past the last
# glyph.
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
    [void][TFC]::mouse_event(0x8001, [uint32][int][Math]::Round(65535 * $x / 3839),
                             [uint32][int][Math]::Round(65535 * $y / 2159), 0,
                             [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 90
}
function Down { [void][TFC]::mouse_event($LEFTDOWN, 0, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 150 }
function Up { [void][TFC]::mouse_event($LEFTUP, 0, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 350 }
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
    [void][TFC]::mouse_event($LEFTDOWN, 0, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 60
    [void][TFC]::mouse_event($LEFTUP, 0, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 60
    [void][TFC]::mouse_event($LEFTDOWN, 0, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 60
    [void][TFC]::mouse_event($LEFTUP, 0, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 450
}
# Not `Type`: that is the built-in alias for Get-Content, and an alias beats a
# function of the same name, so a function of that name is never called.
function Keys([string]$s) { [void][System.Windows.Forms.SendKeys]::SendWait($s) }
function Find-Wins([string]$title) {
    $found = New-Object System.Collections.ArrayList
    $cb = [TFC+EnumProc] {
        param($h, $l)
        $t = New-Object System.Text.StringBuilder 256
        [void][TFC]::GetWindowText($h, $t, 256)
        if ($t.ToString() -eq $title) { [void]$found.Add($h) }
        return $true
    }
    [void][TFC]::EnumWindows($cb, [IntPtr]::Zero)
    return $found.ToArray()
}
function Find-Kids([IntPtr]$parent, [string]$title) {
    $found = New-Object System.Collections.ArrayList
    $cb = [TFC+EnumProc] {
        param($h, $l)
        $t = New-Object System.Text.StringBuilder 256
        [void][TFC]::GetWindowText($h, $t, 256)
        if ($t.ToString() -eq $title -and [TFC]::IsWindowVisible($h)) { [void]$found.Add($h) }
        return $true
    }
    [void][TFC]::EnumChildWindows($parent, $cb, [IntPtr]::Zero)
    return $found.ToArray()
}
function Rect-Of([IntPtr]$h) {
    $r = New-Object TFC+RECT
    [void][TFC]::GetWindowRect($h, [ref]$r)
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
# The caret in screen coords. GetGUIThreadInfo wants the THREAD id, which is the return
# value of GetWindowThreadProcessId rather than its out parameter. $edHost has to be
# re-taken after every open: committing destroys that window and the next edit gets a
# fresh handle, and GetWindowRect on a destroyed one returns a zeroed RECT without
# failing.
$edHost = [IntPtr]::Zero
function Caret() {
    $pid2 = 0
    $tid = [TFC]::GetWindowThreadProcessId($edHost, [ref]$pid2)
    for ($try = 0; $try -lt 10; $try++) {
        $gi = New-Object TFC+GUITHREADINFO
        $gi.cbSize = [System.Runtime.InteropServices.Marshal]::SizeOf([type][TFC+GUITHREADINFO])
        if ([TFC]::GetGUIThreadInfo($tid, [ref]$gi) -and
            $gi.hwndCaret -ne [IntPtr]::Zero) {
            $c = $gi.rcCaret
            if ($c.right -gt $c.left -or $c.bottom -gt $c.top) {
                $fr = Rect-Of $gi.hwndFocus
                return @{ x = $fr.left + $c.left; y = $fr.top + $c.top;
                          h = [Math]::Max($c.bottom - $c.top, 1) }
            }
        }
        Start-Sleep -Milliseconds 150
    }
    return $null
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
    # The comma keeps this an array: a bare `return $bands` of one band hands back the
    # hashtable itself, whose Count is its four keys and reads as four lines.
    return ,$bands
}
function Line-Bands($bmp, $box) {
    $all = Ink-Bands $bmp ($box.left + 4) ($box.top + 4) ($box.right - 5) ($box.bottom - 5)
    return ,@($all | Where-Object { ($_.b - $_.t + 1) -ge $MIN_ROWS })
}
# One assertion, used three times: the caret has to be on the rows of $want and within
# $XSLACK of $x, which is where the press landed. A caret left at the end of the text
# fails both -- the row test because the text here wraps into more than one line, the
# x test even for a single line.
function Caret-At([string]$what, $c, $want, [int]$x) {
    if (-not $c) { return @("$what could not read the caret from the editing thread") }
    Write-Host "$what clicked x $x on rows $($want.t)..$($want.b); caret at $($c.x),$($c.y) (h $($c.h))"
    $notes = @()
    if ($c.y -gt $want.b -or ($c.y + $c.h) -lt $want.t) {
        $notes += "$what the caret is on rows $($c.y)..$($c.y + $c.h), off the clicked line at $($want.t)..$($want.b): it went back to the end of the text"
    }
    if ([Math]::Abs($c.x - $x) -gt $XSLACK) {
        $notes += "$what the caret is at x $($c.x), more than $XSLACK px from the clicked x ${x}: it went back to the end of the text"
    }
    return ,$notes
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
[void][TFC]::PostMessage($sink[0], 0x8002, [IntPtr]::Zero, [IntPtr]::Zero)
Start-Sleep -Seconds 2
$ov = @(Find-Wins 'WinShotOverlay')
if ($ov.Count -eq 0) { 'FAIL: no overlay window'; exit 1 }

# The region text_edit_repaint uses: its right edge at 1600 is what makes the text
# wrap into more than one line, which is what makes the row test below able to tell a
# caret left at the end from one left at the click.
Drag 800 600 1600 1400
$p = Slot 5
if (-not $p) { Bail 'no toolbar' }
Click $p[0] $p[1]              # the text tool
Click 950 690
$ed = Editor
if (-not $ed) { Bail 'clicking with the text tool opened no editor' }
$edHost = $ed
Keys ('abcdefghij ' * 13)
Start-Sleep -Milliseconds 900
$box = Edit-Box $ed
$g = Grab 'D:\Project\winshot\obj\tfc_start.png'
$bands = Line-Bands $g $box
$g.Dispose()
"label: box $($box.left),$($box.top) .. $($box.right),$($box.bottom), $($bands.Count) line(s)"
foreach ($x in $bands) { "  band y $($x.t)..$($x.b)  x $($x.l)..$($x.r)" }
if ($bands.Count -lt 2) { Bail "the label holds $($bands.Count) line(s); the report is about clicking a line that is not the last" }

# --- 0: the caret sits at the end of what was typed ------------------------------
# Not the report, but the starting condition the report describes, and the one the
# fix has to leave alone.
$c = Caret
if (-not $c) {
    $fail += 'could not read the caret from the editing thread'
} else {
    $last = $bands[$bands.Count - 1]
    "caret after typing at $($c.x),$($c.y) (h $($c.h)); last line ink x $($last.l)..$($last.r) y $($last.t)..$($last.b)"
    if ($c.y -gt $last.b -or ($c.y + $c.h) -lt $last.t) {
        $fail += "typing left the caret on rows $($c.y)..$($c.y + $c.h) instead of the last line at $($last.t)..$($last.b)"
    }
    if ([Math]::Abs($c.x - ($last.r + 1)) -gt 10) {
        $fail += "typing left the caret at x $($c.x), want within 10 px of the last glyph's right edge at $($last.r + 1)"
    }
}

# --- 1: the first click into an open edit lands where it was aimed ---------------
# This is the report. The edit was opened by a press on bare canvas, whose up the
# overlay answered, so the arming was still live and used to be spent here.
$mid = @([int](($bands[0].l + $bands[0].r) / 2), [int](($bands[0].t + $bands[0].b) / 2))
Click $mid[0] $mid[1]
Start-Sleep -Milliseconds 500
$fail += Caret-At 'first click:' (Caret) $bands[0] $mid[0]

# --- 2: and the caret keeps following the click ----------------------------------
# A different line this time, so a caret that merely failed to move would fail here
# too. The report says the second click worked; this is that click and one more.
$mid2 = @([int]($bands[1].l + 40), [int](($bands[1].t + $bands[1].b) / 2))
Click $mid2[0] $mid2[1]
Start-Sleep -Milliseconds 500
$fail += Caret-At 'second click:' (Caret) $bands[1] $mid2[0]

# --- 3: re-opening by double click still puts the caret at the end ---------------
# The behaviour the arming exists for, and the reason it could not simply be deleted:
# the double click releases the capture before the control exists, so the up of its
# second press is the control's to answer, and unabsorbed it lands the caret on the
# double-click point. text_edit_box.ps1 step 6 pins the same thing from the other
# direction; it is here because this fix moves where the arming is spent.
$boxA = Edit-Box $ed
Keys '^({ENTER})'
Start-Sleep -Milliseconds 700
$g = Grab 'D:\Project\winshot\obj\tfc_committed.png'
$cb = Line-Bands $g $boxA
$g.Dispose()
"committed label: $($cb.Count) line(s)"
foreach ($x in $cb) { "  band y $($x.t)..$($x.b)  x $($x.l)..$($x.r)" }
if ($cb.Count -lt 2) { Bail "committing left $($cb.Count) line(s); the re-open below needs a wrapped label" }
Click $p[0] $p[1]              # disarm, so the double click lands on the label
DblClick ([int](($cb[0].l + $cb[0].r) / 2)) ([int](($cb[0].t + $cb[0].b) / 2))
$ed2 = Editor
if (-not $ed2) { Bail 'double-clicking the label did not re-open it' }
$edHost = $ed2
Start-Sleep -Milliseconds 400
$g = Grab 'D:\Project\winshot\obj\tfc_reopen.png'
$rb = Line-Bands $g (Edit-Box $ed2)
$g.Dispose()
if ($rb.Count -lt 2) { Bail "re-opening showed $($rb.Count) line(s); the wrap did not survive the edit" }
$lastR = $rb[$rb.Count - 1]
$firstR = $rb[0]
$c = Caret
if (-not $c) {
    $fail += 'could not read the caret after re-opening by double click'
} else {
    "caret after re-open at $($c.x),$($c.y) (h $($c.h)); last line ink x $($firstR.l)..$($lastR.r) y $($lastR.t)..$($lastR.b)"
    if ([Math]::Abs($c.x - ($lastR.r + 1)) -gt 10) {
        $fail += "re-opening put the caret at x $($c.x), want within 10 px of the last glyph's right edge at $($lastR.r + 1): the double click's up is no longer absorbed"
    }
    if ($c.y -gt $lastR.b -or ($c.y + $c.h) -lt $lastR.t) {
        $fail += "re-opening put the caret on rows $($c.y)..$($c.y + $c.h), outside the last line at $($lastR.t)..$($lastR.b)"
    }
    if ($c.y + $c.h -gt $firstR.t -and $c.y -le $firstR.b) {
        $fail += 're-opening put the caret on the first line, which is where the double click landed'
    }
}

# --- 4: the first click after a re-open lands where it was aimed too -------------
# The arming is spent by the double click's up, so this click is an ordinary one --
# and it is the same first-click-of-an-edit the report is about, reached by the other
# opening path.
$mid3 = @([int](($rb[0].l + $rb[0].r) / 2), [int](($rb[0].t + $rb[0].b) / 2))
Click $mid3[0] $mid3[1]
Start-Sleep -Milliseconds 500
$fail += Caret-At 'first click after re-open:' (Caret) $rb[0] $mid3[0]

[void][System.Windows.Forms.SendKeys]::SendWait('{ESC}')
Start-Sleep -Milliseconds 400
if ($proc -and -not $proc.HasExited) { $proc.Kill() }
if ($fail.Count) { "FAILURES: $($fail.Count)"; $fail | ForEach-Object { "  $_" }; exit 1 }
'PASS'
