Add-Type -AssemblyName System.Drawing, System.Windows.Forms
Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class W5 {
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
    $bmp.Save($path)
    $g.Dispose()
    return $bmp
}
function Crop($full, [int]$x, [int]$y, [int]$w, [int]$h, [string]$path) {
    $r = New-Object System.Drawing.Rectangle $x, $y, $w, $h
    $c = $full.Clone($r, $full.PixelFormat)
    $c.Save($path)
    return $c
}
function MoveTo([int]$x, [int]$y) {
    [System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point($x, $y)
    Start-Sleep -Milliseconds 90
}
function Drag([int]$x1, [int]$y1, [int]$x2, [int]$y2) {
    MoveTo $x1 $y1
    [void][W5]::mouse_event($LEFTDOWN, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 120
    for ($i = 1; $i -le 12; $i++) {
        MoveTo ([int]($x1 + ($x2-$x1) * $i / 12)) ([int]($y1 + ($y2-$y1) * $i / 12))
    }
    Start-Sleep -Milliseconds 150
    [void][W5]::mouse_event($LEFTUP, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 300
}
# Freehand: one press, several waypoints, one release.
function Path([int[]]$pts) {
    MoveTo $pts[0] $pts[1]
    [void][W5]::mouse_event($LEFTDOWN, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 120
    for ($i = 2; $i -lt $pts.Length; $i += 2) {
        $px = $pts[$i - 2]; $py = $pts[$i - 1]
        for ($k = 1; $k -le 8; $k++) {
            MoveTo ([int]($px + ($pts[$i]-$px) * $k / 8)) ([int]($py + ($pts[$i+1]-$py) * $k / 8))
        }
    }
    Start-Sleep -Milliseconds 150
    [void][W5]::mouse_event($LEFTUP, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 300
}
function Click([int]$x, [int]$y) {
    MoveTo $x $y
    [void][W5]::mouse_event($LEFTDOWN, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 120
    [void][W5]::mouse_event($LEFTUP, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 350
}
function IsBack($c) {
    return ([Math]::Abs($c.R - 235) -le 8 -and [Math]::Abs($c.G - 239) -le 8 -and
            [Math]::Abs($c.B - 243) -le 8)
}
function Band($bmp, [int]$x, [int]$y0, [int]$y1) {
    $top = -1
    for ($y = $y0; $y -le $y1; $y++) { if (IsBack ($bmp.GetPixel($x, $y))) { $top = $y; break } }
    if ($top -lt 0) { return $null }
    $bot = $top
    while ($bot + 1 -le $y1 -and (IsBack ($bmp.GetPixel($x, ($bot + 1))))) { $bot++ }
    return @($top, $bot)
}
function Extent($bmp, [int]$row) {
    $l = -1; $r = -1
    for ($x = 0; $x -lt $bmp.Width; $x++) {
        $c = $bmp.GetPixel($x, $row)
        if ($c.R -gt 200 -and $c.G -gt 200 -and $c.B -gt 200) { if ($l -lt 0) { $l = $x }; $r = $x }
    }
    return @($l, $r)
}
# The default annotation colour is palette slot 10 = F73840.
function IsRed($c) { return ($c.R -gt 190 -and $c.G -lt 120 -and $c.B -lt 130) }
function RedCount($bmp, [int]$x0, [int]$y0, [int]$x1, [int]$y1) {
    if (-not $bmp) { return -1 }
    $n = 0
    for ($y = $y0; $y -le $y1; $y++) {
        for ($x = $x0; $x -le $x1; $x++) { if (IsRed ($bmp.GetPixel($x, $y))) { $n++ } }
    }
    return $n
}

$sel = @(800, 600, 1400, 1000)
foreach ($f in @('s5_canvas.png', 's5_arrow.png', 's5_out.png')) {
    $p = "D:\Project\winshot\obj\$f"; if (Test-Path $p) { Remove-Item $p }
}

MoveTo 3000 1900
Start-Sleep -Milliseconds 400

$proc = Start-Process -FilePath 'D:\Project\winshot\x64\Debug\winshot.exe' -PassThru
Start-Sleep -Seconds 2

$sink = New-Object System.Collections.ArrayList
$cb = [W5+EnumProc] {
    param($h, $l)
    $t = New-Object System.Text.StringBuilder 256
    [void][W5]::GetWindowText($h, $t, 256)
    if ($t.ToString() -eq 'WinShotSink') { [void]$sink.Add($h) }
    return $true
}
[void][W5]::EnumWindows($cb, [IntPtr]::Zero)
if ($sink.Count -eq 0) { "FAIL: no sink window"; exit 1 }

[void][W5]::PostMessage($sink[0], 0x8002, [IntPtr]::Zero, [IntPtr]::Zero)
Start-Sleep -Seconds 2

Drag $sel[0] $sel[1] $sel[2] $sel[3]

$s0 = Grab 'D:\Project\winshot\obj\s5_bar.png'
$b0 = Band $s0 ($sel[0] + 6) ($sel[3] + 1) ($sel[3] + 90)
if (-not $b0) { "FAIL: no toolbar under the selection"; exit 1 }
$midY = [int](($b0[0] + $b0[1]) / 2)
$e0 = Extent $s0 $midY
$cell = [int](($e0[1] - $e0[0] - 8) / 17)
$slot0 = $e0[0] + 4 + [int]($cell / 2)   # centre of the 矩形 slot
"toolbar x=$($e0[0])..$($e0[1]) y=$($b0[0])..$($b0[1]) cell=$cell slot0=($slot0,$midY)"
# The comma binds tighter than *, so the arithmetic needs its own parentheses.
function Slot([int]$i) { return @(($slot0 + $i * $cell), $midY) }

$base = RedCount $s0 880 680 1300 950
"red pixels before drawing: $base  (want 0)"

# --- arrow (slot 2) -------------------------------------------------------
$a = Slot 2
Click $a[0] $a[1]
$sa = Grab 'D:\Project\winshot\obj\s5_bar_arrow.png'
[void](Crop $sa $sel[0] ($b0[1] + 2) 220 50 'D:\Project\winshot\obj\s5_bar_arrow.png')
Drag 900 700 1150 820
$s1 = Grab 'D:\Project\winshot\obj\s5_arrow_only.png'
# A band across the middle of the shaft, away from the head.
$shaft = RedCount $s1 995 740 1015 760
"arrow shaft pixels: $shaft  (want > 10)"
Click $a[0] $a[1]   # disarm so the next click selects instead of drawing
Click 1000 748      # select the arrow
$s2 = Grab 'D:\Project\winshot\obj\s5_arrow.png'
[void](Crop $s2 860 660 340 220 'D:\Project\winshot\obj\s5_arrow.png')
"selected-arrow crop written"
Click 1000 748      # click again keeps it selected and starts nothing

# --- pen (slot 3) ---------------------------------------------------------
$p = Slot 3
Click $p[0] $p[1]
$sp = Grab 'D:\Project\winshot\obj\s5_bar_pen.png'
[void](Crop $sp $sel[0] ($b0[1] + 2) 220 50 'D:\Project\winshot\obj\s5_bar_pen.png')
Path @(950, 900, 1000, 870, 1050, 915, 1100, 875)
$s3 = Grab 'D:\Project\winshot\obj\s5_pen.png'
$pen = RedCount $s3 960 880 990 900
"pen stroke pixels: $pen  (want > 20)"
Click $p[0] $p[1]

# --- badges (slot 6) ------------------------------------------------------
$b = Slot 6
Click $b[0] $b[1]
Click 1250 700
Click 1250 760
$s4 = Grab 'D:\Project\winshot\obj\s5_canvas.png'
$disc = RedCount $s4 1236 686 1264 714
"badge 1 disc pixels: $disc  (want > 100)"
$white = 0
for ($y = 692; $y -le 708; $y++) {
    for ($x = 1242; $x -le 1258; $x++) {
        $c = $s4.GetPixel($x, $y)
        if ($c.R -gt 225 -and $c.G -gt 225 -and $c.B -gt 225) { $white++ }
    }
}
"white glyph pixels in badge 1: $white  (want > 10)"
[void](Crop $s4 860 660 460 280 'D:\Project\winshot\obj\s5_canvas.png')
Click $b[0] $b[1]

# --- undo each of the four edits ----------------------------------------
foreach ($i in 1..4) {
    [void][System.Windows.Forms.SendKeys]::SendWait('^z')
    Start-Sleep -Milliseconds 400
}
$s5 = Grab 'D:\Project\winshot\obj\s5_undo.png'
$left = RedCount $s5 880 680 1300 950
"red pixels after 4x Ctrl+Z: $left  (want 0)"

# --- redraw everything, then save ---------------------------------------
$a = Slot 2; Click $a[0] $a[1]
Drag 900 700 1150 820
Click $a[0] $a[1]
$p = Slot 3; Click $p[0] $p[1]
Path @(950, 900, 1000, 870, 1050, 915, 1100, 875)
Click $p[0] $p[1]
$b = Slot 6; Click $b[0] $b[1]
Click 1250 700
Click $b[0] $b[1]

$OUT = 'D:\Project\winshot\obj\s5_out.png'
[void][System.Windows.Forms.SendKeys]::SendWait('^s')
Start-Sleep -Seconds 2
[void][System.Windows.Forms.SendKeys]::SendWait('{HOME}+{END}')
[void][System.Windows.Forms.SendKeys]::SendWait($OUT)
[void][System.Windows.Forms.SendKeys]::SendWait('{ENTER}')
Start-Sleep -Seconds 2

if (-not (Test-Path $OUT)) { "FAIL: Ctrl+S wrote no file"; exit 1 }
$png = [System.Drawing.Bitmap]::FromFile((Resolve-Path $OUT).Path)
"saved png $($png.Width) x $($png.Height)  (want $($sel[2]-$sel[0]) x $($sel[3]-$sel[1]))"
$ox = $sel[0]; $oy = $sel[1]
"in png: shaft=$([int](RedCount $png (995-$ox) (740-$oy) (1015-$ox) (760-$oy))) pen=$([int](RedCount $png (960-$ox) (880-$oy) (990-$ox) (900-$oy))) badge=$([int](RedCount $png (1236-$ox) (686-$oy) (1264-$ox) (714-$oy)))"
$png.Dispose()

"winshot still running: $(-not $proc.HasExited)"
if (-not $proc.HasExited) { $proc.Kill() }
