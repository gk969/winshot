# Re-editing a text label used to open a second box over it. The label kept the
# width the user had dragged and the lines that width had forced, while the editor
# window sized itself from the text on one line, so the wrap vanished the moment
# the edit opened and the two boxes drew over each other - which is what
# 出错截图/文本框双击编辑，没有维持自定义文本框宽高.png shows, and what the report
# calls 重影. The caret also landed at the start of the text.
#
# There is one box now: the label's own. The input control lives inside it and
# draws nothing of its own, so all four behaviours below are properties of that
# one rect and its three states.
#
#   unselected  no frame, no markers
#   selected    the red frame, no square markers, the whole box moves
#   editing     the red frame and the eight square markers
#
# The frame is stroked 1px at box inflated by 2, so it lands on column left-2 and
# row top-2; the markers are white-cored squares straddling the box edge. Both are
# read off the screen rather than from the window, because the frame is the
# overlay's and the markers are the selection chrome's, and neither has a window
# of its own.
#
# The caret comes from GetGUIThreadInfo, which reports the caret's rect in the
# focus window's client coords - the documented cross-process way, and the only
# one that works here: the control is another process's, and cross-process
# EM_GETLINECOUNT and friends return self-contradictory answers.
Add-Type -AssemblyName System.Drawing, System.Windows.Forms
Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class TEB {
    public delegate bool EnumProc(IntPtr h, IntPtr l);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
    [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr p, EnumProc cb, IntPtr l);
    [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint msg, IntPtr w, IntPtr l);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint dx, uint dy, uint d, UIntPtr e);
    [DllImport("user32.dll")] public static extern bool GetCursorInfo(out CURSORINFO ci);
    [DllImport("user32.dll", CharSet=CharSet.Unicode, EntryPoint="LoadCursorW")]
    public static extern IntPtr LoadCursorRes(IntPtr h, ushort id);
    [DllImport("user32.dll")] public static extern int GetWindowThreadProcessId(IntPtr h, out int pid);
    [DllImport("user32.dll")] public static extern bool GetGUIThreadInfo(int tid, ref GUITHREADINFO gi);
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int left, top, right, bottom; }
    [StructLayout(LayoutKind.Sequential)] public struct PT { public int x, y; }
    [StructLayout(LayoutKind.Sequential)] public struct CURSORINFO {
        public int cbSize; public int flags; public IntPtr hCursor; public PT pt;
    }
    [StructLayout(LayoutKind.Sequential)] public struct GUITHREADINFO {
        public int cbSize; public int flags;
        public IntPtr hwndActive; public IntPtr hwndFocus; public IntPtr hwndCapture;
        public IntPtr hwndMenuOwner; public IntPtr hwndMoveSize; public IntPtr hwndCaret;
        public RECT rcCaret;
    }
}
"@

$LEFTDOWN = 0x0002; $LEFTUP = 0x0004
$PADX = 4        # annot::kTextPadX at 100% scaling

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
# by 3840 lands every coordinate one pixel low, and a press meant for the marker
# on the box's right edge would land inside the input control instead, which
# swallows it and never starts the drag.
function MoveTo([int]$x, [int]$y) {
    [void][TEB]::mouse_event(0x8001, [uint32][int][Math]::Round(65535 * $x / 3839),
                             [uint32][int][Math]::Round(65535 * $y / 2159), 0,
                             [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 90
}
function Down { [void][TEB]::mouse_event($LEFTDOWN, 0, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 150 }
function Up { [void][TEB]::mouse_event($LEFTUP, 0, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 350 }
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
    [void][TEB]::mouse_event($LEFTDOWN, 0, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 60
    [void][TEB]::mouse_event($LEFTUP, 0, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 60
    [void][TEB]::mouse_event($LEFTDOWN, 0, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 60
    [void][TEB]::mouse_event($LEFTUP, 0, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 450
}
# Not `Type`: that is the built-in alias for Get-Content, and an alias beats a
# function, so a function of that name is never called.
function Keys([string]$s) { [void][System.Windows.Forms.SendKeys]::SendWait($s) }
function Find-Wins([string]$title) {
    $found = New-Object System.Collections.ArrayList
    $cb = [TEB+EnumProc] {
        param($h, $l)
        $t = New-Object System.Text.StringBuilder 256
        [void][TEB]::GetWindowText($h, $t, 256)
        if ($t.ToString() -eq $title) { [void]$found.Add($h) }
        return $true
    }
    [void][TEB]::EnumWindows($cb, [IntPtr]::Zero)
    return $found.ToArray()
}
function Find-Kids([IntPtr]$parent, [string]$title) {
    $found = New-Object System.Collections.ArrayList
    $cb = [TEB+EnumProc] {
        param($h, $l)
        $t = New-Object System.Text.StringBuilder 256
        [void][TEB]::GetWindowText($h, $t, 256)
        if ($t.ToString() -eq $title -and [TEB]::IsWindowVisible($h)) { [void]$found.Add($h) }
        return $true
    }
    [void][TEB]::EnumChildWindows($parent, $cb, [IntPtr]::Zero)
    return $found.ToArray()
}
function Rect-Of([IntPtr]$h) {
    $r = New-Object TEB+RECT
    [void][TEB]::GetWindowRect($h, [ref]$r)
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
# The stock cursor resource ids, straight from winuser.h: 32642..32646 run
# NWSE, NESW, WE, NS, ALL. Guessing them is how a four-way arrow gets reported as
# a diagonal one.
$IDC = [ordered]@{
    arrow = 32512; ibeam = 32513; cross = 32515;
    sizeNWSE = 32642; sizeNESW = 32643; sizeWE = 32644;
    sizeNS = 32645; sizeALL = 32646;
}
function Cursor-Name {
    $ci = New-Object TEB+CURSORINFO
    $ci.cbSize = [System.Runtime.InteropServices.Marshal]::SizeOf([type][TEB+CURSORINFO])
    if (-not [TEB]::GetCursorInfo([ref]$ci)) { return '<failed>' }
    foreach ($k in $IDC.Keys) {
        if ($ci.hCursor -eq [TEB]::LoadCursorRes([IntPtr]::Zero, $IDC[$k])) { return $k }
    }
    return 'custom'
}
# The caret, in screen coords. GetGUIThreadInfo wants the THREAD id, which is the
# return value of GetWindowThreadProcessId rather than its out parameter.
$edHost = [IntPtr]::Zero
function Caret() {
    $pid2 = 0
    $tid = [TEB]::GetWindowThreadProcessId($edHost, [ref]$pid2)
    for ($try = 0; $try -lt 10; $try++) {
        $gi = New-Object TEB+GUITHREADINFO
        $gi.cbSize = [System.Runtime.InteropServices.Marshal]::SizeOf([type][TEB+GUITHREADINFO])
        if ([TEB]::GetGUIThreadInfo($tid, [ref]$gi) -and
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
function IsWhite($c) { return ($c.R -gt 200 -and $c.G -gt 200 -and $c.B -gt 200) }
# Rows that carry ink, grouped into bands: one text line is one band, and the line
# pitch leaves rows between them that no glyph reaches.
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
# The bands of a label's own box, with the chrome left out. While editing, the eight
# square markers straddle the box edge and reach 3px inside it, so an inset narrower
# than that counts their rows as text lines; the ink itself starts 5px in from the
# top and left, so 4 in and 5 back keeps every glyph.
function Label-Bands($bmp, $box) {
    return Ink-Bands $bmp ($box.left + 4) ($box.top + 4) ($box.right - 5) ($box.bottom - 5)
}
# How much of the frame line is red. The frame is stroked 1px at the box inflated
# by 2, so it sits on column left-2, row top-2, column right+1 and row bottom+1.
function Frame-Red($bmp, $box) {
    $hit = 0; $n = 0
    $x0 = $box.left - 2; $x1 = $box.right + 1
    $y0 = $box.top - 2; $y1 = $box.bottom + 1
    for ($x = $x0; $x -le $x1; $x++) {
        foreach ($y in $y0, $y1) { $n++; if (IsInk ($bmp.GetPixel($x, $y))) { $hit++ } }
    }
    for ($y = $y0 + 1; $y -le $y1 - 1; $y++) {
        foreach ($x in $x0, $x1) { $n++; if (IsInk ($bmp.GetPixel($x, $y))) { $hit++ } }
    }
    return @{ hit = $hit; n = $n; pct = [int](100 * $hit / $n) }
}
# The eight marker positions, in annot::BoxHandleAt's order, and for each one a
# pixel that is inside its white core and outside the input control. The control
# covers the box except for the PadX strips at the left and right, so a probe
# straight in from the corner is safe everywhere but on the two edge markers whose
# core runs under the control: the right one probes along the edge and the bottom
# one stops at the edge itself, which is the last row the control does not have.
function Marker-Points($box) {
    $mx = [int](($box.left + $box.right) / 2)
    $my = [int](($box.top + $box.bottom) / 2)
    return @(
        @{ n = 'tl'; x = $box.left;     y = $box.top;    dx = -1; dy = -1 },
        @{ n = 'top'; x = $mx;          y = $box.top;    dx = -1; dy = -1 },
        @{ n = 'tr'; x = $box.right;    y = $box.top;    dx = -1; dy = -1 },
        @{ n = 'right'; x = $box.right; y = $my;         dx =  0; dy = -1 },
        @{ n = 'br'; x = $box.right;    y = $box.bottom; dx = -1; dy = -1 },
        @{ n = 'bottom'; x = $mx;       y = $box.bottom; dx = -1; dy =  0 },
        @{ n = 'bl'; x = $box.left;     y = $box.bottom; dx = -1; dy = -1 },
        @{ n = 'left'; x = $box.left;   y = $my;         dx = -1; dy = -1 }
    )
}
# Which of the eight marker positions show a white core. Returns a hashtable
# rather than the bare list: a function's output is collected, so a status line
# printed here would land in the caller's variable alongside the result.
function White-Cores($bmp, $box) {
    $on = @(); $miss = @()
    foreach ($m in Marker-Points $box) {
        $c = $bmp.GetPixel($m.x + $m.dx, $m.y + $m.dy)
        if (IsWhite $c) { $on += $m.n }
        else { $miss += "$($m.n)@$($m.x + $m.dx),$($m.y + $m.dy)=$($c.R),$($c.G),$($c.B)" }
    }
    return @{ on = $on; miss = $miss }
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
[void][TEB]::PostMessage($sink[0], 0x8002, [IntPtr]::Zero, [IntPtr]::Zero)
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
$edHost = $ed
Keys ('W' * 16)
Start-Sleep -Milliseconds 900
$box1 = Edit-Box $ed
Keys '^({ENTER})'              # Ctrl+Enter commits; plain Enter belongs to the control
Start-Sleep -Milliseconds 700
Click $p[0] $p[1]              # disarm

# --- make the label one the user narrowed, so it carries wrapped lines ---------
# 65% of the width a single line needed is comfortably two lines and comfortably
# short of three, for the label and for the control inside it alike.
DblClick ([int](($box1.left + $box1.right) / 2)) ([int](($box1.top + $box1.bottom) / 2))
$ed2 = Editor
if (-not $ed2) { 'FAIL: double-clicking the label did not re-open it'; exit 1 }
$boxR = Edit-Box $ed2
$wNarrow = [int](($boxR.right - $boxR.left) * 0.65)
$my = [int](($boxR.top + $boxR.bottom) / 2)
Drag ($boxR.right + 2) $my ($boxR.left + $wNarrow) $my
Start-Sleep -Milliseconds 500
$ed2b = Editor
if (-not $ed2b) { 'FAIL: dragging the right marker closed the edit'; exit 1 }
$box2 = Edit-Box $ed2b
Keys '^({ENTER})'
Start-Sleep -Milliseconds 700
Click $p[0] $p[1]
MoveTo 2300 1800; Start-Sleep -Milliseconds 400
$g = Grab 'D:\Project\winshot\obj\teb_narrow.png'
$bands0 = Label-Bands $g $box2
$g.Dispose()
"narrowed box: $($box2.left),$($box2.top) .. $($box2.right),$($box2.bottom)"
foreach ($x in $bands0) { "  band y $($x.t)..$($x.b)  x $($x.l)..$($x.r)" }
if ($bands0.Count -lt 2) {
    "FAIL: the narrowed label holds $($bands0.Count) line(s); the test needs a wrapped one"
    exit 1
}
$pitch = $bands0[1].t - $bands0[0].t
"committed label: $($bands0.Count) lines, line pitch $pitch px"

# --- 7: re-opening keeps that box, and the wrap with it ------------------------
DblClick ($bands0[0].l + 20) ($bands0[0].t + 5)
$ed3 = Editor
if (-not $ed3) { 'FAIL: double-clicking the wrapped label did not re-open it'; exit 1 }
$edHost = $ed3
$box3 = Edit-Box $ed3
"re-opened box: $($box3.left),$($box3.top) .. $($box3.right),$($box3.bottom)"
if ([Math]::Abs($box3.left - $box2.left) -gt 2 -or [Math]::Abs($box3.right - $box2.right) -gt 2 -or
    [Math]::Abs($box3.top - $box2.top) -gt 2 -or [Math]::Abs($box3.bottom - $box2.bottom) -gt 2) {
    $fail += "re-opening the label changed its box from $($box2.left),$($box2.top) .. $($box2.right),$($box2.bottom) to $($box3.left),$($box3.top) .. $($box3.right),$($box3.bottom)"
}
MoveTo 2300 1800; Start-Sleep -Milliseconds 400
$g = Grab 'D:\Project\winshot\obj\teb_reopen.png'
$bands1 = Label-Bands $g $box3
$g.Dispose()
"while editing: $($bands1.Count) line(s) (want $($bands0.Count))"
foreach ($x in $bands1) { "  band y $($x.t)..$($x.b)  x $($x.l)..$($x.r)" }
if ($bands1.Count -ne $bands0.Count) {
    $fail += "re-opening the label turned its $($bands0.Count) lines into $($bands1.Count): the wrap did not survive the edit"
}

# --- 6: the caret opens at the end of the text, not the start ------------------
$c = Caret
if (-not $c) {
    $fail += 'could not read the caret from the editing thread'
} else {
    $last = $bands1[$bands1.Count - 1]
    $first = $bands1[0]
    "caret at $($c.x),$($c.y) (h $($c.h)); last line ink x $($first.l)..$($last.r) y $($last.t)..$($last.b)"
    if ([Math]::Abs($c.x - ($last.r + 1)) -gt 10) {
        $fail += "the caret opened at x $($c.x), want within 10 px of the last glyph's right edge at $(($last.r + 1))"
    }
    if ($c.y -gt $last.b -or $c.y + $c.h -lt $last.t) {
        $fail += "the caret opened on the row range $($c.y)..$($c.y + $c.h), outside the last line at $($last.t)..$($last.b)"
    }
    if ($bands1.Count -gt 1 -and $c.y + $c.h -gt $first.t -and $c.y -le $first.b) {
        $fail += 'the caret opened on the first line, which is where it used to land'
    }
}

# --- 9: Enter inserts a line break and the box grows by one line ---------------
$h0 = $box3.bottom - $box3.top
Keys '{ENTER}X'
Start-Sleep -Milliseconds 800
$ed4 = Editor
if (-not $ed4) { 'FAIL: Enter closed the edit instead of breaking the line'; exit 1 }
$edHost = $ed4
$box4 = Edit-Box $ed4
MoveTo 2300 1800; Start-Sleep -Milliseconds 400
$g = Grab 'D:\Project\winshot\obj\teb_enter.png'
$bands2 = Label-Bands $g $box4
$g.Dispose()
"after Enter: box $($box4.left),$($box4.top) .. $($box4.right),$($box4.bottom), $($bands2.Count) line(s)"
if ($bands2.Count -ne $bands1.Count + 1) {
    $fail += "Enter left $($bands2.Count) lines of text, want $($bands1.Count + 1): Enter is not inserting a line break"
}
$grew = ($box4.bottom - $box4.top) - $h0
if ([Math]::Abs($grew - $pitch) -gt 3) {
    $fail += "Enter grew the box by $grew px, want one line pitch of $pitch px"
}
Keys '^({ENTER})'
Start-Sleep -Milliseconds 700
Click $p[0] $p[1]              # disarm

# --- 8: committed and clicked away from, the label shows its text only ---------
Click 1800 1200
Start-Sleep -Milliseconds 500
MoveTo 2300 1800; Start-Sleep -Milliseconds 400
$g = Grab 'D:\Project\winshot\obj\teb_committed.png'
$f0 = Frame-Red $g $box4
$c0 = White-Cores $g $box4
$g.Dispose()
"after commit: frame line $($f0.pct)% red (want 0), cores $($c0.on.Count)/8"
if ($f0.pct -gt 5) {
    $fail += "the committed label still draws its red frame: $($f0.pct)% of the frame line is red"
}
if ($c0.on.Count -ne 0) {
    $fail += "the committed label still draws markers at $(($c0.on) -join ' ')"
}

# --- 8: a single click gives the frame, no markers, and the move cursor --------
Click ($bands2[0].l + 20) ($bands2[0].t + 5)
Start-Sleep -Milliseconds 500
MoveTo 2300 1800; Start-Sleep -Milliseconds 400
$g = Grab 'D:\Project\winshot\obj\teb_selected.png'
$f1 = Frame-Red $g $box4
$c1 = White-Cores $g $box4
$g.Dispose()
"single click: frame line $($f1.pct)% red (want over 90), cores $($c1.on.Count)/8 (want 0)"
if ($f1.pct -lt 90) {
    $fail += "a selected label draws its red frame on only $($f1.pct)% of the frame line, want the whole of it"
}
if ($c1.on.Count -ne 0) {
    $fail += "a selected label that is not being edited draws markers at $(($c1.on) -join ' '): it has no handles to mark"
}
MoveTo ([int](($box4.left + $box4.right) / 2)) ([int](($box4.top + $box4.bottom) / 2))
$cur = Cursor-Name
"hover inside a selected label: $cur (want sizeALL)"
if ($cur -ne 'sizeALL') {
    $fail += "hovering inside a selected label that is not being edited shows $cur, want the four-way move arrow"
}

# --- 9: double click adds the markers, the I-beam and the grips ----------------
DblClick ($bands2[0].l + 20) ($bands2[0].t + 5)
$ed5 = Editor
if (-not $ed5) { 'FAIL: double-clicking the label did not re-open it'; exit 1 }
$edHost = $ed5
$box5 = Edit-Box $ed5
MoveTo 2300 1800; Start-Sleep -Milliseconds 400
$g = Grab 'D:\Project\winshot\obj\teb_editing.png'
$f2 = Frame-Red $g $box5
$c2 = White-Cores $g $box5
$g.Dispose()
"editing: frame line $($f2.pct)% red, cores $($c2.on.Count)/8 $(($c2.miss) -join ' ')"
# Not 100%: the eight markers sit on the box edge and each one paints over the
# frame line where it crosses, which is around 8% of the line's length.
if ($f2.pct -lt 85) {
    $fail += "the label being edited draws its red frame on only $($f2.pct)% of the frame line"
}
if ($c2.on.Count -ne 8) {
    $fail += "the label being edited shows markers at $(($c2.on) -join ' ') - all eight corners and edges want one; missing: $(($c2.miss) -join ' ')"
}
$my5 = [int](($box5.top + $box5.bottom) / 2)
MoveTo ([int](($box5.left + $box5.right) / 2)) $my5
$cur = Cursor-Name
"hover inside the editing box: $cur (want ibeam)"
if ($cur -ne 'ibeam') {
    $fail += "hovering inside the text being edited shows $cur, want the I-beam"
}
MoveTo ($box5.right + 2) $my5
$cur = Cursor-Name
"hover on the right marker: $cur (want sizeWE)"
if ($cur -ne 'sizeWE') {
    $fail += "hovering on the marker at the box's right edge shows $cur, want the left-right resize arrow"
}
# The frame line a quarter of the way down the left edge: far enough from the
# corner and edge markers that a press there moves the box rather than resizing it.
MoveTo ($box5.left - 2) ([int]($box5.top + ($box5.bottom - $box5.top) / 4))
$cur = Cursor-Name
"hover on the frame line away from a marker: $cur (want sizeALL)"
if ($cur -ne 'sizeALL') {
    $fail += "hovering on the red frame away from a marker shows $cur, want the four-way move arrow"
}

Keys '{ESC}'
Start-Sleep -Milliseconds 400
if (-not $proc.HasExited) { $proc.Kill() }
if ($fail.Count) { "FAILURES: $($fail.Count)"; $fail | ForEach-Object { "  $_" }; exit 1 }
'PASS'
