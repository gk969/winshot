# The width/colour bar used to open on the widest dot. The request is that every
# tool starts on the middle one (4px) with the red swatch picked, so the first
# shape drawn is the one the reference shows without the user touching anything.
#
# Three things have to agree: the frame in the bar sits around the middle dot, the
# large current-colour swatch is red, and the stroke actually drawn is 4px.
Add-Type -AssemblyName System.Drawing, System.Windows.Forms
Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class PD {
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
    Start-Sleep -Milliseconds 90
}
function Down { [void][PD]::mouse_event($LEFTDOWN, 0, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 150 }
function Up { [void][PD]::mouse_event($LEFTUP, 0, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 350 }
function Walk([int]$x1, [int]$y1, [int]$x2, [int]$y2, [int]$steps) {
    for ($i = 1; $i -le $steps; $i++) {
        MoveTo ([int]($x1 + ($x2-$x1) * $i / $steps)) ([int]($y1 + ($y2-$y1) * $i / $steps))
    }
}
function Drag([int]$x1, [int]$y1, [int]$x2, [int]$y2) {
    MoveTo $x1 $y1; Down; Walk $x1 $y1 $x2 $y2 20; Up
}
function Find-Wins([string]$title) {
    $found = New-Object System.Collections.ArrayList
    $cb = [PD+EnumProc] {
        param($h, $l)
        $t = New-Object System.Text.StringBuilder 256
        [void][PD]::GetWindowText($h, $t, 256)
        if ($t.ToString() -eq $title) { [void]$found.Add($h) }
        return $true
    }
    [void][PD]::EnumWindows($cb, [IntPtr]::Zero)
    return $found.ToArray()
}
function Find-Kids([IntPtr]$parent, [string]$title) {
    $found = New-Object System.Collections.ArrayList
    $cb = [PD+EnumProc] {
        param($h, $l)
        $t = New-Object System.Text.StringBuilder 256
        [void][PD]::GetWindowText($h, $t, 256)
        if ($t.ToString() -eq $title -and [PD]::IsWindowVisible($h)) { [void]$found.Add($h) }
        return $true
    }
    [void][PD]::EnumChildWindows($parent, $cb, [IntPtr]::Zero)
    return $found.ToArray()
}
function Rect-Of([IntPtr]$h) {
    $r = New-Object PD+RECT
    [void][PD]::GetWindowRect($h, [ref]$r)
    return $r
}
function IsRed($c) { return ($c.R -gt 190 -and $c.G -lt 120 -and $c.B -lt 130) }
function Near($c, [int]$r, [int]$g, [int]$b, [int]$tol) {
    return ([Math]::Abs($c.R - $r) -le $tol -and [Math]::Abs($c.G - $g) -le $tol -and
            [Math]::Abs($c.B - $b) -le $tol)
}
# The frame the bar paints around the selected width dot: kActive is 8% black over
# the kBack bar face, which composites to (216,220,224) against (235,239,243).
function IsFrameFill($c) { return (Near $c 216 220 224 6) }
function FrameFill-In($bmp, $bar, [int]$dot) {
    # Dot centres are at bar x + 13 + i * 25, and the frame is 24px square centred
    # in the bar's height.
    $cx = $bar.left + 13 + $dot * 25
    $h = $bar.bottom - $bar.top
    $fy = $bar.top + [int](($h - 24) / 2)
    $n = 0
    for ($y = $fy + 2; $y -le $fy + 21; $y++) {
        for ($x = $cx - 10; $x -le $cx + 10; $x++) {
            if (IsFrameFill ($bmp.GetPixel($x, $y))) { $n++ }
        }
    }
    return $n
}
function RedCount($bmp, [int]$x0, [int]$y0, [int]$x1, [int]$y1) {
    $n = 0
    for ($y = $y0; $y -le $y1; $y++) {
        for ($x = $x0; $x -le $x1; $x++) { if (IsRed ($bmp.GetPixel($x, $y))) { $n++ } }
    }
    return $n
}
# Consecutive red pixels crossing the rect's left edge on a row through its middle:
# that run is the stroke width.
function StrokeWidth($bmp, [int]$y, [int]$x0, [int]$x1) {
    $best = 0; $run = 0
    for ($x = $x0; $x -le $x1; $x++) {
        if (IsRed ($bmp.GetPixel($x, $y))) { $run++; if ($run -gt $best) { $best = $run } }
        else { $run = 0 }
    }
    return $best
}

$sel = @(800, 600, 1500, 1000)
$fail = @()

MoveTo 3000 1900
Start-Sleep -Milliseconds 400
Get-Process winshot -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 600
$proc = Start-Process -FilePath 'D:\Project\winshot\x64\Debug\winshot.exe' -PassThru
Start-Sleep -Seconds 2

$sink = @(Find-Wins 'WinShotSink')
if ($sink.Count -eq 0) { 'FAIL: no sink window'; exit 1 }
[void][PD]::PostMessage($sink[0], 0x8002, [IntPtr]::Zero, [IntPtr]::Zero)
Start-Sleep -Seconds 2

Drag $sel[0] $sel[1] $sel[2] $sel[3]
$ov = @(Find-Wins 'WinShotOverlay')
if ($ov.Count -eq 0) { 'FAIL: no overlay window'; exit 1 }
$t = @(Find-Kids $ov[0] 'WinShotToolbar')
if ($t.Count -eq 0) { 'FAIL: no toolbar'; exit 1 }
$tr = Rect-Of $t[0]
$s = ($tr.bottom - $tr.top) / 32.0
$cell = [int][Math]::Round(27 * $s); $pad = [int][Math]::Round(4 * $s)
function Slot([int]$i) {
    return @(($tr.left + $pad + [int]($cell / 2) + $i * $cell),
             [int](($tr.top + $tr.bottom) / 2))
}

# --- arm the rectangle tool: the bar opens on its defaults -------------------
$p = Slot 0
MoveTo $p[0] $p[1]; Down; Up
$pb = @(Find-Kids $ov[0] 'WinShotPropBar')
if ($pb.Count -eq 0) { 'FAIL: arming the rectangle tool opened no property bar'; exit 1 }
$bar = Rect-Of $pb[0]
$bmp = Grab 'D:\Project\winshot\obj\prop_default_bar.png'
$fill = @(0, 1, 2) | ForEach-Object { FrameFill-In $bmp $bar $_ }
# Array.IndexOf returns -1 here whatever the boxed element type is; the argmax is
# three lines of its own and says the same thing.
$b = 0
for ($i = 1; $i -le 2; $i++) { if ($fill[$i] -gt $fill[$b]) { $b = $i } }
"width-dot frame fill counts: dot0=$($fill[0]) dot1=$($fill[1]) dot2=$($fill[2]) -> selected $b (want 1)"
if ($b -ne 1) { $fail += "the width frame is on dot $b, want the middle one" }
if ($fill[1] -lt 150) { $fail += "the middle dot has no frame (fill=$($fill[1]))" }

# The large current-colour swatch at the head of the palette: 26px square at bar
# x + 85, y + 5.
$sw = RedCount $bmp ($bar.left + 86) ($bar.top + 6) ($bar.left + 110) ($bar.top + 30)
"current-colour swatch: $sw red px of 625 (want > 500)"
if ($sw -lt 500) { $fail += "the current colour is not red (swatch=$sw)" }
[void]($bmp.Dispose())

# --- and the stroke actually drawn is the middle width -----------------------
Drag 1000 700 1250 880
$c = Grab 'D:\Project\winshot\obj\prop_default_rect.png'
$w = StrokeWidth $c 790 985 1015
"rect left-edge stroke width: $w px (want 3..6)"
if ($w -lt 3 -or $w -gt 6) { $fail += "the drawn stroke is $w px, want the middle dot's 4px" }
$ink = RedCount $c 995 695 1255 885
"rect ink: $ink red px (want > 1500)"
if ($ink -lt 1500) { $fail += "the rect ink is missing ($ink)" }
[void]($c.Dispose())

[void][System.Windows.Forms.SendKeys]::SendWait('{ESC}')
Start-Sleep -Milliseconds 400
if (-not $proc.HasExited) { $proc.Kill() }
if ($fail.Count) { "FAILURES: $($fail.Count)"; $fail | ForEach-Object { "  $_" }; exit 1 }
'PASS'
