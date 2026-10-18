# Drawing a shape with the pointer outside the 选区 used to keep growing the
# shape out where nothing of it would be exported. The request is that the shape
# stops at the last position the pointer had while still inside, and starts
# following it again the moment the pointer comes back — all in one press, with
# releasing outside ending the drag rather than losing the shape.
#
# So: press inside, walk far past the bottom-right corner, measure, walk back
# inside without releasing, measure again. The first measure has to be inside the
# frame and far along the path; the second has to be back at the new inside
# position rather than still at the frozen one.
Add-Type -AssemblyName System.Drawing, System.Windows.Forms
Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class DF {
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
function Down { [void][DF]::mouse_event($LEFTDOWN, 0, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 150 }
function Up { [void][DF]::mouse_event($LEFTUP, 0, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 350 }
# A real drag arrives as a stream of moves a pixel or two apart; a coarse one
# stops a whole step short of wherever it was heading and proves less.
function Walk([int]$x1, [int]$y1, [int]$x2, [int]$y2, [int]$steps) {
    for ($i = 1; $i -le $steps; $i++) {
        MoveTo ([int]($x1 + ($x2-$x1) * $i / $steps)) ([int]($y1 + ($y2-$y1) * $i / $steps))
    }
}
function Find-Wins([string]$title) {
    $found = New-Object System.Collections.ArrayList
    $cb = [DF+EnumProc] {
        param($h, $l)
        $t = New-Object System.Text.StringBuilder 256
        [void][DF]::GetWindowText($h, $t, 256)
        if ($t.ToString() -eq $title) { [void]$found.Add($h) }
        return $true
    }
    [void][DF]::EnumWindows($cb, [IntPtr]::Zero)
    return $found.ToArray()
}
function Find-Kids([IntPtr]$parent, [string]$title) {
    $found = New-Object System.Collections.ArrayList
    $cb = [DF+EnumProc] {
        param($h, $l)
        $t = New-Object System.Text.StringBuilder 256
        [void][DF]::GetWindowText($h, $t, 256)
        if ($t.ToString() -eq $title -and [DF]::IsWindowVisible($h)) { [void]$found.Add($h) }
        return $true
    }
    [void][DF]::EnumChildWindows($parent, $cb, [IntPtr]::Zero)
    return $found.ToArray()
}
function Rect-Of([IntPtr]$h) {
    $r = New-Object DF+RECT
    [void][DF]::GetWindowRect($h, [ref]$r)
    return $r
}
function IsRed($c) { return ($c.R -gt 190 -and $c.G -lt 120 -and $c.B -lt 130) }
# ClearType puts single red pixels along desktop text, so a pixel only counts as
# ink with red on both sides of it. The span has to stay inside the stroke: the
# default width is the middle dot now, 4px, so 3px either way falls off the edge
# of it and the whole shape reads as gone.
function Solid($bmp, [int]$x, [int]$y) {
    foreach ($d in @(-1, 1)) {
        if (-not (IsRed ($bmp.GetPixel($x + $d, $y)))) { return $false }
        if (-not (IsRed ($bmp.GetPixel($x, $y + $d)))) { return $false }
    }
    return $true
}
function In-Bars([int]$x, [int]$y, $bars) {
    foreach ($b2 in $bars) {
        if ($x -ge $b2.left -and $x -lt $b2.right -and
            $y -ge $b2.top -and $y -lt $b2.bottom) { return $true }
    }
    return $false
}
# $skip is the toolbar and the 粗细/颜色 bar: they are child windows painted over
# the overlay, and the bar's colour palette holds a red swatch a few rows below
# the frame's bottom edge, which would otherwise read as ink that crossed it.
function Ink-Box($bmp, [int]$x0, [int]$y0, [int]$x1, [int]$y1, $skip = @()) {
    $l = -1; $t = -1; $r = -1; $b = -1; $n = 0
    for ($y = $y0; $y -le $y1; $y++) {
        for ($x = $x0; $x -le $x1; $x++) {
            if (In-Bars $x $y $skip) { continue }
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
# The stroke reaches half its width past the shape's own corners and the solid-ink
# test pulls the measured box back in by a pixel, so the corner lands within a
# couple of px of where the pointer left off; the walk steps are 27px apart.
$TOL = 24
$fail = @()

MoveTo 3000 1900
Start-Sleep -Milliseconds 400
Get-Process winshot -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 600
$proc = Start-Process -FilePath 'D:\Project\winshot\x64\Debug\winshot.exe' -PassThru
Start-Sleep -Seconds 2

$sink = @(Find-Wins 'WinShotSink')
if ($sink.Count -eq 0) { 'FAIL: no sink window'; exit 1 }
[void][DF]::PostMessage($sink[0], 0x8002, [IntPtr]::Zero, [IntPtr]::Zero)
Start-Sleep -Seconds 2

MoveTo $sel[0] $sel[1]; Down; Walk $sel[0] $sel[1] $sel[2] $sel[3] 24; Up
$ov = @(Find-Wins 'WinShotOverlay')
if ($ov.Count -eq 0) { 'FAIL: no overlay window'; exit 1 }

$t = @(Find-Kids $ov[0] 'WinShotToolbar')
if ($t.Count -eq 0) { 'FAIL: no toolbar'; exit 1 }
$tr = Rect-Of $t[0]
$s = ($tr.bottom - $tr.top) / 32.0
$cell = [int][Math]::Round(27 * $s); $pad = [int][Math]::Round(4 * $s)
MoveTo ($tr.left + $pad + [int]($cell / 2)) ([int](($tr.top + $tr.bottom) / 2))
Down; Up    # slot 0: the rectangle tool, which opens the 粗细/颜色 bar
$pb = @(Find-Kids $ov[0] 'WinShotPropBar')
if ($pb.Count -eq 0) {
    'FAIL: arming the rectangle tool did not open the property bar'; exit 1
}
# Both bars hang below the frame and are opaque over the overlay, so the ink scan
# has to look past them.
$bars = @(Rect-Of $t[0]) + @(Rect-Of $pb[0])

# --- one press: inside, far outside, back inside, released outside ------------
MoveTo 1000 700
Down
Walk 1000 700 2600 1900 60
$a = Grab 'D:\Project\winshot\obj\freeze_out.png'
$ia = Ink-Box $a 950 650 1560 1110 $bars
$a.Dispose()
if (-not $ia) {
    $fail += 'the shape disappeared while the pointer was outside the 选区'
} else {
    "while the pointer was at 2600,1900: ink $($ia.l),$($ia.t) .. $($ia.r),$($ia.b)"
    "  frame right=$($sel[2]) bottom=$($sel[3])"
    if ($ia.r -gt $sel[2] + $TOL) {
        $fail += "the shape reached x=$($ia.r) while the pointer was outside, past the frame at $($sel[2])"
    }
    if ($ia.b -gt $sel[3] + $TOL) {
        $fail += "the shape reached y=$($ia.b) while the pointer was outside, past the frame at $($sel[3])"
    }
    # It has to have followed the pointer to the frame rather than stopped at the
    # start: the path leaves the region near (1467,1050).
    if ($ia.r -lt 1350) { $fail += "the shape only reached x=$($ia.r); it stopped instead of following the pointer to the frame" }
    if ($ia.b -lt 950) { $fail += "the shape only reached y=$($ia.b); it stopped instead of following the pointer to the frame" }
}

Walk 2600 1900 1200 900 40
$b = Grab 'D:\Project\winshot\obj\freeze_back.png'
$ib = Ink-Box $b 950 650 1560 1110 $bars
$b.Dispose()
if (-not $ib) {
    $fail += 'the shape was gone after the pointer came back inside'
} else {
    "after coming back to 1200,900: ink $($ib.l),$($ib.t) .. $($ib.r),$($ib.b)"
    # The request: back inside, the newest inside position drives the shape
    # again, so the corner is at 1200,900 and not still at the frozen one.
    if ([Math]::Abs($ib.r - 1200) -gt $TOL) {
        $fail += "the shape's right edge is at $($ib.r) after the pointer returned to 1200, want 1200"
    }
    if ([Math]::Abs($ib.b - 900) -gt $TOL) {
        $fail += "the shape's bottom edge is at $($ib.b) after the pointer returned to 1200,900, want 900"
    }
}

# Released outside the frame the drag still ends: the shape is kept, not lost.
Walk 1200 900 2400 1800 40
Up
$c = Grab 'D:\Project\winshot\obj\freeze_drop.png'
$ic = Ink-Box $c 950 650 1560 1110 $bars
$c.Dispose()
if (-not $ic) {
    $fail += 'releasing outside the 选区 threw the shape away'
} else {
    "after releasing at 2400,1800: ink $($ic.l),$($ic.t) .. $($ic.r),$($ic.b)"
    if ($ic.r -gt $sel[2] + $TOL -or $ic.b -gt $sel[3] + $TOL) {
        $fail += "releasing outside let the shape reach $($ic.r),$($ic.b), past the frame at $($sel[2]),$($sel[3])"
    }
}

[void][System.Windows.Forms.SendKeys]::SendWait('{ESC}')
Start-Sleep -Milliseconds 400
if (-not $proc.HasExited) { $proc.Kill() }
if ($fail.Count) { "FAILURES: $($fail.Count)"; $fail | ForEach-Object { "  $_" }; exit 1 }
'PASS'
