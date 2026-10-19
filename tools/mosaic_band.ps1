# The 马赛克 band was twice the 粗细 dot, so the widest setting drew a 16px stripe
# against 18px text and the tool could not cover the thing it exists to hide. The
# request is for every step to be twice as wide again: `MosaicBandForPen` is now
# four times the dot, so the three dots 2/4/8 draw bands 8/16/32 px across.
#
# A band is measured by what it changes, not by what it draws: it fills itself with
# the canvas averaged into squares, so over content that varies inside one square
# every pixel it covers differs from the same pixel before it was drawn, and every
# pixel it does not cover is identical. Two grabs either side of the drag, and the
# run of differing pixels along a row through the band is its diameter.
#
# The content is two pen strokes at their widest: one horizontal line through the
# band's middle and one vertical line under it. The 12px default block cannot fit
# inside an 8px stroke, so every square the band covers straddles ink and desktop
# and the change is unambiguous right out to the band's edge. The horizontal line
# gives the width, the vertical one the height, and the height less the length of
# the drag is the same diameter read the other way.
Add-Type -AssemblyName System.Drawing, System.Windows.Forms
Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class MB {
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
# without error once Windows starts flagging the script's process "(未响应)".
# The inverse of the driver's 0..65535 mapping onto pixels 0..(width-1).
function MoveTo([int]$x, [int]$y) {
    [void][MB]::mouse_event(0x8001, [uint32][int][Math]::Round(65535 * $x / 3839),
                            [uint32][int][Math]::Round(65535 * $y / 2159), 0,
                            [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 90
}
function Down { [void][MB]::mouse_event($LEFTDOWN, 0, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 150 }
function Up { [void][MB]::mouse_event($LEFTUP, 0, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 350 }
function Walk([int]$x1, [int]$y1, [int]$x2, [int]$y2, [int]$steps) {
    for ($i = 1; $i -le $steps; $i++) {
        MoveTo ([int]($x1 + ($x2-$x1) * $i / $steps)) ([int]($y1 + ($y2-$y1) * $i / $steps))
    }
}
function Drag([int]$x1, [int]$y1, [int]$x2, [int]$y2) {
    MoveTo $x1 $y1; Down; Walk $x1 $y1 $x2 $y2 20; Up
}
function Click([int]$x, [int]$y) { MoveTo $x $y; Down; Up }
# Not `Type`: that is the built-in alias for Get-Content, and an alias beats a
# function, so a function of that name is never called.
function Keys([string]$s) { [void][System.Windows.Forms.SendKeys]::SendWait($s) }
function Find-Wins([string]$title) {
    $found = New-Object System.Collections.ArrayList
    $cb = [MB+EnumProc] {
        param($h, $l)
        $t = New-Object System.Text.StringBuilder 256
        [void][MB]::GetWindowText($h, $t, 256)
        if ($t.ToString() -eq $title) { [void]$found.Add($h) }
        return $true
    }
    [void][MB]::EnumWindows($cb, [IntPtr]::Zero)
    return $found.ToArray()
}
function Find-Kids([IntPtr]$parent, [string]$title) {
    $found = New-Object System.Collections.ArrayList
    $cb = [MB+EnumProc] {
        param($h, $l)
        $t = New-Object System.Text.StringBuilder 256
        [void][MB]::GetWindowText($h, $t, 256)
        if ($t.ToString() -eq $title -and [MB]::IsWindowVisible($h)) { [void]$found.Add($h) }
        return $true
    }
    [void][MB]::EnumChildWindows($parent, $cb, [IntPtr]::Zero)
    return $found.ToArray()
}
function Rect-Of([IntPtr]$h) {
    $r = New-Object MB+RECT
    [void][MB]::GetWindowRect($h, [ref]$r)
    return $r
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
function Width-Dot([int]$i) {
    $pb = @(Find-Kids $ov[0] 'WinShotPropBar')
    if ($pb.Count -eq 0) { return $null }
    $b = Rect-Of $pb[0]
    $s = ($b.bottom - $b.top) / 37.0
    return @(($b.left + [Math]::Round(13 * $s) + $i * [Math]::Round(25 * $s)),
             [int](($b.top + $b.bottom) / 2))
}
# A pixel the band rewrote: the averaged square it sits in differs from the plain
# canvas by far more than any dithering could, but the band's own edge is
# anti-aliased and lands on a partial pixel, so the threshold sits low.
function Changed($a, $b, [int]$x, [int]$y) {
    $c1 = $a.GetPixel($x, $y); $c2 = $b.GetPixel($x, $y)
    return ([Math]::Abs($c1.R - $c2.R) + [Math]::Abs($c1.G - $c2.G) +
            [Math]::Abs($c1.B - $c2.B)) -gt 24
}
# Longest run of rewritten pixels along one row, and the same down one column,
# each searched over the few rows or columns around the reference stroke in case
# the drag landed a pixel off its middle.
function Run-Along-Row($a, $b, [int]$cy, [int]$x0, [int]$x1) {
    $best = 0; $bestY = $cy; $bestL = 0; $bestR = 0
    for ($y = $cy - 4; $y -le $cy + 4; $y++) {
        $run = 0; $l = -1; $r = -1
        for ($x = $x0; $x -le $x1; $x++) {
            if (Changed $a $b $x $y) { if ($l -lt 0) { $l = $x }; $r = $x; $run++ }
            else { $run = 0 }
        }
        if ($l -ge 0 -and ($r - $l + 1) -gt $best) { $best = $r - $l + 1; $bestY = $y; $bestL = $l; $bestR = $r }
    }
    return @{ n = $best; y = $bestY; l = $bestL; r = $bestR }
}
function Run-Down-Col($a, $b, [int]$cx, [int]$y0, [int]$y1) {
    $best = 0; $bestT = 0; $bestB = 0
    for ($x = $cx - 4; $x -le $cx + 4; $x++) {
        $t = -1; $bt = 0
        for ($y = $y0; $y -le $y1; $y++) {
            if (Changed $a $b $x $y) { if ($t -lt 0) { $t = $y }; $bt = $y }
            else { if ($t -ge 0 -and ($bt - $t + 1) -gt $best) {
                       $best = $bt - $t + 1; $bestT = $t; $bestB = $bt }
                   $t = -1 }
        }
        if ($t -ge 0 -and ($bt - $t + 1) -gt $best) { $best = $bt - $t + 1; $bestT = $t; $bestB = $bt }
    }
    return @{ n = $best; t = $bestT; b = $bestB }
}
# Pixels the band should not have touched: a strip well clear of its edge.
function Changed-Outside($a, $b, [int]$x0, [int]$y0, [int]$x1, [int]$y1) {
    $n = 0
    for ($y = $y0; $y -le $y1; $y++) {
        for ($x = $x0; $x -le $x1; $x++) { if (Changed $a $b $x $y) { $n++ } }
    }
    return $n
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
[void][MB]::PostMessage($sink[0], 0x8002, [IntPtr]::Zero, [IntPtr]::Zero)
Start-Sleep -Seconds 2
$ov = @(Find-Wins 'WinShotOverlay')
if ($ov.Count -eq 0) { 'FAIL: no overlay window'; exit 1 }

Drag 700 500 2200 1500
$pen = Slot 3
$mos = Slot 4
if (-not $pen -or -not $mos) { 'FAIL: no toolbar'; exit 1 }

# --- the content the band has to average ------------------------------------
# Widest dot first: an 8px stroke is wider than any square the 模糊度 rail offers
# below its top end, which is what makes every covered square straddle two colours.
Click $pen[0] $pen[1]
$d2 = Width-Dot 2
if (-not $d2) { 'FAIL: no property bar with the width dots'; exit 1 }
Click $d2[0] $d2[1]
Start-Sleep -Milliseconds 300
$lineY = 850
$bandX = @(1000, 1300, 1600)
$bandY0 = 700; $bandY1 = 1000
Drag 880 $lineY 1720 $lineY
foreach ($x in $bandX) { Drag $x ($bandY0 - 20) $x ($bandY1 + 20) }
Click $pen[0] $pen[1]              # disarm, so the next clicks land on the canvas

MoveTo 2300 1800; Start-Sleep -Milliseconds 500
$before = Grab 'D:\Project\winshot\obj\mb_before.png'

# --- one band per width dot --------------------------------------------------
# 马赛克 keeps its own width index (each tool remembers the last one picked), so
# the dots have to be clicked on the mosaic bar itself. It keeps them: only the
# colour swatch and palette are swapped for the 模糊度 rail. The tool stays armed
# between drags, so it is clicked once here.
Click $mos[0] $mos[1]
Start-Sleep -Milliseconds 300
$wide = @(0, 0, 0); $tall = @(0, 0, 0); $outside = @(0, 0, 0)
for ($i = 0; $i -le 2; $i++) {
    $x = $bandX[$i]
    $d = Width-Dot $i
    if (-not $d) { 'FAIL: the width dots went away'; exit 1 }
    Click $d[0] $d[1]
    Start-Sleep -Milliseconds 300
    Drag $x $bandY0 $x $bandY1
    MoveTo 2300 1800; Start-Sleep -Milliseconds 600
    $after = Grab ("D:\Project\winshot\obj\mb_band{0}.png" -f $i)

    $w = Run-Along-Row $before $after $lineY ($x - 60) ($x + 60)
    $h = Run-Down-Col $before $after $x ($bandY0 - 30) ($bandY1 + 30)
    $wide[$i] = $w.n
    $tall[$i] = $h.n - ($bandY1 - $bandY0)
    # 40..70px left of the centre: past the widest band's edge, inside the region.
    $outside[$i] = Changed-Outside $before $after ($x - 70) ($bandY0 + 40) ($x - 40) ($bandY1 - 40)
    $after.Dispose()
    "width dot $i at x=${x}: band $($w.n) px across (row $($w.y), x $($w.l)..$($w.r)), " +
        "$($h.n) px down so $($tall[$i]) px of diameter, $($outside[$i]) changed px outside"
}
$before.Dispose()

"band diameters: $($wide -join ' / ') px across, $($tall -join ' / ') px down the drag (want 8 / 16 / 32)"
for ($i = 0; $i -le 2; $i++) {
    $want = @(8, 16, 32)[$i]
    if ([Math]::Abs($wide[$i] - $want) -gt 3) {
        $fail += "the band at width dot $i is $($wide[$i]) px across, want about ${want}"
    }
    if ([Math]::Abs($tall[$i] - $want) -gt 3) {
        $fail += "the band at width dot $i is $($tall[$i]) px wider than the drag's own length, want about ${want}"
    }
    if ($outside[$i] -gt 40) {
        $fail += "the band at width dot $i rewrote $($outside[$i]) px 40..70 px clear of its edge"
    }
}
if (-not ($wide[0] -lt $wide[1] -and $wide[1] -lt $wide[2])) {
    $fail += "the bands do not grow with the width dot: $($wide -join ', ')"
}

Keys '{ESC}'
Start-Sleep -Milliseconds 400
if (-not $proc.HasExited) { $proc.Kill() }
if ($fail.Count) { "FAILURES: $($fail.Count)"; $fail | ForEach-Object { "  $_" }; exit 1 }
'PASS'
