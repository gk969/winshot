Add-Type -AssemblyName System.Drawing, System.Windows.Forms
Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class W4 {
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
function MoveTo([int]$x, [int]$y) {
    [System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point($x, $y)
    Start-Sleep -Milliseconds 100
}
function Drag([int]$x1, [int]$y1, [int]$x2, [int]$y2) {
    MoveTo $x1 $y1
    [void][W4]::mouse_event($LEFTDOWN, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 120
    for ($i = 1; $i -le 12; $i++) {
        MoveTo ([int]($x1 + ($x2-$x1) * $i / 12)) ([int]($y1 + ($y2-$y1) * $i / 12))
    }
    Start-Sleep -Milliseconds 150
    [void][W4]::mouse_event($LEFTUP, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 300
}
function Click([int]$x, [int]$y) {
    MoveTo $x $y
    [void][W4]::mouse_event($LEFTDOWN, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 120
    [void][W4]::mouse_event($LEFTUP, 0, 0, 0, [UIntPtr]::Zero)
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

# Our own windows by title. A save now ends the capture, so the script has to be able
# to say the overlay is gone -- "the process is still up" is true either way and says
# nothing about it.
function Wins([string]$title) {
    $found = New-Object System.Collections.ArrayList
    $cb = [W4+EnumProc] {
        param($h, $l)
        $t = New-Object System.Text.StringBuilder 256
        [void][W4]::GetWindowText($h, $t, 256)
        if ($t.ToString() -eq $title) { [void]$found.Add($h) }
        return $true
    }
    [void][W4]::EnumWindows($cb, [IntPtr]::Zero)
    return $found.ToArray()
}
function Summon() {
    [void][W4]::PostMessage($sink[0], 0x8002, [IntPtr]::Zero, [IntPtr]::Zero)
    Start-Sleep -Seconds 2
}

$OUT = 'D:\Project\winshot\obj\s4_out.png'
if (Test-Path $OUT) { Remove-Item $OUT }

MoveTo 3000 1900
Start-Sleep -Milliseconds 400

$p = Start-Process -FilePath 'D:\Project\winshot\x64\Debug\winshot.exe' -PassThru
Start-Sleep -Seconds 2

$sink = New-Object System.Collections.ArrayList
$cb = [W4+EnumProc] {
    param($h, $l)
    $t = New-Object System.Text.StringBuilder 256
    [void][W4]::GetWindowText($h, $t, 256)
    if ($t.ToString() -eq 'WinShotSink') { [void]$sink.Add($h) }
    return $true
}
[void][W4]::EnumWindows($cb, [IntPtr]::Zero)
if ($sink.Count -eq 0) { "FAIL: no sink window"; exit 1 }

[void][W4]::PostMessage($sink[0], 0x8002, [IntPtr]::Zero, [IntPtr]::Zero)
Start-Sleep -Seconds 2

Drag 800 600 1400 1000
$sel = @(800, 600, 1400, 1000)

$s1 = Grab 'D:\Project\winshot\obj\s4_bar.png'
$b1 = Band $s1 ($sel[0] + 6) ($sel[3] + 1) ($sel[3] + 90)
if (-not $b1) { "FAIL: no toolbar under the selection"; exit 1 }
$tbTop = $b1[0]; $tbBot = $b1[1]
$e1 = Extent $s1 ([int](($tbTop + $tbBot) / 2))
$cell = [int](($e1[1] - $e1[0] - 8) / 17)
$firstX = $e1[0] + 4 + [int]($cell / 2)
$midY = [int](($tbTop + $tbBot) / 2)
"toolbar x=$($e1[0])..$($e1[1]) y=$tbTop..$tbBot  rect slot=($firstX,$midY)"

Click $firstX $midY          # arm the rect tool
Drag 900 700 1200 900        # draw the shape

# The band the top edge of the drawn rect should cover, on screen.
$edge = @(950, 694, 1150, 706)
$s2 = Grab 'D:\Project\winshot\obj\s4_rect.png'
$with = RedCount $s2 $edge[0] $edge[1] $edge[2] $edge[3]
"red pixels along the drawn top edge: $with  (want > 150)"

[void][System.Windows.Forms.SendKeys]::SendWait('^z')
Start-Sleep -Milliseconds 500
$s3 = Grab 'D:\Project\winshot\obj\s4_undo.png'
$after = RedCount $s3 $edge[0] $edge[1] $edge[2] $edge[3]
"after Ctrl+Z: $after  (want 0)"

Drag 900 700 1200 900        # draw it again

# The tick and Ctrl+S are two different exits and only one of them can follow a
# drawing, so the tick comes first and the save gets a capture of its own below.
$ox = $sel[0]; $oy = $sel[1]
[System.Windows.Forms.Clipboard]::Clear()
Start-Sleep -Milliseconds 300
[void][System.Windows.Forms.SendKeys]::SendWait('{ENTER}')   # tick = clipboard + close
Start-Sleep -Seconds 2

$do = [System.Windows.Forms.Clipboard]::GetDataObject()
if (-not $do) { "FAIL: clipboard empty after the tick" }
else {
    "clipboard formats: $($do.GetFormats() -join ', ')"
    if ($do.GetDataPresent([System.Windows.Forms.DataFormats]::Dib)) {
        $st = $do.GetData([System.Windows.Forms.DataFormats]::Dib)
        "dib bytes: $($st.Length)  (want $(40 + 600 * 4 * 400))"
    }
    if ($do.GetDataPresent([System.Windows.Forms.DataFormats]::Bitmap)) {
        $img = $do.GetData([System.Windows.Forms.DataFormats]::Bitmap)
        "clipboard image $($img.Width) x $($img.Height)"
        $clipRed = RedCount $img (950-$ox) (694-$oy) (1150-$ox) (706-$oy)
        "red pixels in the clipboard image: $clipRed  (want > 150)"
        $img.Dispose()
    } else {
        "FAIL: no Bitmap on the clipboard"
    }
}
if (@(Wins 'WinShotOverlay').Count) { "FAIL: the tick left the overlay up" }

# --- a second capture, for the save -------------------------------------------------
# The region is dragged identically, so the toolbar lands where it did before and the
# rect slot keeps the coordinates found above.
Summon
Drag 800 600 1400 1000
Click $firstX $midY          # arm the rect tool on the new toolbar
Drag 900 700 1200 900
[void][System.Windows.Forms.SendKeys]::SendWait('^s')
Start-Sleep -Seconds 2
[void][System.Windows.Forms.SendKeys]::SendWait('{HOME}+{END}')
[void][System.Windows.Forms.SendKeys]::SendWait($OUT)
[void][System.Windows.Forms.SendKeys]::SendWait('{ENTER}')
Start-Sleep -Seconds 2

if (-not (Test-Path $OUT)) { "FAIL: Ctrl+S wrote no file"; exit 1 }
$png = [System.Drawing.Bitmap]::FromFile((Resolve-Path $OUT).Path)
"saved png $($png.Width) x $($png.Height)  (want $($sel[2]-$sel[0]) x $($sel[3]-$sel[1]))"
$inSel = RedCount $png (950-$ox) (694-$oy) (1150-$ox) (706-$oy)
"red pixels in the png at the same spot: $inSel  (want > 150)"

# The crop comes from the frozen still, so none of the overlay chrome — the blue
# selection frame in particular — may appear in it.
function IsFrame($c) { return ($c.B -gt 180 -and $c.G -gt 130 -and $c.R -lt 90) }
$frame = 0
for ($i = 0; $i -lt 4; $i++) {
    foreach ($c in @($png.GetPixel($i, $i), $png.GetPixel($png.Width-1-$i, $i),
                     $png.GetPixel($i, $png.Height-1-$i),
                     $png.GetPixel($png.Width-1-$i, $png.Height-1-$i))) {
        if (IsFrame $c) { $frame++ }
    }
}
"blue selection-frame pixels inside the crop: $frame  (want 0)"
$png.Dispose()

# A save ends the capture; the program stays in the tray so the hotkey works again.
$left = @(Wins 'WinShotOverlay').Count
"overlay windows after the save: $left  (want 0)"
if ($left -ne 0) { "FAIL: the save left the overlay up" }
"winshot still running: $(-not $p.HasExited)"
if (-not $p.HasExited) { $p.Kill() }
