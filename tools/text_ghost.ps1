# Double-clicking a committed label re-opens it, and the re-opened box used to
# show the text twice. The editor paints its own backdrop out of the overlay's
# cached base canvas, and that canvas still held the label's committed glyphs, so
# they came through behind whatever was being typed. Committing or cancelling
# repaints the base, which is why it looked right again the moment the edit ended.
#
# Three measurements of one inset box, the label's own:
#   A  the label as committed, editor closed - the ink the box is meant to hold,
#      and the positive control: it proves the box does contain measurable ink.
#   B  the editor open over it with the text selected and deleted - the box has
#      to be empty. With the ghost the committed glyphs are still painted in
#      there, so B comes back at about A.
#   C  after ESC, which cancels the edit - back to A. This is what separates a
#      label excluded from the base for the duration of an edit from one that has
#      simply been erased from it.
Add-Type -AssemblyName System.Drawing, System.Windows.Forms
Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class TG {
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
    [void][TG]::mouse_event(0x8001, [uint32][int][Math]::Floor(65535 * $x / 3840),
                            [uint32][int][Math]::Floor(65535 * $y / 2160), 0,
                            [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 90
}
function Down { [void][TG]::mouse_event($LEFTDOWN, 0, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 150 }
function Up { [void][TG]::mouse_event($LEFTUP, 0, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 350 }
function Walk([int]$x1, [int]$y1, [int]$x2, [int]$y2, [int]$steps) {
    for ($i = 1; $i -le $steps; $i++) {
        MoveTo ([int]($x1 + ($x2-$x1) * $i / $steps)) ([int]($y1 + ($y2-$y1) * $i / $steps))
    }
}
function Drag([int]$x1, [int]$y1, [int]$x2, [int]$y2) {
    MoveTo $x1 $y1; Down; Walk $x1 $y1 $x2 $y2 20; Up
}
function Click([int]$x, [int]$y) { MoveTo $x $y; Down; Up }
# Two presses inside the double-click time, which is what makes the shell pair
# them into WM_LBUTTONDBLCLK rather than two single clicks.
function DblClick([int]$x, [int]$y) {
    MoveTo $x $y
    [void][TG]::mouse_event($LEFTDOWN, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 60
    [void][TG]::mouse_event($LEFTUP, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 60
    [void][TG]::mouse_event($LEFTDOWN, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 60
    [void][TG]::mouse_event($LEFTUP, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 450
}
# Not `Type`: that is the built-in alias for Get-Content, and an alias beats a
# function, so a function of that name is never called.
function Keys([string]$s) { [void][System.Windows.Forms.SendKeys]::SendWait($s) }
function Find-Wins([string]$title) {
    $found = New-Object System.Collections.ArrayList
    $cb = [TG+EnumProc] {
        param($h, $l)
        $t = New-Object System.Text.StringBuilder 256
        [void][TG]::GetWindowText($h, $t, 256)
        if ($t.ToString() -eq $title) { [void]$found.Add($h) }
        return $true
    }
    [void][TG]::EnumWindows($cb, [IntPtr]::Zero)
    return $found.ToArray()
}
function Find-Kids([IntPtr]$parent, [string]$title) {
    $found = New-Object System.Collections.ArrayList
    $cb = [TG+EnumProc] {
        param($h, $l)
        $t = New-Object System.Text.StringBuilder 256
        [void][TG]::GetWindowText($h, $t, 256)
        if ($t.ToString() -eq $title -and [TG]::IsWindowVisible($h)) { [void]$found.Add($h) }
        return $true
    }
    [void][TG]::EnumChildWindows($parent, $cb, [IntPtr]::Zero)
    return $found.ToArray()
}
function Rect-Of([IntPtr]$h) {
    $r = New-Object TG+RECT
    [void][TG]::GetWindowRect($h, [ref]$r)
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

$fail = @()

MoveTo 3000 1900
Start-Sleep -Milliseconds 400
Get-Process winshot -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 600
$proc = Start-Process -FilePath 'D:\Project\winshot\x64\Debug\winshot.exe' -PassThru
Start-Sleep -Seconds 2

$sink = @(Find-Wins 'WinShotSink')
if ($sink.Count -eq 0) { 'FAIL: no sink window'; exit 1 }
[void][TG]::PostMessage($sink[0], 0x8002, [IntPtr]::Zero, [IntPtr]::Zero)
Start-Sleep -Seconds 2
$ov = @(Find-Wins 'WinShotOverlay')
if ($ov.Count -eq 0) { 'FAIL: no overlay window'; exit 1 }

Drag 800 600 1600 1400
$p = Slot 5
if (-not $p) { 'FAIL: no toolbar'; exit 1 }
Click $p[0] $p[1]              # the text tool
Click 950 690
$ed = Editor
if (-not $ed) { 'FAIL: clicking with the text tool opened no editor'; exit 1 }
Keys ('GHOSTTEST ' * 4)
Start-Sleep -Milliseconds 900
$box0 = Edit-Box $ed
# Plain Enter belongs to the control and inserts a newline; Ctrl+Enter is the
# commit.
Keys '^({ENTER})'
Start-Sleep -Milliseconds 700
Click $p[0] $p[1]              # disarm, so a double click lands on the label

# --- A: the label as committed ------------------------------------------------
# The inset keeps the selection chrome out of the count: the frame is stroked 2px
# outside the box and the markers straddle the edge, reaching about 2px inside it.
# The ink starts 5px below the top edge and, now that the box is exactly N line
# cells, ends the same 5px above the bottom one -- with a descender a little lower,
# so the bottom inset is 2 rather than 5 and the count keeps the whole last line.
MoveTo 2300 1800; Start-Sleep -Milliseconds 400
$gA = Grab 'D:\Project\winshot\obj\tg_committed.png'
$il = $box0.left + 4; $it = $box0.top + 4; $ir = $box0.right - 5; $ib = $box0.bottom - 2
$inkA = Ink-Box $gA $il $it $ir $ib
$gA.Dispose()
if (-not $inkA) { 'FAIL: the committed label drew no ink in its own box'; exit 1 }
$nA = $inkA.n
"committed label: box $($box0.left),$($box0.top) .. $($box0.right),$($box0.bottom), $nA red px inside"
if ($nA -lt 300) { "FAIL: only $nA red px in the committed label, so the box proves nothing"; exit 1 }

# --- B: the same label re-opened, nearly emptied ------------------------------
DblClick ([int](($inkA.l + $inkA.r) / 2)) ([int](($inkA.t + $inkA.b) / 2))
$ed2 = Editor
if (-not $ed2) { 'FAIL: double-clicking the label did not re-open it'; exit 1 }
$box = Edit-Box $ed2
"re-opened box: $($box.left),$($box.top) .. $($box.right),$($box.bottom)"
if ([Math]::Abs($box.left - $box0.left) -gt 6 -or [Math]::Abs($box.top - $box0.top) -gt 6) {
    "FAIL: the re-opened editor is at a different place than the label, so it is not the same one"
    exit 1
}
# Ctrl+A is the control's own select-all and Delete then empties the selection in
# one keystroke, so the result does not depend on 38 keys all arriving. Emptying
# it is safe: the label is only discarded on commit, and this step ends with ESC.
Keys '^a'
Start-Sleep -Milliseconds 200
Keys '{DEL}'
Start-Sleep -Milliseconds 800
MoveTo 2300 1800; Start-Sleep -Milliseconds 400
$gB = Grab 'D:\Project\winshot\obj\tg_emptied.png'
$nB = RedCount $gB $il $it $ir $ib
$gB.Dispose()
"editor open, text deleted: $nB red px in the same box (want well under $nA)"
if ($nB -gt [int](0.3 * $nA)) {
    $fail += "with the text deleted the box still holds $nB red px where the label drew ${nA}: the committed glyphs are painted behind the editor"
}

# --- C: cancelling puts the label back ----------------------------------------
Keys '{ESC}'
Start-Sleep -Milliseconds 800
MoveTo 2300 1800; Start-Sleep -Milliseconds 400
$gC = Grab 'D:\Project\winshot\obj\tg_cancelled.png'
$nC = RedCount $gC $il $it $ir $ib
$gC.Dispose()
"after ESC: $nC red px in the same box (want about $nA)"
if ([Math]::Abs($nC - $nA) -gt 80) {
    $fail += "cancelling the edit left $nC red px where the committed label drew ${nA}: the label did not come back"
}

Keys '{ESC}'
Start-Sleep -Milliseconds 400
if (-not $proc.HasExited) { $proc.Kill() }
if ($fail.Count) { "FAILURES: $($fail.Count)"; $fail | ForEach-Object { "  $_" }; exit 1 }
'PASS'
