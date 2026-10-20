Add-Type -AssemblyName System.Drawing, System.Windows.Forms
Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class W5C {
    public delegate bool EnumProc(IntPtr h, IntPtr l);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
    [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr p, EnumProc cb, IntPtr l);
    [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll", CharSet=CharSet.Auto)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint msg, IntPtr w, IntPtr l);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr SendMessage(IntPtr h, uint msg, IntPtr w, string l);
    [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr h, uint msg, IntPtr w, IntPtr l);
    [DllImport("user32.dll")] public static extern int GetWindowThreadProcessId(IntPtr h, out int pid);
    [DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr h, int idx);
    [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint dx, uint dy, uint d, UIntPtr e);
}
"@

$LEFTDOWN = 0x0002; $LEFTUP = 0x0004
$WM_SETTEXT = 0x000C; $BM_CLICK = 0x00F5; $GWL_STYLE = -16; $BS_DEFPUSHBUTTON = 0x1

# 96dpi display: the app's logical sizes are its physical sizes.
$K = 1.0
function Sx([int]$v) { return [int]($v * $K) }

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
    [void][W5C]::mouse_event($LEFTDOWN, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 120
    for ($i = 1; $i -le 12; $i++) {
        MoveTo ([int]($x1 + ($x2-$x1) * $i / 12)) ([int]($y1 + ($y2-$y1) * $i / 12))
    }
    Start-Sleep -Milliseconds 150
    [void][W5C]::mouse_event($LEFTUP, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 300
}
function Click([int]$x, [int]$y) {
    MoveTo $x $y
    [void][W5C]::mouse_event($LEFTDOWN, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 120
    [void][W5C]::mouse_event($LEFTUP, 0, 0, 0, [UIntPtr]::Zero)
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
function IsRed($c) { return ($c.R -gt 190 -and $c.G -lt 120 -and $c.B -lt 130) }
function RedCount($bmp, [int]$x0, [int]$y0, [int]$x1, [int]$y1) {
    if (-not $bmp) { return -1 }
    $n = 0
    for ($y = $y0; $y -le $y1; $y++) {
        for ($x = $x0; $x -le $x1; $x++) { if (IsRed ($bmp.GetPixel($x, $y))) { $n++ } }
    }
    return $n
}
# The rail: 4px of grey (211) at rest, blue (106,175,234) up to the thumb.
function IsRail($c) {
    $grey = ([Math]::Abs($c.R - $c.G) -lt 12 -and [Math]::Abs($c.G - $c.B) -lt 12 -and
             $c.R -gt 195 -and $c.R -lt 226)
    $blue = ($c.B -gt 205 -and $c.R -gt 80 -and $c.R -lt 140 -and $c.G -gt 150 -and $c.G -lt 200)
    return ($grey -or $blue)
}
function IsBlue($c) { return ($c.B -gt 205 -and $c.R -gt 80 -and $c.R -lt 140 -and $c.G -gt 150 -and $c.G -lt 200) }
function RailCount($bmp, [int]$x0, [int]$x1, [int]$y) {
    $n = 0
    for ($x = $x0; $x -le $x1; $x++) { if (IsRail ($bmp.GetPixel($x, $y))) { $n++ } }
    return $n
}
function BlueCount($bmp, [int]$x0, [int]$x1, [int]$y) {
    $n = 0
    for ($x = $x0; $x -le $x1; $x++) { if (IsBlue ($bmp.GetPixel($x, $y))) { $n++ } }
    return $n
}
function InkCount($bmp, [int]$x0, [int]$y0, [int]$x1, [int]$y1) {
    $n = 0
    for ($y = $y0; $y -le $y1; $y++) {
        for ($x = $x0; $x -le $x1; $x++) {
            $c = $bmp.GetPixel($x, $y)
            if ($c.R -lt 110 -and $c.G -lt 110 -and $c.B -lt 110) { $n++ }
        }
    }
    return $n
}

Get-Process winshot -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 600

$sel = @(800, 600, 1400, 1000)
# Three red pen lines: the structure the mosaic band has to average away.
$lnX0 = 900; $lnX1 = 1350; $lnY = @(780, 800, 820)
$bandAX = 1000; $bandBX = 1250; $bandY0 = 765; $bandY1 = 835
# The witness that the mosaic leaves the rest of the canvas alone: a strip of the
# reference lines between the two bands. The band is four times the widest dot, so
# it reaches 16px either side of its drag line; the strip starts 24px out to stay
# clear of that and of the second band's edge.
$outX0 = $bandAX + 40; $outX1 = $bandAX + 125
$fail = @()

Get-ChildItem 'D:\Project\winshot\obj\s5c_*.png' -ErrorAction SilentlyContinue | Remove-Item -Force

MoveTo 3000 1900
Start-Sleep -Milliseconds 400

$proc = Start-Process -FilePath 'D:\Project\winshot\x64\Debug\winshot.exe' -PassThru
Start-Sleep -Seconds 2

$sink = New-Object System.Collections.ArrayList
$cb = [W5C+EnumProc] {
    param($h, $l)
    $t = New-Object System.Text.StringBuilder 256
    [void][W5C]::GetWindowText($h, $t, 256)
    if ($t.ToString() -eq 'WinShotSink') { [void]$sink.Add($h) }
    return $true
}
[void][W5C]::EnumWindows($cb, [IntPtr]::Zero)
if ($sink.Count -eq 0) { "FAIL: no sink window"; exit 1 }

[void][W5C]::PostMessage($sink[0], 0x8002, [IntPtr]::Zero, [IntPtr]::Zero)
Start-Sleep -Seconds 2

Drag $sel[0] $sel[1] $sel[2] $sel[3]

$s0 = Grab 'D:\Project\winshot\obj\s5c_full0.png'
$b0 = Band $s0 ($sel[0] + 6) ($sel[3] + 1) ($sel[3] + 90)
if (-not $b0) { "FAIL: no toolbar under the selection"; exit 1 }
$midY = [int](($b0[0] + $b0[1]) / 2)
$e0 = Extent $s0 $midY
$cell = [int](($e0[1] - $e0[0] - 8) / 17)
$slot0 = $e0[0] + 4 + [int]($cell / 2)
"toolbar x=$($e0[0])..$($e0[1]) y=$($b0[0])..($($b0[1])) cell=$cell"
function Slot([int]$i) { return @(($slot0 + $i * $cell), $midY) }

# The property bar sits 2px under the toolbar, left-aligned with it.
# The bar only exists while a tool is active: pick 画笔 first, then measure.
$t = Slot 3
$barLeft = $e0[0]
$bb = $null
for ($try = 0; $try -lt 3 -and -not $bb; $try++) {
    Click $t[0] $t[1]
    $sb = Grab ("D:\Project\winshot\obj\s5c_bar0{0}.png" -f $try)
    for ($y = $b0[1] + 1; $y -le $b0[1] + 12 -and -not $bb; $y++) {
        if (IsBack ($sb.GetPixel($barLeft + 3, $y))) { $bb = Band $sb ($barLeft + 3) $y ($y + 50) }
    }
}
if (-not $bb) { "FAIL: no property bar under the toolbar"; exit 1 }
$barTop = $bb[0]; $barH = $bb[1] - $bb[0] + 1
"property bar x=$barLeft y=$barTop..$($bb[1]) (h=$barH, want 37)"
if ($barH -lt 33 -or $barH -gt 41) { "FAIL: property bar height wrong"; exit 1 }
$barMidY = [int](($barTop + $bb[1]) / 2)
# The rail row: 4px tall, centred in the bar.
$railY = [int](($barTop + $bb[1]) / 2)

# The widest dot, not the default middle one: every threshold below is about what
# a mosaic block does to a stroke, and the middle dot's 4px line is only one block
# wide at the small setting, so it is the stroke that disappears rather than the
# block doing the averaging. Dot centres are at bar x + 13 + i * 25.
Click ($barLeft + 63) $barMidY

# --- 画笔 (slot 3): three reference lines --------------------------------
foreach ($y in $lnY) { Drag $lnX0 $y $lnX1 $y }
$s1 = Grab 'D:\Project\winshot\obj\s5c_full1.png'
$penAll = RedCount $s1 $lnX0 ($lnY[0] - 12) $lnX1 ($lnY[2] + 12)
$penOut = RedCount $s1 $outX0 $bandY0 $outX1 $bandY1
$penBandB = RedCount $s1 ($bandBX - 6) ($bandY0 + 5) ($bandBX + 6) ($bandY1 - 5)
"pen ink: all=$penAll outside=$penOut bandB=$penBandB  (want all > 3000)"
if ($penAll -lt 3000) { $fail += 'pen strokes missing' }
[void](Crop $s1 ($lnX0 - 20) ($lnY[0] - 30) 500 100 'D:\Project\winshot\obj\s5c_pen.png')

# --- 马赛克 (slot 4): the bar swaps the palette for the 模糊度 rail ------
$t = Slot 4
$trackX0 = $barLeft + (Sx 125); $trackX1 = $barLeft + (Sx 235)
# A synthetic click on the toolbar is occasionally swallowed (the pointer has
# just crossed the canvas after a stroke), so confirm the rail appeared and
# retry once rather than failing the run.
$rail = -1
for ($try = 0; $try -lt 3; $try++) {
    Click $t[0] $t[1]
    $s2 = Grab ("D:\Project\winshot\obj\s5c_full2{0}.png" -f $try)
    $rail = RailCount $s2 $trackX0 $trackX1 $railY
    if ($rail -ge 90) { break }
}
if ($try -gt 0) { "mosaic tool click needed $try extra attempt(s); rail=$rail" }
# The band is four times the width index picked above, so the widest dot lays a
# 32px band. The 模糊度 bar shows no width dots at all — the index carries over
# from the shape tools — which is why the dot was clicked while the 画笔 bar was
# up. The measurement window below is 13px wide and sits inside the band.
$label = InkCount $s2 ($barLeft + (Sx 86)) ($barTop + 8) ($barLeft + (Sx 122)) ($bb[1] - 8)
$swatch = RedCount $s2 ($barLeft + (Sx 85)) ($barTop + 5) ($barLeft + (Sx 111)) ($barTop + 31)
"mosaic bar: rail=$rail px (want ~110) label ink=$label (want >20) red swatch=$swatch (want 0)"
if ($rail -lt 90) { $fail += 'rail missing' }
if ($label -lt 20) { $fail += '模糊度 label missing' }
if ($swatch -gt 20) { $fail += 'mosaic bar still shows the colour swatch' }
[void](Crop $s2 ($barLeft - 4) ($barTop - 4) 260 46 'D:\Project\winshot\obj\s5c_bar_mosaic.png')

# --- slider to the left end: block = 4 ----------------------------------
$blueMin = 999
for ($try = 0; $try -lt 3; $try++) {
    Click ($trackX0 + 1) $barMidY
    $s3 = Grab ("D:\Project\winshot\obj\s5c_full3{0}.png" -f $try)
    $blueMin = BlueCount $s3 $trackX0 $trackX1 $railY
    if ($blueMin -lt 12) { break }
}
"blue fill at min: $blueMin px  (want < 12)"
if ($blueMin -gt 12) { $fail += 'slider min fill too wide' }

# Band A over the three lines at the small block size.
Drag $bandAX $bandY0 $bandAX $bandY1
$s4 = Grab 'D:\Project\winshot\obj\s5c_full4.png'
$redA = RedCount $s4 ($bandAX - 6) ($bandY0 + 5) ($bandAX + 6) ($bandY1 - 5)
$outA = RedCount $s4 $outX0 $bandY0 $outX1 $bandY1
"band A (block 4): red=$redA (want > 150); outside=$outA (want $penOut)"
if ($redA -lt 150) { $fail += 'small-block band lost the lines' }
if ([Math]::Abs($outA - $penOut) -gt 30) { $fail += 'mosaic changed pixels outside its band' }
[void](Crop $s4 ($bandAX - 40) ($bandY0 - 10) 90 90 'D:\Project\winshot\obj\s5c_bandA.png')

# --- slider to the right end: block = 24 --------------------------------
$blueMax = 0
for ($try = 0; $try -lt 3; $try++) {
    # The target rect is [left, right): a click on the last column misses.
    Click ($trackX1 - 2) $barMidY
    $s5 = Grab ("D:\Project\winshot\obj\s5c_full5{0}.png" -f $try)
    $blueMax = BlueCount $s5 $trackX0 $trackX1 $railY
    if ($blueMax -gt 95) { break }
}
"blue fill at max: $blueMax px  (want > 95)"
if ($blueMax -lt 95) { $fail += 'slider max fill too narrow' }
[void](Crop $s5 ($barLeft - 4) ($barTop - 4) 260 46 'D:\Project\winshot\obj\s5c_bar_max.png')

for ($try = 0; $try -lt 3; $try++) {
    Drag $bandBX $bandY0 $bandBX $bandY1
    $s6 = Grab ("D:\Project\winshot\obj\s5c_full6{0}.png" -f $try)
    $redB = RedCount $s6 ($bandBX - 6) ($bandY0 + 5) ($bandBX + 6) ($bandY1 - 5)
    if ($redB -lt $penBandB - 100) { break }
}
"band B (block 24): red=$redB baseline=$penBandB (want < $redA / 3)"
[void](Crop $s6 ($bandBX - 40) ($bandY0 - 10) 90 90 'D:\Project\winshot\obj\s5c_bandB.png')
if ($redB -gt ($redA / 3)) { $fail += 'large block did not average the lines away' }
# The earlier band keeps its own block size: moving the slider must not
# retro-change it.
$redA2 = RedCount $s6 ($bandAX - 6) ($bandY0 + 5) ($bandAX + 6) ($bandY1 - 5)
"band A after the slider moved: $redA2 (was $redA)"
if ([Math]::Abs($redA2 - $redA) -gt 40) { $fail += 'slider retro-changed a committed band' }

# --- save: the PNG has to carry the same two bands ----------------------
# Saved while both bands are live, so the file can be compared against the
# pre-undo screen: band A keeps its lines, band B has them averaged away.
$OUT = 'D:\Project\winshot\obj\s5c_out.png'
Remove-Item $OUT -Force -ErrorAction SilentlyContinue
[void][System.Windows.Forms.SendKeys]::SendWait('^s')
Start-Sleep -Seconds 2

$dlg = New-Object System.Collections.ArrayList
$dcb = [W5C+EnumProc] {
    param($h, $l)
    $cls = New-Object System.Text.StringBuilder 256
    [void][W5C]::GetClassName($h, $cls, 256)
    if ($cls.ToString() -ne '#32770') { return $true }
    $pid2 = 0
    [void][W5C]::GetWindowThreadProcessId($h, [ref]$pid2)
    if ($pid2 -eq $proc.Id) { [void]$dlg.Add($h) }
    return $true
}
[void][W5C]::EnumWindows($dcb, [IntPtr]::Zero)
if ($dlg.Count -eq 0) { "FAIL: no save dialog"; exit 1 }

$btns = New-Object System.Collections.ArrayList
$ccb = [W5C+EnumProc] {
    param($h, $l)
    $cls = New-Object System.Text.StringBuilder 256
    [void][W5C]::GetClassName($h, $cls, 256)
    if ($cls.ToString() -eq 'Button') { [void]$btns.Add($h) }
    return $true
}
[void][W5C]::EnumChildWindows($dlg[0], $ccb, [IntPtr]::Zero)
# The file-name edit. This used to be the Edit whose text looked like a .png
# path, which only worked while the default name carried an extension -- it does
# not any more, because the format dropdown has to be free to decide that. The
# commdlg id cmb1 is no use either: GetSaveFileNameW routes to IFileSaveDialog
# unless OFN_ENABLEHOOK or OFN_ENABLETEMPLATE forces the classic resource, and
# the modern dialog has no cmb1 -- measured, GetDlgItem returns zero. The name
# edit is the one Edit with control id 1001; the address bar's toolbar shares
# that id, so the class has to be part of the test. The dialog is up before it
# has finished building its children, hence the retry.
$names = @()
for ($try = 0; $try -lt 20; $try++) {
    $found = New-Object System.Collections.ArrayList
    $nccb = [W5C+EnumProc] {
        param($h, $l)
        $cls = New-Object System.Text.StringBuilder 256
        [void][W5C]::GetClassName($h, $cls, 256)
        if ($cls.ToString() -eq 'Edit' -and [W5C]::GetWindowLong($h, -12) -eq 1001) { [void]$found.Add($h) }
        return $true
    }
    [void][W5C]::EnumChildWindows($dlg[0], $nccb, [IntPtr]::Zero)
    $names = $found.ToArray()
    if ($names.Count) { break }
    Start-Sleep -Milliseconds 200
}
if ($names.Count -eq 0) { "FAIL: no file-name edit in the dialog"; exit 1 }
$name = $names[0]
[void][W5C]::SendMessage($name, $WM_SETTEXT, [IntPtr]::Zero, $OUT)
$def = $null
foreach ($b in $btns) {
    if (([W5C]::GetWindowLong($b, $GWL_STYLE) -band $BS_DEFPUSHBUTTON) -ne 0) { $def = $b }
}
if (-not $def -and $btns.Count) { $def = $btns[0] }
[void][W5C]::SendMessage($def, $BM_CLICK, [IntPtr]::Zero, [IntPtr]::Zero)
Start-Sleep -Seconds 2

if (-not (Test-Path $OUT)) { "FAIL: Ctrl+S wrote no file"; exit 1 }
$png = [System.Drawing.Bitmap]::FromFile((Resolve-Path $OUT).Path)
$ox = $sel[0]; $oy = $sel[1]
$pA = RedCount $png ($bandAX - 6 - $ox) ($bandY0 + 5 - $oy) ($bandAX + 6 - $ox) ($bandY1 - 5 - $oy)
$pB = RedCount $png ($bandBX - 6 - $ox) ($bandY0 + 5 - $oy) ($bandBX + 6 - $ox) ($bandY1 - 5 - $oy)
$pOut = RedCount $png ($outX0 - $ox) ($bandY0 - $oy) ($outX1 - $ox) ($bandY1 - $oy)
"in png: bandA=$pA bandB=$pB outside=$pOut  ($($png.Width) x $($png.Height), want $($sel[2]-$sel[0]) x $($sel[3]-$sel[1]))"
$png.Dispose()
if ($pA -lt 150) { $fail += 'saved png lost the small-block band' }
if ($pB -gt ($pA / 3)) { $fail += 'saved png band B not averaged' }
if ([Math]::Abs($pOut - $penOut) -gt 40) { $fail += 'saved png ink outside the bands changed' }

# --- Ctrl+Z drops band B ------------------------------------------------
$redUndo = 0
for ($try = 0; $try -lt 3; $try++) {
    [void][System.Windows.Forms.SendKeys]::SendWait('^z')
    Start-Sleep -Milliseconds 600
    $s7 = Grab ("D:\Project\winshot\obj\s5c_full7{0}.png" -f $try)
    $redUndo = RedCount $s7 ($bandBX - 6) ($bandY0 + 5) ($bandBX + 6) ($bandY1 - 5)
    if ([Math]::Abs($redUndo - $penBandB) -le 40) { break }
}
"band B after Ctrl+Z: $redUndo (want ~$penBandB)"
if ([Math]::Abs($redUndo - $penBandB) -gt 40) { $fail += 'Ctrl+Z did not remove the band' }
[void](Crop $s7 ($bandBX - 40) ($bandY0 - 10) 90 90 'D:\Project\winshot\obj\s5c_undo.png')

if ($fail.Count) { "FAIL: " + ($fail -join '; '); exit 1 }
"PASS"
if (-not $proc.HasExited) { $proc.Kill() }
