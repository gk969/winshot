# What falls outside the 选区 is not in the export, so an element dragged past the
# frame reads as having vanished — the user's complaint. It has to stop at the
# frame instead. Drag one well past the bottom-right corner and then well past
# the top-left and measure where the ink actually ended up: it should be flush
# with the frame, not out where the pointer went.
Add-Type -AssemblyName System.Drawing, System.Windows.Forms
Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class DC {
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
function MoveTo([int]$x, [int]$y) {
    [System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point($x, $y)
    Start-Sleep -Milliseconds 110
}
# $steps is how many moves the path takes. A real drag arrives as a stream of
# moves a pixel or two apart, and the freeze stops at the last one that still
# fits, so a coarse path stops a whole step short of the frame. These drags cross
# 1700px, so they take enough steps to land within a few px of it.
function Drag([int]$x1, [int]$y1, [int]$x2, [int]$y2, [int]$steps = 14) {
    MoveTo $x1 $y1
    [void][DC]::mouse_event($LEFTDOWN, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 120
    for ($i = 1; $i -le $steps; $i++) {
        MoveTo ([int]($x1 + ($x2-$x1) * $i / $steps)) ([int]($y1 + ($y2-$y1) * $i / $steps))
    }
    Start-Sleep -Milliseconds 150
    [void][DC]::mouse_event($LEFTUP, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 350
}
function Click([int]$x, [int]$y) {
    MoveTo $x $y
    [void][DC]::mouse_event($LEFTDOWN, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 120
    [void][DC]::mouse_event($LEFTUP, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 350
}
function Find-Wins([string]$title) {
    $found = New-Object System.Collections.ArrayList
    $cb = [DC+EnumProc] {
        param($h, $l)
        $t = New-Object System.Text.StringBuilder 256
        [void][DC]::GetWindowText($h, $t, 256)
        if ($t.ToString() -eq $title) { [void]$found.Add($h) }
        return $true
    }
    [void][DC]::EnumWindows($cb, [IntPtr]::Zero)
    return $found.ToArray()
}
function Find-Kids([IntPtr]$parent, [string]$title) {
    $found = New-Object System.Collections.ArrayList
    $cb = [DC+EnumProc] {
        param($h, $l)
        $t = New-Object System.Text.StringBuilder 256
        [void][DC]::GetWindowText($h, $t, 256)
        if ($t.ToString() -eq $title -and [DC]::IsWindowVisible($h)) { [void]$found.Add($h) }
        return $true
    }
    [void][DC]::EnumChildWindows($parent, $cb, [IntPtr]::Zero)
    return $found.ToArray()
}
function Rect-Of([IntPtr]$h) {
    $r = New-Object DC+RECT
    [void][DC]::GetWindowRect($h, [ref]$r)
    return $r
}
function IsRed($c) { return ($c.R -gt 190 -and $c.G -lt 120 -and $c.B -lt 130) }
# ClearType puts single red pixels along the edges of desktop text, and one of
# those a hundred pixels from the shape moves the box's corner by a hundred
# pixels. The default stroke is the middle dot, 4px, so the span is 1px either
# way: enough to reject a fringe, narrow enough to stay inside the stroke.
function Solid($bmp, [int]$x, [int]$y) {
    foreach ($d in @(-1, 1)) {
        if (-not (IsRed ($bmp.GetPixel($x + $d, $y)))) { return $false }
        if (-not (IsRed ($bmp.GetPixel($x, $y + $d)))) { return $false }
    }
    return $true
}
function Ink-Box($bmp, [int]$x0, [int]$y0, [int]$x1, [int]$y1) {
    $l = -1; $t = -1; $r = -1; $b = -1; $n = 0
    for ($y = $y0; $y -le $y1; $y++) {
        for ($x = $x0; $x -le $x1; $x++) {
            if (-not (IsRed ($bmp.GetPixel($x, $y)))) { continue }
            if (-not (Solid $bmp $x $y)) { continue }
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

$sel = @(800, 600, 1500, 1050)
# A selected element wears a red ring with white handle circles, and the stroke
# reaches half its width past the element's own box, so the ink gets a little
# past it. That overhang is what the tolerance allows for; the element never does.
$TOL = 16
$fail = @()

MoveTo 3000 1900
Start-Sleep -Milliseconds 400
Get-Process winshot -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 600
$proc = Start-Process -FilePath 'D:\Project\winshot\x64\Debug\winshot.exe' -PassThru
Start-Sleep -Seconds 2

$sink = @(Find-Wins 'WinShotSink')
if ($sink.Count -eq 0) { 'FAIL: no sink window'; exit 1 }
[void][DC]::PostMessage($sink[0], 0x8002, [IntPtr]::Zero, [IntPtr]::Zero)
Start-Sleep -Seconds 2

Drag $sel[0] $sel[1] $sel[2] $sel[3]
$ov = @(Find-Wins 'WinShotOverlay')
if ($ov.Count -eq 0) { 'FAIL: no overlay window'; exit 1 }

# The bar re-lays itself out when the property bar opens and closes under it.
function Click-Slot([int]$i) {
    $t = @(Find-Kids $ov[0] 'WinShotToolbar')
    if ($t.Count -eq 0) { return }
    $tr = Rect-Of $t[0]
    $s = ($tr.bottom - $tr.top) / 32.0
    $cell = [int][Math]::Round(27 * $s); $pad = [int][Math]::Round(4 * $s)
    Click ($tr.left + $pad + $i * $cell + [int]($cell / 2)) ([int](($tr.top + $tr.bottom) / 2))
}

Click-Slot 0            # arm the rectangle tool
Drag 900 700 1000 800   # the element to move
Click-Slot 0            # disarm, so a press on it moves it instead of drawing

$s = Grab 'D:\Project\winshot\obj\clamp_start.png'
$at = Ink-Box $s 850 650 1050 850
$s.Dispose()
if (-not $at) { 'FAIL: the rectangle was never drawn'; exit 1 }
"drawn at $($at.l),$($at.t) .. $($at.r),$($at.b) ($($at.n) px)"

# --- far past the bottom-right corner ---------------------------------------
# The pointer goes to 2600,1900, more than 1000px beyond the frame in both axes.
Drag ([int]($at.l + ($at.r - $at.l) / 4)) $at.t 2600 1900 60
$s = Grab 'D:\Project\winshot\obj\clamp_br.png'
$br = Ink-Box $s 1150 850 1600 1150
$s.Dispose()
if (-not $br) {
    $fail += 'dragging the rectangle past the bottom-right corner lost it entirely'
} else {
    "after the down-right drag: $($br.l),$($br.t) .. $($br.r),$($br.b) ($($br.n) px)"
    "  frame right=$($sel[2]) bottom=$($sel[3]); pointer went to 2600,1900"
    if ($br.r -gt $sel[2] + $TOL) {
        $fail += "the rectangle reached x=$($br.r), past the frame at $($sel[2])"
    }
    if ($br.b -gt $sel[3] + $TOL) {
        $fail += "the rectangle reached y=$($br.b), past the frame at $($sel[3])"
    }
    # Stopping at the frame is only proved if it actually got there; an element
    # that stopped short would pass the two checks above by accident.
    if ($br.r -lt $sel[2] - 60) { $fail += "the rectangle stopped at x=$($br.r), short of the frame at $($sel[2])" }
    if ($br.b -lt $sel[3] - 60) { $fail += "the rectangle stopped at y=$($br.b), short of the frame at $($sel[3])" }
}

# --- far past the top-left corner -------------------------------------------
if ($br) {
    Drag ([int]($br.l + ($br.r - $br.l) / 4)) $br.t 100 100 60
    $s = Grab 'D:\Project\winshot\obj\clamp_tl.png'
    $tl = Ink-Box $s 740 540 1050 850
    $s.Dispose()
    if (-not $tl) {
        $fail += 'dragging the rectangle past the top-left corner lost it entirely'
    } else {
        "after the up-left drag: $($tl.l),$($tl.t) .. $($tl.r),$($tl.b) ($($tl.n) px)"
        "  frame left=$($sel[0]) top=$($sel[1]); pointer went to 100,100"
        if ($tl.l -lt $sel[0] - $TOL) {
            $fail += "the rectangle reached x=$($tl.l), past the frame at $($sel[0])"
        }
        if ($tl.t -lt $sel[1] - $TOL) {
            $fail += "the rectangle reached y=$($tl.t), past the frame at $($sel[1])"
        }
        if ($tl.l -gt $sel[0] + 60) { $fail += "the rectangle stopped at x=$($tl.l), short of the frame at $($sel[0])" }
        if ($tl.t -gt $sel[1] + 60) { $fail += "the rectangle stopped at y=$($tl.t), short of the frame at $($sel[1])" }
    }
}

if (-not $proc.HasExited) { $proc.Kill() }
if ($fail.Count) { "FAILURES: $($fail.Count)"; $fail | ForEach-Object { "  $_" }; exit 1 }
'PASS'
