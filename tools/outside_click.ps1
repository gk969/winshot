# Once a 选区 exists, everything outside it used to be live: a press there started
# a brand new rubber band, which was a easy way to lose the region you had. The
# request is that outside a press and a drag do nothing at all, an outside double
# click leaves the capture, and an outside right click throws the whole session
# back to the state it opened in -- whole-screen region, no shapes, magnifier
# card back.
#
# The toolbar is placed from the region alone, so its rectangle is a witness for
# the region; the ink box is the witness for the shapes.
Add-Type -AssemblyName System.Drawing, System.Windows.Forms
Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class OC {
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
$RBUTTONDOWN = 0x0008; $RBUTTONUP = 0x0010

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
function Down { [void][OC]::mouse_event($LEFTDOWN, 0, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 150 }
function Up { [void][OC]::mouse_event($LEFTUP, 0, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 350 }
function Walk([int]$x1, [int]$y1, [int]$x2, [int]$y2, [int]$steps) {
    for ($i = 1; $i -le $steps; $i++) {
        MoveTo ([int]($x1 + ($x2-$x1) * $i / $steps)) ([int]($y1 + ($y2-$y1) * $i / $steps))
    }
}
function Drag([int]$x1, [int]$y1, [int]$x2, [int]$y2) {
    MoveTo $x1 $y1; Down; Walk $x1 $y1 $x2 $y2 20; Up
}
# The second press has to land inside the double-click time, which the 350ms Up
# pause alone would blow past.
function Dbl([int]$x, [int]$y) {
    MoveTo $x $y
    [void][OC]::mouse_event($LEFTDOWN, 0, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 60
    [void][OC]::mouse_event($LEFTUP, 0, 0, 0, [UIntPtr]::Zero)
    [void][OC]::mouse_event($LEFTDOWN, 0, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 60
    [void][OC]::mouse_event($LEFTUP, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 350
}
function RClick([int]$x, [int]$y) {
    MoveTo $x $y
    [void][OC]::mouse_event($RBUTTONDOWN, 0, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 150
    [void][OC]::mouse_event($RBUTTONUP, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 600
}
function Find-Wins([string]$title) {
    $found = New-Object System.Collections.ArrayList
    $cb = [OC+EnumProc] {
        param($h, $l)
        $t = New-Object System.Text.StringBuilder 256
        [void][OC]::GetWindowText($h, $t, 256)
        if ($t.ToString() -eq $title) { [void]$found.Add($h) }
        return $true
    }
    [void][OC]::EnumWindows($cb, [IntPtr]::Zero)
    return $found.ToArray()
}
function Find-Kids([IntPtr]$parent, [string]$title) {
    $found = New-Object System.Collections.ArrayList
    $cb = [OC+EnumProc] {
        param($h, $l)
        $t = New-Object System.Text.StringBuilder 256
        [void][OC]::GetWindowText($h, $t, 256)
        if ($t.ToString() -eq $title -and [OC]::IsWindowVisible($h)) { [void]$found.Add($h) }
        return $true
    }
    [void][OC]::EnumChildWindows($parent, $cb, [IntPtr]::Zero)
    return $found.ToArray()
}
function Rect-Of([IntPtr]$h) {
    $r = New-Object OC+RECT
    [void][OC]::GetWindowRect($h, [ref]$r)
    return $r
}
function Same-Rect($a, $b) {
    return ($a.left -eq $b.left -and $a.top -eq $b.top -and
            $a.right -eq $b.right -and $a.bottom -eq $b.bottom)
}
function IsRed($c) { return ($c.R -gt 190 -and $c.G -lt 120 -and $c.B -lt 130) }
function IsCyan($c) {
    return ([Math]::Abs($c.R - 77) -le 40 -and [Math]::Abs($c.G - 202) -le 40 -and
            [Math]::Abs($c.B - 250) -le 25)
}
function CyanCount($bmp, [int]$x0, [int]$y0, [int]$x1, [int]$y1) {
    $n = 0
    for ($y = $y0; $y -le $y1; $y++) {
        for ($x = $x0; $x -le $x1; $x++) { if (IsCyan ($bmp.GetPixel($x, $y))) { $n++ } }
    }
    return $n
}
function In-Bars([int]$x, [int]$y, $bars) {
    foreach ($b2 in $bars) {
        if ($x -ge $b2.left -and $x -lt $b2.right -and
            $y -ge $b2.top -and $y -lt $b2.bottom) { return $true }
    }
    return $false
}
function Ink-Box($bmp, [int]$x0, [int]$y0, [int]$x1, [int]$y1, $skip = @()) {
    $l = -1; $t = -1; $r = -1; $b = -1; $n = 0
    for ($y = $y0; $y -le $y1; $y++) {
        for ($x = $x0; $x -le $x1; $x++) {
            if (In-Bars $x $y $skip) { continue }
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

$sel = @(800, 600, 1500, 1000)
$shape = @(900, 700, 1300, 900)
# Far outside the 选区, and clear of the two bars, which hang below it from x=800.
$out = @(2400, 1700)
$scan = @(860, 560, 1540, 1040)
$fail = @()

function Start-Session {
    MoveTo 3000 1900
    Start-Sleep -Milliseconds 400
    Get-Process winshot -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep -Milliseconds 600
    $p = Start-Process -FilePath 'D:\Project\winshot\x64\Debug\winshot.exe' -PassThru
    Start-Sleep -Seconds 2
    $s = @(Find-Wins 'WinShotSink')
    if ($s.Count -eq 0) { 'FAIL: no sink window'; exit 1 }
    [void][OC]::PostMessage($s[0], 0x8002, [IntPtr]::Zero, [IntPtr]::Zero)
    Start-Sleep -Seconds 2
    return $p
}
# The toolbar and, when it is open, the 粗细/颜色 bar: both are child windows
# painted over the overlay, and the bar's palette holds a red swatch.
function Bars($ov) {
    $r = @(Rect-Of (@(Find-Kids $ov 'WinShotToolbar'))[0])
    $pb = @(Find-Kids $ov 'WinShotPropBar')
    if ($pb.Count) { $r += @(Rect-Of $pb[0]) }
    return $r
}
function Toolbar-Rect($ov) { return Rect-Of (@(Find-Kids $ov 'WinShotToolbar'))[0] }
function Slot($tr, [int]$i) {
    $s = ($tr.bottom - $tr.top) / 32.0
    $cell = [int][Math]::Round(27 * $s); $pad = [int][Math]::Round(4 * $s)
    return @(($tr.left + $pad + [int]($cell / 2) + $i * $cell),
             [int](($tr.top + $tr.bottom) / 2))
}

# ============================ round 1: click, drag, double click =============
$proc = Start-Session
$ov = @(Find-Wins 'WinShotOverlay')
if ($ov.Count -eq 0) { 'FAIL: no overlay window'; exit 1 }

Drag $sel[0] $sel[1] $sel[2] $sel[3]
$tr = Toolbar-Rect $ov[0]
$p = Slot $tr 0
MoveTo $p[0] $p[1]; Down; Up          # the rectangle tool
Drag $shape[0] $shape[1] $shape[2] $shape[3]
MoveTo $p[0] $p[1]; Down; Up          # disarm: an armed tool draws outside too

$bars = Bars $ov[0]
$tr0 = Toolbar-Rect $ov[0]
$m0 = Grab 'D:\Project\winshot\obj\outside_base.png'
$ink0 = Ink-Box $m0 $scan[0] $scan[1] $scan[2] $scan[3] $bars
$m0.Dispose()
if (-not $ink0) { 'FAIL: the rectangle never got drawn'; exit 1 }
"baseline: toolbar at $($tr0.left),$($tr0.top), ink $($ink0.l),$($ink0.t) .. $($ink0.r),$($ink0.b) ($($ink0.n) px)"

function Unchanged($tag, $path) {
    $m = Grab $path
    $ink = Ink-Box $m $scan[0] $scan[1] $scan[2] $scan[3] (Bars $ov[0])
    $m.Dispose()
    $tr = Toolbar-Rect $ov[0]
    "$tag`: toolbar at $($tr.left),$($tr.top), ink $(if ($ink) { "$($ink.l),$($ink.t) .. $($ink.r),$($ink.b) ($($ink.n) px)" } else { 'none' })"
    if (-not (Same-Rect $tr $tr0)) {
        $script:fail += "$tag`: the region moved (toolbar $($tr0.left),$($tr0.top) -> $($tr.left),$($tr.top))"
    }
    if (-not $ink) {
        $script:fail += "$tag`: the shape disappeared"
    } elseif ($ink.n -ne $ink0.n -or $ink.l -ne $ink0.l -or $ink.t -ne $ink0.t -or
              $ink.r -ne $ink0.r -or $ink.b -ne $ink0.b) {
        $script:fail += "$tag`: the shape moved ($($ink0.l),$($ink0.t) .. $($ink0.r),$($ink0.b) -> $($ink.l),$($ink.t) .. $($ink.r),$($ink.b))"
    }
}

MoveTo $out[0] $out[1]; Down; Up
Unchanged 'outside click' 'D:\Project\winshot\obj\outside_click.png'
Drag $out[0] $out[1] 2700 1900
Unchanged 'outside drag' 'D:\Project\winshot\obj\outside_drag.png'

Dbl $out[0] $out[1]
Start-Sleep -Milliseconds 900
$n = @(Find-Wins 'WinShotOverlay').Count
"overlay after the outside double click: $n (want 0)"
if ($n -gt 0) { $fail += 'the outside double click left the capture up' }
if (-not $proc.HasExited) { $proc.Kill() }

# ============================ round 2: right click resets ====================
$proc = Start-Session
$ov = @(Find-Wins 'WinShotOverlay')
if ($ov.Count -eq 0) { 'FAIL: no overlay window (round 2)'; exit 1 }
$trFull = Toolbar-Rect $ov[0]
"toolbar with the whole screen selected: $($trFull.left),$($trFull.top)"

Drag $sel[0] $sel[1] $sel[2] $sel[3]
$tr = Toolbar-Rect $ov[0]
$p = Slot $tr 0
MoveTo $p[0] $p[1]; Down; Up
Drag $shape[0] $shape[1] $shape[2] $shape[3]

RClick $out[0] $out[1]
# The card rides the cursor, so it has to be parked where the count looks.
MoveTo 1900 1000
Start-Sleep -Milliseconds 500
$m = Grab 'D:\Project\winshot\obj\outside_reset.png'
$ink = Ink-Box $m $scan[0] $scan[1] $scan[2] $scan[3] (Bars $ov[0])
# The magnifier card is back once the region is unpicked again: its crosshair is
# the only cyan on screen. The card hangs 30px below-right of the cursor.
$cy = CyanCount $m 1930 1030 2046 1175
$m.Dispose()
$trNow = Toolbar-Rect $ov[0]
"after the outside right click: ink $(if ($ink) { "$($ink.l),$($ink.t) .. $($ink.r),$($ink.b) ($($ink.n) px)" } else { 'none' }), loupe crosshair $cy, toolbar at $($trNow.left),$($trNow.top) (whole-screen was $($trFull.left),$($trFull.top))"
if ($ink) { $fail += "the outside right click left a shape behind ($($ink.n) red px)" }
if (-not (Same-Rect $trNow $trFull)) {
    $fail += "the outside right click did not return the region to the whole screen (toolbar $($trNow.left),$($trNow.top), want $($trFull.left),$($trFull.top))"
}
if ($cy -lt 300) { $fail += "the magnifier card did not come back (crosshair=$cy)" }

# Undo must not resurrect what the reset threw away.
[void][System.Windows.Forms.SendKeys]::SendWait('^z')
Start-Sleep -Milliseconds 500
$m2 = Grab 'D:\Project\winshot\obj\outside_undo.png'
$ink2 = Ink-Box $m2 $scan[0] $scan[1] $scan[2] $scan[3] (Bars $ov[0])
$m2.Dispose()
"after Ctrl+Z: ink $(if ($ink2) { "$($ink2.n) red px" } else { 'none' })"
if ($ink2) { $fail += "Ctrl+Z brought the reset shape back ($($ink2.n) red px)" }

[void][System.Windows.Forms.SendKeys]::SendWait('{ESC}')
Start-Sleep -Milliseconds 400
if (-not $proc.HasExited) { $proc.Kill() }
if ($fail.Count) { "FAILURES: $($fail.Count)"; $fail | ForEach-Object { "  $_" }; exit 1 }
'PASS'
