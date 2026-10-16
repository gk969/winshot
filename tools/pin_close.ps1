# A pinned image needs a ✕ in its top-right corner and must not resize from its
# edges: every part of it but the ✕ is HTCAPTION, so an edge drag moves the pin
# instead of reshaping it.
#
# The ✕ is a 22px dark badge 5px in from the corner with a white cross, so it is
# found by counting dark badge pixels and white cross pixels inside that rect.
Add-Type -AssemblyName System.Drawing, System.Windows.Forms
Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class PC {
    public delegate bool EnumProc(IntPtr h, IntPtr l);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
    [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr p, EnumProc cb, IntPtr l);
    [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint msg, IntPtr w, IntPtr l);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
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
    [void][PC]::mouse_event($LEFTDOWN, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 120
    for ($i = 1; $i -le 12; $i++) {
        MoveTo ([int]($x1 + ($x2-$x1) * $i / 12)) ([int]($y1 + ($y2-$y1) * $i / 12))
    }
    Start-Sleep -Milliseconds 150
    [void][PC]::mouse_event($LEFTUP, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 350
}
function Click([int]$x, [int]$y) {
    MoveTo $x $y
    [void][PC]::mouse_event($LEFTDOWN, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 120
    [void][PC]::mouse_event($LEFTUP, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 350
}
function Find-Wins([string]$title) {
    $found = New-Object System.Collections.ArrayList
    $cb = [PC+EnumProc] {
        param($h, $l)
        $t = New-Object System.Text.StringBuilder 256
        [void][PC]::GetWindowText($h, $t, 256)
        if ($t.ToString() -eq $title) { [void]$found.Add($h) }
        return $true
    }
    [void][PC]::EnumWindows($cb, [IntPtr]::Zero)
    return $found.ToArray()
}
function Rect-Of([IntPtr]$h) {
    $r = New-Object PC+RECT
    [void][PC]::GetWindowRect($h, [ref]$r)
    return $r
}
# Dark badge pixels and white cross pixels inside a rect.
function Badge-Count($bmp, [int]$x0, [int]$y0, [int]$x1, [int]$y1) {
    $d = 0; $w = 0
    for ($y = $y0; $y -lt $y1; $y++) {
        for ($x = $x0; $x -lt $x1; $x++) {
            $c = $bmp.GetPixel($x, $y)
            if ($c.R -lt 120 -and $c.G -lt 120 -and $c.B -lt 120) { $d++ }
            elseif ($c.R -gt 200 -and $c.G -gt 200 -and $c.B -gt 200) { $w++ }
        }
    }
    return @($d, $w)
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
[void][PC]::PostMessage($sink[0], 0x8002, [IntPtr]::Zero, [IntPtr]::Zero)
Start-Sleep -Seconds 2

Drag $sel[0] $sel[1] $sel[2] $sel[3]

# The toolbar is its own window, so its rect gives the exact left edge. Deriving
# the slot pitch from the bar's width instead puts slot 10 on the wrong icon,
# because the last slot ("完成") carries a text label and is wider than the rest.
# The layout constants, scaled by the bar's own height, are exact.
$ov = @(Find-Wins 'WinShotOverlay')
if ($ov.Count -eq 0) { 'FAIL: no overlay window'; exit 1 }
$kids = New-Object System.Collections.ArrayList
$cb2 = [PC+EnumProc] {
    param($h, $l)
    $t = New-Object System.Text.StringBuilder 256
    [void][PC]::GetWindowText($h, $t, 256)
    if ($t.ToString() -eq 'WinShotToolbar') { [void]$kids.Add($h) }
    return $true
}
[void][PC]::EnumChildWindows($ov[0], $cb2, [IntPtr]::Zero)
if ($kids.Count -eq 0) { 'FAIL: no toolbar window under the overlay'; exit 1 }
$tr = Rect-Of $kids[0]
$scale = ($tr.bottom - $tr.top) / 32.0
"toolbar ($($tr.left),$($tr.top))..($($tr.right),$($tr.bottom)) scale=$scale"
if ($scale -lt 0.5 -or $scale -gt 4) { "FAIL: implausible toolbar height"; exit 1 }
$cell = [int][Math]::Round(27 * $scale)
$sep = [int][Math]::Round(14 * $scale)
$pad = [int][Math]::Round(4 * $scale)
# Slots 0..6 are the shape tools, then a separator, then Undo, LongShot, OCR, Pin.
$pinX = $tr.left + $pad + 10 * $cell + $sep + [int]($cell / 2)
$midY = [int](($tr.top + $tr.bottom) / 2)
"clicking 钉在桌面上 at ($pinX,$midY)"
Click $pinX $midY
Start-Sleep -Milliseconds 800

$pins = @(Find-Wins 'WinShotPin')
"pin windows: $($pins.Count)"
if ($pins.Count -ne 1) { 'FAIL: the pin did not appear'; exit 1 }
$r = Rect-Of $pins[0]
"w=$($r.right - $r.left) h=$($r.bottom - $r.top) at ($($r.left),$($r.top))"

# --- the ✕ badge -------------------------------------------------------------
# 22px, 5px in from the top-right corner.
$s = Grab 'D:\Project\winshot\obj\pc_pin.png'
$bx1 = $r.right - 5; $bx0 = $bx1 - 22; $by0 = $r.top + 5; $by1 = $by0 + 22
$cnt = Badge-Count $s $bx0 $by0 $bx1 $by1
# The same size one step further in, which is plain image and must not read as a
# badge: without this a uniformly dark pin would pass.
$off = Badge-Count $s ($bx0 - 30) $by0 ($bx1 - 30) $by1
$s.Dispose()
"badge rect ($bx0,$by0)..($bx1,$by1): dark=$($cnt[0]) white=$($cnt[1])  (image beside it: dark=$($off[0]) white=$($off[1]))"
if ($cnt[0] -lt 150 -or $cnt[1] -lt 40) {
    $fail += "no ✕ badge in the pin's top-right corner (dark $($cnt[0]), white $($cnt[1]))"
}

# --- an edge drag moves the pin rather than resizing it ----------------------
$w0 = $r.right - $r.left; $h0 = $r.bottom - $r.top
$ex = $r.right - 3
$ey = [int](($r.top + $r.bottom) / 2)
Drag $ex $ey ($ex - 60) $ey
$r2 = Rect-Of @(Find-Wins 'WinShotPin')[0]
$w1 = $r2.right - $r2.left; $h1 = $r2.bottom - $r2.top
"edge drag from x=${ex}: now w=$w1 h=$h1 at ($($r2.left),$($r2.top))  (was w=$w0 h=$h0)"
if ($w1 -ne $w0 -or $h1 -ne $h0) {
    $fail += "dragging the pin's edge resized it ($w0 x $h0 -> $w1 x $h1)"
}

# --- the ✕ closes it ---------------------------------------------------------
# The drag moved the pin, so the badge has to be located from where it is now.
$bx0 = $r2.right - 5 - 22; $bx1 = $r2.right - 5
$by0 = $r2.top + 5; $by1 = $by0 + 22
$cx = [int](($bx0 + $bx1) / 2); $cy = [int](($by0 + $by1) / 2)
Click $cx $cy
Start-Sleep -Milliseconds 600
$left = @(Find-Wins 'WinShotPin').Count
"pin windows after clicking the ✕ at ($cx,$cy): $left (want 0)"
if ($left -ne 0) { $fail += 'clicking the ✕ did not close the pin' }

if (-not $proc.HasExited) { $proc.Kill() }
if ($fail.Count) { "FAILURES: $($fail.Count)"; $fail | ForEach-Object { "  $_" }; exit 1 }
'PASS'
