# The arrow head has to read as an arrow head. The measure that shows it is the
# ink width straight across the arrow near its tip: a head flares to several times
# the shaft, a headless line stays one width throughout.
Add-Type -AssemblyName System.Drawing, System.Windows.Forms
Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class AH {
    public delegate bool EnumProc(IntPtr h, IntPtr l);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
    [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr p, EnumProc cb, IntPtr l);
    [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
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
function Drag([int]$x1, [int]$y1, [int]$x2, [int]$y2) {
    MoveTo $x1 $y1
    [void][AH]::mouse_event($LEFTDOWN, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 120
    for ($i = 1; $i -le 12; $i++) {
        MoveTo ([int]($x1 + ($x2-$x1) * $i / 12)) ([int]($y1 + ($y2-$y1) * $i / 12))
    }
    Start-Sleep -Milliseconds 150
    [void][AH]::mouse_event($LEFTUP, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 350
}
function Click([int]$x, [int]$y) {
    MoveTo $x $y
    [void][AH]::mouse_event($LEFTDOWN, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 120
    [void][AH]::mouse_event($LEFTUP, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 350
}
function Find-Wins([string]$title) {
    $found = New-Object System.Collections.ArrayList
    $cb = [AH+EnumProc] {
        param($h, $l)
        $t = New-Object System.Text.StringBuilder 256
        [void][AH]::GetWindowText($h, $t, 256)
        if ($t.ToString() -eq $title) { [void]$found.Add($h) }
        return $true
    }
    [void][AH]::EnumWindows($cb, [IntPtr]::Zero)
    return $found.ToArray()
}
function Rect-Of([IntPtr]$h) {
    $r = New-Object AH+RECT
    [void][AH]::GetWindowRect($h, [ref]$r)
    return $r
}
function IsRed($c) { return ($c.R -gt 190 -and $c.G -lt 120 -and $c.B -lt 130) }
function Ink-Box($bmp, [int]$x0, [int]$y0, [int]$x1, [int]$y1) {
    $l = -1; $t = -1; $r = -1; $b = -1; $n = 0
    for ($y = $y0; $y -le $y1; $y++) {
        for ($x = $x0; $x -le $x1; $x++) {
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
# Run of ink pixels straight up and down through the given column.
function Cross($bmp, [int]$x, [int]$y0, [int]$y1) {
    $n = 0
    for ($y = $y0; $y -le $y1; $y++) { if (IsRed ($bmp.GetPixel($x, $y))) { $n++ } }
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

$sink = @(Find-Wins 'WinShotSink')
if ($sink.Count -eq 0) { 'FAIL: no sink window'; exit 1 }
[void][AH]::PostMessage($sink[0], 0x8002, [IntPtr]::Zero, [IntPtr]::Zero)
Start-Sleep -Seconds 2

Drag $sel[0] $sel[1] $sel[2] $sel[3]

$ov = @(Find-Wins 'WinShotOverlay')
if ($ov.Count -eq 0) { 'FAIL: no overlay window'; exit 1 }
$kids = New-Object System.Collections.ArrayList
$cb2 = [AH+EnumProc] {
    param($h, $l)
    $t = New-Object System.Text.StringBuilder 256
    [void][AH]::GetWindowText($h, $t, 256)
    if ($t.ToString() -eq 'WinShotToolbar') { [void]$kids.Add($h) }
    return $true
}
[void][AH]::EnumChildWindows($ov[0], $cb2, [IntPtr]::Zero)
if ($kids.Count -eq 0) { 'FAIL: no toolbar window under the overlay'; exit 1 }
$tr = Rect-Of $kids[0]
$scale = ($tr.bottom - $tr.top) / 32.0
"toolbar ($($tr.left),$($tr.top))..($($tr.right),$($tr.bottom)) scale=$scale"
if ($scale -lt 0.5 -or $scale -gt 4) { "FAIL: implausible toolbar height"; exit 1 }
$cell = [int][Math]::Round(27 * $scale)
$pad = [int][Math]::Round(4 * $scale)
# Slot 2 is the arrow: Rect, Ellipse, Arrow.
$arX = $tr.left + $pad + 2 * $cell + [int]($cell / 2)
$arY = [int](($tr.top + $tr.bottom) / 2)
"clicking the arrow tool at ($arX,$arY)"
Click $arX $arY

# A horizontal arrow so the head's width is a straight vertical run.
Drag 900 800 1300 800
Start-Sleep -Milliseconds 300

$s = Grab 'D:\Project\winshot\obj\ah_arrow.png'
$box = Ink-Box $s 860 700 1400 900
if (-not $box) { $s.Dispose(); 'FAIL: the arrow was never drawn'; exit 1 }
$l = $box.l; $r = $box.r

# Ink width straight across the arrow, measured back from the tip. The arrow tool
# opens on the thin dot by design, so the head is judged against the shaft it sits
# on rather than against an absolute pen width.
$prof = @(0..44 | ForEach-Object { Cross $s ($r - $_) $box.t $box.b })
$s.Dispose()
$shaft = ($prof[36..44] | Measure-Object -Minimum).Minimum
$head = ($prof[0..30] | Measure-Object -Maximum).Maximum
$headLen = 0
foreach ($d in 0..30) { if ($prof[$d] -ge $shaft + 4) { $headLen = $d } }
"profile back from the tip: " + (($prof | ForEach-Object { "$_" }) -join ' ')
"arrow ink box ($l,$($box.t))..($r,$($box.b))"
"shaft=$shaft  head=$head  head length=$headLen px"
if ($shaft -lt 1 -or $shaft -gt 4) { "FAIL: the shaft is not the arrow tool's 2px dot ($shaft)" }
if ($head -lt 18) { $fail += "the head is only $head px wide, too small to read as an arrow head" }
if ($head -lt 6 * $shaft) { $fail += "the head is $head px against a $shaft px shaft — no visible flare" }
if ($headLen -lt 20) { $fail += "the head is only $headLen px long, too stubby to read as an arrow head" }

# Crop the head for a look.
$s = Grab ''
$c = New-Object System.Drawing.Bitmap 110, 90
$g = [System.Drawing.Graphics]::FromImage($c)
$g.DrawImage($s, [System.Drawing.Rectangle]::new(0, 0, 110, 90),
                 [System.Drawing.Rectangle]::new(($r - 80), ($box.t - 20), 110, 90),
                 [System.Drawing.GraphicsUnit]::Pixel)
$g.Dispose(); $s.Dispose()
$c.Save('D:\Project\winshot\obj\ah_head.png')
$c.Dispose()

if (-not $proc.HasExited) { $proc.Kill() }
if ($fail.Count) { "FAILURES: $($fail.Count)"; $fail | ForEach-Object { "  $_" }; exit 1 }
'PASS'
