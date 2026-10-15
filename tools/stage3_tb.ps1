Add-Type -AssemblyName System.Drawing, System.Windows.Forms
Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class W3 {
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
    Start-Sleep -Milliseconds 120
}
function Drag([int]$x1, [int]$y1, [int]$x2, [int]$y2) {
    MoveTo $x1 $y1
    [void][W3]::mouse_event($LEFTDOWN, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 120
    for ($i = 1; $i -le 12; $i++) {
        MoveTo ([int]($x1 + ($x2-$x1) * $i / 12)) ([int]($y1 + ($y2-$y1) * $i / 12))
    }
    Start-Sleep -Milliseconds 150
    [void][W3]::mouse_event($LEFTUP, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 300
}
function Click([int]$x, [int]$y) {
    MoveTo $x $y
    [void][W3]::mouse_event($LEFTDOWN, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 120
    [void][W3]::mouse_event($LEFTUP, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 350
}

function IsLight($c) { return ($c.R -gt 200 -and $c.G -gt 200 -and $c.B -gt 200) }

# Column scan at an x known to be plain chrome background (the left padding of
# the bar), matching the exact background colour rather than "any light pixel" —
# the undimmed selection interior is light too.
function IsBack($c) {
    return ([Math]::Abs($c.R - 235) -le 8 -and [Math]::Abs($c.G - 239) -le 8 -and
            [Math]::Abs($c.B - 243) -le 8)
}
function Band($bmp, [int]$x, [int]$y0, [int]$y1) {
    $top = -1
    for ($y = $y0; $y -le $y1; $y++) {
        if (IsBack ($bmp.GetPixel($x, $y))) { $top = $y; break }
    }
    if ($top -lt 0) { return $null }
    $bot = $top
    while ($bot + 1 -le $y1 -and (IsBack ($bmp.GetPixel($x, ($bot + 1))))) { $bot++ }
    return @($top, $bot)
}

function Extent($bmp, [int]$row) {
    $l = -1; $r = -1
    for ($x = 0; $x -lt $bmp.Width; $x++) {
        if (IsLight ($bmp.GetPixel($x, $row))) { if ($l -lt 0) { $l = $x }; $r = $x }
    }
    return @($l, $r)
}

function Clusters($bmp, [int]$left, [int]$right, [int]$top, [int]$bot) {
    $out = @(); $start = -1
    for ($x = $left; $x -le $right; $x++) {
        $n = 0
        for ($y = $top + 2; $y -le $bot - 2; $y++) {
            $c = $bmp.GetPixel($x, $y)
            if ($c.R -lt 120 -and $c.G -lt 120 -and $c.B -lt 120) { $n++ }
        }
        if ($n -gt 0 -and $start -lt 0) { $start = $x }
        if ($n -eq 0 -and $start -ge 0) { $end = $x - 1; $out += ,@(($left + ($start - $left)), ($left + ($end - $left))); $start = -1 }
    }
    if ($start -ge 0) { $out += ,@(($left + ($start - $left)), $right) }
    return $out
}

MoveTo 3000 1900
Start-Sleep -Milliseconds 400

$p = Start-Process -FilePath 'D:\Project\winshot\x64\Debug\winshot.exe' -PassThru
Start-Sleep -Seconds 2

$sink = New-Object System.Collections.ArrayList
$cb = [W3+EnumProc] {
    param($h, $l)
    $t = New-Object System.Text.StringBuilder 256
    [void][W3]::GetWindowText($h, $t, 256)
    if ($t.ToString() -eq 'WinShotSink') { [void]$sink.Add($h) }
    return $true
}
[void][W3]::EnumWindows($cb, [IntPtr]::Zero)
if ($sink.Count -eq 0) { "no sink window"; exit 1 }

[void][W3]::PostMessage($sink[0], 0x8002, [IntPtr]::Zero, [IntPtr]::Zero)
Start-Sleep -Seconds 2

Drag 800 600 1400 1000
$sel = @(800, 600, 1400, 1000)

$s1 = Grab 'D:\Project\winshot\obj\s3_create.png'
$b1 = Band $s1 ($sel[0] + 6) ($sel[3] + 1) ($sel[3] + 90)
if (-not $b1) { "FAIL: no toolbar band below the selection"; exit 1 }
$tbTop = $b1[0]; $tbBot = $b1[1]
"toolbar band y=$tbTop..$tbBot height=$($tbBot - $tbTop + 1)  (want gap 2, height 32)"
$e1 = Extent $s1 ([int](($tbTop + $tbBot) / 2))
"toolbar x=$($e1[0])..$($e1[1]) width=$($e1[1] - $e1[0] + 1)  (want left = $($sel[0]))"
$c1 = Clusters $s1 $e1[0] $e1[1] $tbTop $tbBot
"clusters ($($c1.Count)):"
foreach ($c in $c1) { "  x=$($c[0])..$($c[1]) w=$($c[1] - $c[0] + 1)" }

# Click the first slot (rect tool) and expect the property bar underneath.
$cell = [int](($e1[1] - $e1[0] - 8) / 17)
$firstX = $e1[0] + 4 + [int]($cell / 2)
$midY = [int](($tbTop + $tbBot) / 2)

MoveTo $firstX $midY
Start-Sleep -Milliseconds 900
$h = Grab 'D:\Project\winshot\obj\s3_hover.png'
$hp = $h.GetPixel($firstX, $tbTop + 3)
"hover cell pixel = #{0:X2}{1:X2}{2:X2}  (plain chrome = EBEFF3, hot ~ D3D6DA)" -f $hp.R, $hp.G, $hp.B
& powershell -NoProfile -File 'D:\Project\winshot\tools\enum_children.ps1' | Select-String 'Toolbar'

"`nclicking first slot at ($firstX,$midY) cell=$cell"
Click $firstX $midY

$s2 = Grab 'D:\Project\winshot\obj\s3_tool.png'
$b2 = Band $s2 ($e1[0] + 6) ($tbBot + 1) ($tbBot + 90)
if (-not $b2) { "FAIL: no property bar under the toolbar" }
else {
    "property bar y=$($b2[0])..($b2[1]) height=$($b2[1] - $b2[0] + 1)  (want gap 2, height 37)"
    $e2 = Extent $s2 ([int](($b2[0] + $b2[1]) / 2))
    "property bar x=$($e2[0])..$($e2[1]) width=$($e2[1] - $e2[0] + 1)  (want left = $($e1[0]), width 246)"
}

# The active tool should now have a frame; check the first cell for a grey fill.
$act = $s2.GetPixel($firstX - $cell / 2 + 2, $tbTop + 3)
"active cell pixel = #{0:X2}{1:X2}{2:X2}" -f $act.R, $act.G, $act.B

[void][System.Windows.Forms.SendKeys]::SendWait("{ESC}")
Start-Sleep -Milliseconds 500
"winshot still running: $(-not $p.HasExited)"
if (-not $p.HasExited) { $p.Kill() }
