# The arrow head has to read as an arrow head, and the three widths have to read
# as three different triangles: the widest keeps the reference size and the two
# thinner ones are two thirds and a half of it. The measure that shows both is the
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
function IsBlue($c) { return ($c.B -gt 150 -and ($c.B - $c.R) -gt 60 -and ($c.B - $c.G) -gt 30) }

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

# The three width dots are the three leftmost blue blobs in the strip the tool
# bar hangs below the selection; the palette's own blue chips sit further right.
# The first dot is the narrowest pen. Blob positions beat the bar's chrome band,
# which its own icons and chips chop into pieces too small to recognise.
$s = Grab 'D:\Project\winshot\obj\ah_bar.png'
$by0 = $tr.bottom + 2
$by1 = $tr.bottom + [int][Math]::Round(40 * $scale)
$blueY = @{}
for ($x = $tr.left; $x -lt $tr.right; $x++) {
    $n = 0
    for ($y = $by0; $y -le $by1; $y++) {
        if (IsBlue ($s.GetPixel($x, $y))) {
            if (-not $blueY.ContainsKey($x)) { $blueY[$x] = @() }
            $blueY[$x] += $y
        }
    }
}
$s.Dispose()
$runs = New-Object System.Collections.ArrayList
$cur = $null
foreach ($x in ($blueY.Keys | Sort-Object)) {
    if ($null -ne $cur -and $x -gt $cur[1] + 2) { [void]$runs.Add($cur); $cur = $null }
    if ($null -eq $cur) { $cur = @($x, $x) } else { $cur[1] = $x }
}
if ($null -ne $cur) { [void]$runs.Add($cur) }
"blue runs below the toolbar (y $by0..$by1): $((($runs | ForEach-Object { "$($_[0])..$_[1]" }) -join ' '))"
if ($runs.Count -lt 3) { 'FAIL: the three width dots are not all there'; exit 1 }
$dotX = @(); $dotY = @()
foreach ($d in $runs[0], $runs[1], $runs[2]) {
    $dotX += [int](($d[0] + $d[1]) / 2)
    $all = @()
    for ($x = $d[0]; $x -le $d[1]; $x++) { $all += $blueY[$x] }
    $dotY += [int](($all | Measure-Object -Average).Average)
}
"dot centres: $(for ($i = 0; $i -lt 3; $i++) { "($($dotX[$i]),$($dotY[$i]))" })"

# One arrow per width, each in its own band of the selection, so the three heads
# can be measured one at a time. Horizontal, so a head's width is a straight
# vertical run.
$heads = @()
for ($i = 0; $i -lt 3; $i++) {
    Click $dotX[$i] $dotY[$i]
    # 130 apart with a 110px scan window: the bands must not overlap or the
    # previous arrow's ink lands in this one's box.
    $ay = 680 + 130 * $i
    Drag 900 $ay 1300 $ay
    Start-Sleep -Milliseconds 250

    $s = Grab "D:\Project\winshot\obj\ah_w$i.png"
    $box = Ink-Box $s 860 ($ay - 55) 1400 ($ay + 55)
    if (-not $box) { $s.Dispose(); "FAIL: the arrow for width $i was never drawn"; exit 1 }
    # Ink width straight across the arrow, measured back from the tip. The head
    # is a triangle with its base square across the shaft, so the widest column
    # in that profile is the head's own width and the far columns are the shaft.
    $prof = @(0..44 | ForEach-Object { Cross $s ($box.r - $_) $box.t $box.b })
    $s.Dispose()
    $shaft = ($prof[38..44] | Measure-Object -Minimum).Minimum
    $head = ($prof[0..34] | Measure-Object -Maximum).Maximum
    $flare = 0
    foreach ($d in 0..34) { if ($prof[$d] -gt $shaft) { $flare = $d } }
    "width $i : shaft=$shaft  head=$head  flare reaches $flare px back"
    $heads += , @{ shaft = $shaft; head = $head; flare = $flare }
}

$wide = $heads[2]; $mid = $heads[1]; $thin = $heads[0]
"head widths: thin=$($thin.head) mid=$($mid.head) wide=$($wide.head)"
foreach ($h in $heads) {
    if ($h.head -lt $h.shaft + 8) {
        $fail += "a $($h.shaft)px arrow head is only $($h.head) px wide, no visible flare"
    }
    if ($h.flare -lt 8) { $fail += "an arrow head flares for only $($h.flare) px" }
}
if ($mid.head -lt [int]($wide.head * 0.55) -or $mid.head -gt [int]($wide.head * 0.80)) {
    $fail += "the medium head is $($mid.head) px against the wide $($wide.head) px, want about two thirds"
}
if ($thin.head -lt [int]($wide.head * 0.38) -or $thin.head -gt [int]($wide.head * 0.62)) {
    $fail += "the thin head is $($thin.head) px against the wide $($wide.head) px, want about a half"
}
if ($mid.head -le $thin.head) { $fail += 'the medium head is no wider than the thin one' }
if ($wide.head -le $mid.head) { $fail += 'the wide head is no wider than the medium one' }

if (-not $proc.HasExited) { $proc.Kill() }
if ($fail.Count) { "FAILURES: $($fail.Count)"; $fail | ForEach-Object { "  $_" }; exit 1 }
'PASS'
