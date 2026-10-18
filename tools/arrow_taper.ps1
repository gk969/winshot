# The arrow used to be a line of one width with a triangle on the end. The
# request is a shaft that starts 2px wide at the tail and opens to the width the
# user picked by the time it reaches the head, and anti-aliasing on the curves
# and diagonals -- ellipses, arrows, pen strokes -- which the reference has and
# this app never did.
#
# A 45 degree arrow makes the width easy to read: a vertical scan across the
# shaft catches 1.41x the perpendicular width wherever it runs. The head is 21px
# long at the default width, so the scan near it stops 10px short of the tip and
# is still on the shaft. Anti-aliasing is proved by the half-covered edge pixels
# along a diagonal: a hard-edged line has none of them. Each window is counted
# twice, before the shape lands in it and after, so whatever reddish text the
# frozen desktop happens to show there cancels out of the difference.
Add-Type -AssemblyName System.Drawing, System.Windows.Forms
Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class AT {
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
function Down { [void][AT]::mouse_event($LEFTDOWN, 0, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 150 }
function Up { [void][AT]::mouse_event($LEFTUP, 0, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 350 }
function Walk([int]$x1, [int]$y1, [int]$x2, [int]$y2, [int]$steps) {
    for ($i = 1; $i -le $steps; $i++) {
        MoveTo ([int]($x1 + ($x2-$x1) * $i / $steps)) ([int]($y1 + ($y2-$y1) * $i / $steps))
    }
}
function Drag([int]$x1, [int]$y1, [int]$x2, [int]$y2) {
    MoveTo $x1 $y1; Down; Walk $x1 $y1 $x2 $y2 24; Up
}
function Find-Wins([string]$title) {
    $found = New-Object System.Collections.ArrayList
    $cb = [AT+EnumProc] {
        param($h, $l)
        $t = New-Object System.Text.StringBuilder 256
        [void][AT]::GetWindowText($h, $t, 256)
        if ($t.ToString() -eq $title) { [void]$found.Add($h) }
        return $true
    }
    [void][AT]::EnumWindows($cb, [IntPtr]::Zero)
    return $found.ToArray()
}
function Find-Kids([IntPtr]$parent, [string]$title) {
    $found = New-Object System.Collections.ArrayList
    $cb = [AT+EnumProc] {
        param($h, $l)
        $t = New-Object System.Text.StringBuilder 256
        [void][AT]::GetWindowText($h, $t, 256)
        if ($t.ToString() -eq $title -and [AT]::IsWindowVisible($h)) { [void]$found.Add($h) }
        return $true
    }
    [void][AT]::EnumChildWindows($parent, $cb, [IntPtr]::Zero)
    return $found.ToArray()
}
function Rect-Of([IntPtr]$h) {
    $r = New-Object AT+RECT
    [void][AT]::GetWindowRect($h, [ref]$r)
    return $r
}
# annot::kSel is (250,55,58): a fully covered pixel is that, an anti-aliased edge
# pixel is it blended with whatever the frozen desktop shows there. ClearType puts
# reddish pixels along desktop text too, so the anti-aliasing counts are taken as
# a difference against the same window before the shape was drawn.
function IsFull($c) { return ($c.R -gt 190 -and $c.G -lt 120 -and $c.B -lt 130) }
function IsPart($c) {
    return ($c.R -gt 110 -and $c.R -le 235 -and
            ($c.R - [Math]::Max($c.G, $c.B)) -gt 50)
}
# Longest run of fully covered ink down a column: 1.41x the shaft's perpendicular
# width at 45 degrees.
function ColRun($bmp, [int]$x, [int]$y0, [int]$y1) {
    $best = 0; $run = 0
    for ($y = $y0; $y -le $y1; $y++) {
        if (IsFull ($bmp.GetPixel($x, $y))) {
            $run++; if ($run -gt $best) { $best = $run }
        } else { $run = 0 }
    }
    return $best
}
function PartCount($bmp, [int]$x0, [int]$y0, [int]$x1, [int]$y1) {
    $n = 0
    for ($y = $y0; $y -le $y1; $y++) {
        for ($x = $x0; $x -le $x1; $x++) { if (IsPart ($bmp.GetPixel($x, $y))) { $n++ } }
    }
    return $n
}
function Click([int]$x, [int]$y) { MoveTo $x $y; Down; Up }
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
[void][AT]::PostMessage($sink[0], 0x8002, [IntPtr]::Zero, [IntPtr]::Zero)
Start-Sleep -Seconds 2
$ov = @(Find-Wins 'WinShotOverlay')
if ($ov.Count -eq 0) { 'FAIL: no overlay window'; exit 1 }

Drag $sel[0] $sel[1] $sel[2] $sel[3]

# The two windows the anti-aliasing is read in, before anything is drawn in them:
# the middle of where the shaft will run, and the upper-left quarter of where the
# ellipse will run. Both stay clear of the selection rings and the 1px guide box
# that sit on a selected shape's bounding box.
$aw = @(1090, 790, 1210, 910)
$ew = @(1040, 1105, 1120, 1180)
$pre = Grab 'D:\Project\winshot\obj\taper_pre.png'
$baseA = PartCount $pre $aw[0] $aw[1] $aw[2] $aw[3]
$baseE = PartCount $pre $ew[0] $ew[1] $ew[2] $ew[3]
$pre.Dispose()
"before drawing: arrow window $baseA reddish px, ellipse window $baseE"

# --- a 45 degree arrow, tail at 1000,700 and tip at 1300,1000 ----------------
$p = Slot 2
if (-not $p) { 'FAIL: no toolbar'; exit 1 }
Click $p[0] $p[1]              # the arrow tool
Drag 1000 700 1300 1000
Click $p[0] $p[1]              # disarm, so the selection rings are the only extra

$a = Grab 'D:\Project\winshot\obj\taper_arrow.png'
# x=1010 is 14px along the shaft, x=1275 is 390px along its 403px length and 10px
# before the head starts. Expected vertical runs: 2.1 * 1.41 = 3 and 3.9 * 1.41 = 5.6.
$tail = ColRun $a 1010 690 730
$neck = ColRun $a 1275 955 995
"shaft width: tail column $tail px, neck column $neck px (want 1..3 and 4..8)"
if ($tail -lt 1 -or $tail -gt 3) { $fail += "the tail is $tail px wide, want about 2" }
if ($neck -lt 4 -or $neck -gt 8) { $fail += "the shaft at the head is $neck px wide, want about 4" }
if ($neck - $tail -lt 2) { $fail += "the shaft only widened from $tail to $neck px: no taper" }

$aaArrow = PartCount $a $aw[0] $aw[1] $aw[2] $aw[3]
$a.Dispose()
$gainA = $aaArrow - $baseA
"anti-aliasing along the shaft: $aaArrow reddish px, was $baseA -> +$gainA (want > 100)"
if ($gainA -lt 100) { $fail += "the arrow's diagonal added no anti-aliased edge pixels (+$gainA)" }

# --- an ellipse, for the same claim about curves -----------------------------
$p = Slot 1
Click $p[0] $p[1]              # the ellipse tool
Drag 1000 1100 1400 1300
Click $p[0] $p[1]

$b = Grab 'D:\Project\winshot\obj\taper_ellipse.png'
$aaEll = PartCount $b $ew[0] $ew[1] $ew[2] $ew[3]
$b.Dispose()
$gainE = $aaEll - $baseE
"anti-aliasing along the ellipse: $aaEll reddish px, was $baseE -> +$gainE (want > 60)"
if ($gainE -lt 60) { $fail += "the ellipse's curve added no anti-aliased edge pixels (+$gainE)" }

[void][System.Windows.Forms.SendKeys]::SendWait('{ESC}')
Start-Sleep -Milliseconds 400
if (-not $proc.HasExited) { $proc.Kill() }
if ($fail.Count) { "FAILURES: $($fail.Count)"; $fail | ForEach-Object { "  $_" }; exit 1 }
'PASS'
