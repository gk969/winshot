# A selected element has to follow the property bar: pick a colour and the shape
# changes colour, pick a width and its stroke changes thickness. Before the fix
# the bar only edited the style for shapes drawn next.
#
# The rect is drawn with the defaults (palette index 10 = red, widest dot = 8px),
# so the target colour is yellow (index 11), which no other pixel in either bar
# is, and the target width is the first dot. Both are found by scanning the bar
# rather than by trusting the layout constants.
Add-Type -AssemblyName System.Drawing, System.Windows.Forms
Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class ST {
    public delegate bool EnumProc(IntPtr h, IntPtr l);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
    [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint msg, IntPtr w, IntPtr l);
    [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint dx, uint dy, uint d, UIntPtr e);
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
function Drag([int]$x1, [int]$y1, [int]$x2, [int]$y2) {
    MoveTo $x1 $y1
    [void][ST]::mouse_event($LEFTDOWN, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 120
    for ($i = 1; $i -le 12; $i++) {
        MoveTo ([int]($x1 + ($x2-$x1) * $i / 12)) ([int]($y1 + ($y2-$y1) * $i / 12))
    }
    Start-Sleep -Milliseconds 150
    [void][ST]::mouse_event($LEFTUP, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 300
}
function Click([int]$x, [int]$y) {
    MoveTo $x $y
    [void][ST]::mouse_event($LEFTDOWN, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 120
    [void][ST]::mouse_event($LEFTUP, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 350
}
function IsBack($c) {
    return ([Math]::Abs($c.R - 235) -le 8 -and [Math]::Abs($c.G - 239) -le 8 -and
            [Math]::Abs($c.B - 243) -le 8)
}
# Light-chrome bands down a column: the first is the toolbar, the second the
# property bar.
function Bands($bmp, [int]$x, [int]$y0, [int]$y1) {
    $out = @(); $cur = $null
    for ($y = $y0; $y -le $y1; $y++) {
        if (IsBack ($bmp.GetPixel($x, $y))) {
            if ($null -eq $cur) { $cur = @($y, $y) } else { $cur[1] = $y }
        } elseif ($null -ne $cur) {
            if ($cur[1] - $cur[0] -ge 8) { $out += , $cur }
            $cur = $null
        }
    }
    if ($null -ne $cur -and $cur[1] - $cur[0] -ge 8) { $out += , $cur }
    return $out
}
function IsRed($c)    { return ($c.R -gt 190 -and $c.G -lt 120 -and $c.B -lt 130) }
function IsYellow($c) { return ($c.R -gt 200 -and $c.G -gt 200 -and $c.B -lt 120) }
function Ink-Box($bmp, [int]$x0, [int]$y0, [int]$x1, [int]$y1, [bool]$yellow) {
    $l = -1; $t = -1; $r = -1; $b = -1; $n = 0
    for ($y = $y0; $y -le $y1; $y++) {
        for ($x = $x0; $x -le $x1; $x++) {
            $c = $bmp.GetPixel($x, $y)
            $hit = if ($yellow) { IsYellow $c } else { IsRed $c }
            if ($hit) {
                $n++
                if ($l -lt 0 -or $x -lt $l) { $l = $x }
                if ($x -gt $r) { $r = $x }
                if ($t -lt 0) { $t = $y }
                $b = $y
            }
        }
    }
    if ($l -lt 0) { return $null }
    return @{ l = $l; t = $t; r = $r; b = $b; n = $n }
}
# Thickness of the rect's left stroke: the run of ink pixels crossing the left
# edge. A quarter of the way down, because the row through the middle is where
# the left-middle selection handle sits, and the handle covers the stroke there.
function Stroke($bmp, $box, [bool]$yellow) {
    $y = [int]($box.t + ($box.b - $box.t) / 4)
    $n = 0
    for ($x = $box.l; $x -le $box.r; $x++) {
        $c = $bmp.GetPixel($x, $y)
        $hit = if ($yellow) { IsYellow $c } else { IsRed $c }
        if ($hit) { $n++ } elseif ($n -gt 0) { break }
    }
    return $n
}
# Ink of one colour on the rect's own box, leaving out the discs of the 8
# selection handles that sit on that box's corners and edge midpoints: their
# rings are drawn in the selection colour, so they would read as leftover ink
# of the old colour.
function Ink-Count($bmp, $box, [bool]$yellow, [int]$skipR) {
    $my = [int](($box.t + $box.b) / 2); $mx = [int](($box.l + $box.r) / 2)
    $px = @($box.l, $mx, $box.r, $box.r, $box.r, $mx, $box.l, $box.l)
    $py = @($box.t, $box.t, $box.t, $my, $box.b, $box.b, $box.b, $my)
    $n = 0
    for ($y = ($box.t - $skipR); $y -le ($box.b + $skipR); $y++) {
        for ($x = ($box.l - $skipR); $x -le ($box.r + $skipR); $x++) {
            $c = $bmp.GetPixel($x, $y)
            $hit = if ($yellow) { IsYellow $c } else { IsRed $c }
            if (-not $hit) { continue }
            $onHandle = $false
            for ($i = 0; $i -lt 8; $i++) {
                $dx = $x - $px[$i]; $dy = $y - $py[$i]
                if (($dx * $dx + $dy * $dy) -le ($skipR * $skipR)) { $onHandle = $true; break }
            }
            if (-not $onHandle) { $n++ }
        }
    }
    return $n
}

$sel = @(800, 600, 1500, 1050)
$fail = @()

MoveTo 3000 1900
Start-Sleep -Milliseconds 400
Get-Process winshot -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 600
$proc = Start-Process -FilePath 'D:\Project\winshot\x64\Debug\winshot.exe' -PassThru
Start-Sleep -Seconds 2

$sink = New-Object System.Collections.ArrayList
$cb = [ST+EnumProc] {
    param($h, $l)
    $t = New-Object System.Text.StringBuilder 256
    [void][ST]::GetWindowText($h, $t, 256)
    if ($t.ToString() -eq 'WinShotSink') { [void]$sink.Add($h) }
    return $true
}
[void][ST]::EnumWindows($cb, [IntPtr]::Zero)
if ($sink.Count -eq 0) { 'FAIL: no sink window'; exit 1 }
[void][ST]::PostMessage($sink[0], 0x8002, [IntPtr]::Zero, [IntPtr]::Zero)
Start-Sleep -Seconds 2

Drag $sel[0] $sel[1] $sel[2] $sel[3]
$s = Grab 'D:\Project\winshot\obj\st_bars.png'
$bands = @(Bands $s ($sel[0] + 6) ($sel[3] + 1) ($sel[3] + 110))
if ($bands.Count -lt 1) { 'FAIL: no toolbar under the selection'; exit 1 }
# Walk right from the toolbar's left edge and stop at the first gap wider than a
# separator; a row above the glyphs is unbroken by icon strokes.
function Run-Right($bmp, [int]$row, [int]$x0, [int]$x1) {
    $last = $x0; $gap = 0
    for ($x = $x0; $x -le $x1; $x++) {
        if (IsBack ($bmp.GetPixel($x, $row))) { $last = $x; $gap = 0 }
        elseif (++$gap -gt 6) { break }
    }
    return $last
}
$tb = $bands[0]
$tbL = $sel[0] + 1
$tbR = Run-Right $s ($tb[0] + 2) $tbL ($sel[2] + 300)
# 15 slots, separators after slot 6 and slot 12, 4px padding each end.
$cell = [int](($tbR - $tbL - 8 - 2 * 14) / 15)
$slot0 = $tbL + 4 + [int]($cell / 2)
$midY = [int](($tb[0] + $tb[1]) / 2)
$s.Dispose()
"toolbar x=$tbL..$tbR y=$($tb[0])..($tb[1]) cell=$cell"
if ($cell -lt 20 -or $cell -gt 34) { "FAIL: implausible cell width $cell"; exit 1 }

# Draw one rect with the defaults.
Click $slot0 $midY
Drag 900 700 1150 850
Start-Sleep -Milliseconds 300

$win = @(860, 660, 1220, 900)
$s = Grab 'D:\Project\winshot\obj\st_drawn.png'
$box = Ink-Box $s $win[0] $win[1] $win[2] $win[3] $false
if (-not $box) { 'FAIL: the rect was never drawn'; exit 1 }
$wRed = Stroke $s $box $false
$s.Dispose()
"rect drawn: ink box ($($box.l),$($box.t))..($($box.r),$($box.b))  red px=$($box.n)  left stroke=$wRed"

# Select it: a point on its own stroke, a quarter of the way along the top edge
# so it is not one of the eight bbox handles.
$px = [int]($box.l + ($box.r - $box.l) / 4)
$py = $box.t + [int]($wRed / 2)
Click $px $py
$s = Grab 'D:\Project\winshot\obj\st_selected.png'
$b2 = Ink-Box $s $win[0] $win[1] $win[2] $win[3] $false
$s.Dispose()
"selected at ($px,$py): red px=$($b2.n)"

# The property bar is the lowest tall band of chrome below the selection. The
# armed tool's cell is drawn with a highlight that is not the plain chrome
# colour, so the toolbar may not read as a band at all — the bar is the last one
# either way. Its rows then bound the chip search: the dimmed desktop around it
# is full of saturated colours of its own.
$runs0 = @(Bands (Grab 'D:\Project\winshot\obj\st_bar.png') ($sel[0] + 6) ($sel[3] + 1) ($sel[3] + 140))
$pb = $null
foreach ($r in $runs0) { if (($r[1] - $r[0]) -ge 20) { $pb = $r } }
if (-not $pb) { 'FAIL: no property bar band below the selection'; exit 1 }
"property bar y=$($pb[0])..$($pb[1])"

function Saturated($c) {
    $mx = [Math]::Max($c.R, [Math]::Max($c.G, $c.B))
    $mn = [Math]::Min($c.R, [Math]::Min($c.G, $c.B))
    return (($mx - $mn) -gt 90 -and $mx -gt 120)
}
$s = Grab ''
$gl = -1; $gt = -1; $gr = -1; $gb = -1
$yl = -1; $yt = -1; $yr = -1; $yb = -1
for ($y = $pb[0]; $y -le $pb[1]; $y++) {
    for ($x = $sel[0] - 30; $x -le $sel[2] + 60; $x++) {
        $c = $s.GetPixel($x, $y)
        if (Saturated $c) {
            if ($gl -lt 0 -or $x -lt $gl) { $gl = $x }
            if ($x -gt $gr) { $gr = $x }
            if ($gt -lt 0) { $gt = $y }
            $gb = $y
        }
        if (IsYellow $c) {
            if ($yl -lt 0 -or $x -lt $yl) { $yl = $x }
            if ($x -gt $yr) { $yr = $x }
            if ($yt -lt 0) { $yt = $y }
            $yb = $y
        }
    }
}
if ($gl -lt 0) { $s.Dispose(); 'FAIL: no colour chips below the selection'; exit 1 }
if ($yl -lt 0) { $s.Dispose(); 'FAIL: no yellow swatch in the property bar'; exit 1 }
$cx = [int](($yl + $yr) / 2); $cy = [int](($yt + $yb) / 2)

# The three width dots are drawn in the accent blue, so they are the leftmost
# blue runs in the bar; the palette's own blue chips sit further right. The first
# dot is the narrowest pen.
function IsBlue($c) { return ($c.B -gt 150 -and ($c.B - $c.R) -gt 60 -and ($c.B - $c.G) -gt 30) }
$pmid = [int](($pb[0] + $pb[1]) / 2)
$runs = @(); $cur = $null
for ($x = $gl; $x -le $gr; $x++) {
    $hit = $false
    for ($y = $pb[0] + 2; $y -le $pb[1] - 2; $y++) {
        if (IsBlue ($s.GetPixel($x, $y))) { $hit = $true; break }
    }
    if ($hit) { if ($null -eq $cur) { $cur = @($x, $x) } else { $cur[1] = $x } }
    elseif ($null -ne $cur) { $runs += , $cur; $cur = $null }
}
if ($null -ne $cur) { $runs += , $cur }
$s.Dispose()
"chip grid x=$gl..$gr y=$gt..$gb; yellow chip ($cx,$cy)"
"width dots: $(($runs | ForEach-Object { "$($_[0])..$_[1]" }) -join ' ')"
if ($runs.Count -lt 3) { 'FAIL: the three width dots are not all there'; exit 1 }
$dotX = [int](($runs[0][0] + $runs[0][1]) / 2)
$dotY = $pmid

Click $cx $cy

$s = Grab 'D:\Project\winshot\obj\st_coloured.png'
$red = Ink-Box $s $win[0] $win[1] $win[2] $win[3] $false
$yel = Ink-Box $s $win[0] $win[1] $win[2] $win[3] $true
$yelN = if ($yel) { $yel.n } else { 0 }
# Counted off the handle discs; without the yellow box to locate the rect the
# whole-window red count stands, which is what a failed recolour wants.
$redN = if ($yel) { Ink-Count $s $yel $false 9 } elseif ($red) { $red.n } else { 0 }
# The width baseline comes off the yellow box, not the red one it was drawn
# with: recolouring leaves the stroke as thick as it was, and a yellow scan is
# immune to the ClearType fringes on the desktop text behind it, which a red one
# picks up as a stray pixel and reads as a wider box.
$w0 = if ($yel) { Stroke $s $yel $true } else { 0 }
$s.Dispose()
"after the colour click: red px=$redN (off the handles)  yellow px=$yelN  left stroke=$w0"
if ($yelN -lt 500 -or $redN -gt 200) {
    $fail += "the selected rect did not take the new colour (yellow $yelN, red left $redN)"
}

# --- the narrow width dot ----------------------------------------------------
"narrow dot at ($dotX,$dotY)"
Click $dotX $dotY

$s = Grab 'D:\Project\winshot\obj\st_thin.png'
$yel2 = Ink-Box $s $win[0] $win[1] $win[2] $win[3] $true
$w1 = if ($yel2) { Stroke $s $yel2 $true } else { 0 }
$s.Dispose()
"after the width click: yellow px=$($yel2.n)  left stroke=$w1 (was $w0)"
if ($w1 -ge $w0 -or $w1 -lt 1) {
    $fail += "the selected rect did not take the new width (stroke $w1, was $w0)"
}

[void][System.Windows.Forms.SendKeys]::SendWait('{ESC}')
Start-Sleep -Milliseconds 400
[void][System.Windows.Forms.SendKeys]::SendWait('{ESC}')
Start-Sleep -Milliseconds 400
if (-not $proc.HasExited) { $proc.Kill() }

if ($fail.Count) { "FAILURES: $($fail.Count)"; $fail | ForEach-Object { "  $_" }; exit 1 }
'PASS'
