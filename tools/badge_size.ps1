# The 序号 disc used to be one fixed radius whatever the width dots said, because
# ShapeBadge::SetStyle ignored the pen. The request is for the current size to be
# the middle step, with a smaller and a larger one either side, driven off the same
# three dots every other tool uses.
#
#   BadgeRadiusForPen: pen<=3 -> 10, pen<=6 -> 13, else 17. The three dots are 2,
#   4 and 8 px, so the discs come out 20, 26 and 34 px across.
#
# Each disc is measured on its own centre row, where the span of solidly inked
# columns is the diameter. The white digit sits inside that span and the selection
# guide, when there is one, is stroked on the disc's own box, so neither changes
# the outermost ink. The click lands on a whole pixel and the disc's radius is
# whole too, so the edge straddles the outermost column on one side: measured, the
# 20px disc gives 19 columns of full ink with a ~40% covered one on each side of
# them. That is what the +-2 tolerance is for, and what the feathering test below
# is for.
#
# The anti-aliasing is measured rather than assumed: the row is walked in from
# outside, and the pixels between the last one that still matches the desktop
# behind the disc and the first fully inked one are the feathered edge. A hard
# edged FillEllipse has none of those, because the disc's edge then lands on a
# whole pixel and either covers it or does not. The background is sampled next to
# the disc rather than assumed, because what sits there is whatever the frozen
# desktop happens to be.
#
# Each disc is measured before the next width is picked: selecting a badge and
# clicking another width dot resizes it, which is the other half of the request,
# and by then the measurement is already taken.
Add-Type -AssemblyName System.Drawing, System.Windows.Forms
Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class BS {
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
function MoveTo([int]$x, [int]$y) {
    [void][BS]::mouse_event(0x8001, [uint32][int][Math]::Floor(65535 * $x / 3840),
                            [uint32][int][Math]::Floor(65535 * $y / 2160), 0,
                            [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 90
}
function Down { [void][BS]::mouse_event($LEFTDOWN, 0, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 150 }
function Up { [void][BS]::mouse_event($LEFTUP, 0, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 350 }
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
    $cb = [BS+EnumProc] {
        param($h, $l)
        $t = New-Object System.Text.StringBuilder 256
        [void][BS]::GetWindowText($h, $t, 256)
        if ($t.ToString() -eq $title) { [void]$found.Add($h) }
        return $true
    }
    [void][BS]::EnumWindows($cb, [IntPtr]::Zero)
    return $found.ToArray()
}
function Find-Kids([IntPtr]$parent, [string]$title) {
    $found = New-Object System.Collections.ArrayList
    $cb = [BS+EnumProc] {
        param($h, $l)
        $t = New-Object System.Text.StringBuilder 256
        [void][BS]::GetWindowText($h, $t, 256)
        if ($t.ToString() -eq $title -and [BS]::IsWindowVisible($h)) { [void]$found.Add($h) }
        return $true
    }
    [void][BS]::EnumChildWindows($parent, $cb, [IntPtr]::Zero)
    return $found.ToArray()
}
function Rect-Of([IntPtr]$h) {
    $r = New-Object BS+RECT
    [void][BS]::GetWindowRect($h, [ref]$r)
    return $r
}
# tb::kPalette's default red, (247,56,64).
function IsInk($c) { return ($c.R -gt 190 -and $c.G -lt 120 -and $c.B -lt 130) }
function Near($c, $bg) {
    return ([Math]::Abs($c.R - $bg.R) + [Math]::Abs($c.G - $bg.G) +
            [Math]::Abs($c.B - $bg.B)) -lt 40
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
# Widest span of solidly inked columns within +-40 px of the click, over the few
# rows around it: the click may land a pixel off the disc's true middle row.
function Disc-Span($bmp, [int]$cx, [int]$cy) {
    $best = 0; $by = $cy; $bl = 0; $br = 0
    for ($y = $cy - 3; $y -le $cy + 3; $y++) {
        $l = -1; $r = -1
        for ($x = $cx - 40; $x -le $cx + 40; $x++) {
            if (IsInk ($bmp.GetPixel($x, $y))) { if ($l -lt 0) { $l = $x }; $r = $x }
        }
        if ($l -ge 0 -and ($r - $l + 1) -gt $best) { $best = $r - $l + 1; $by = $y; $bl = $l; $br = $r }
    }
    return @{ w = $best; y = $by; l = $bl; r = $br }
}
# How many pixels between the desktop and the first fully inked column on each
# side: the anti-aliasing. Sampled from outside in, so the white digit and the
# disc's own body never enter it.
function Feather($bmp, [int]$y, [int]$edge, [int]$dx) {
    $bg = $bmp.GetPixel($edge + $dx * 6, $y)
    $n = 0
    for ($k = 5; $k -ge 1; $k--) {
        $c = $bmp.GetPixel($edge + $dx * $k, $y)
        if (Near $c $bg) { continue }
        if (IsInk $c) { break }
        $n++
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
[void][BS]::PostMessage($sink[0], 0x8002, [IntPtr]::Zero, [IntPtr]::Zero)
Start-Sleep -Seconds 2
$ov = @(Find-Wins 'WinShotOverlay')
if ($ov.Count -eq 0) { 'FAIL: no overlay window'; exit 1 }

Drag 700 500 2200 1500
$b = Slot 6
if (-not $b) { 'FAIL: no toolbar'; exit 1 }
Click $b[0] $b[1]              # the 序号 tool arms the width dots
Start-Sleep -Milliseconds 500

$cx = @(1000, 1300, 1600)
$cy = 800
$diam = @(0, 0, 0)
$feather = @(0, 0, 0)
for ($i = 0; $i -le 2; $i++) {
    $d = Width-Dot $i
    if (-not $d) { 'FAIL: no property bar'; exit 1 }
    Click $d[0] $d[1]
    Start-Sleep -Milliseconds 300
    Click $cx[$i] $cy
    Start-Sleep -Milliseconds 500
    $g = Grab "D:\Project\winshot\obj\bs_badge$i.png"
    $s = Disc-Span $g $cx[$i] $cy
    $diam[$i] = $s.w
    $feather[$i] = [Math]::Min((Feather $g $s.y $s.l -1), (Feather $g $s.y $s.r 1))
    $g.Dispose()
    "badge at width dot ${i}: disc $($s.w) px across at row $($s.y), feather $($feather[$i]) px"
}
"disc diameters: $($diam[0]) -> $($diam[1]) -> $($diam[2]) (want 20/26/34)"
"edge feathering: $($feather -join ' / ') (want at least 1 on each disc)"
for ($i = 0; $i -le 2; $i++) {
    $want = @(20, 26, 34)[$i]
    if ([Math]::Abs($diam[$i] - $want) -gt 2) {
        $fail += "the disc at width dot $i is $($diam[$i]) px across, want about ${want}"
    }
    if ($feather[$i] -lt 1) {
        $fail += "the disc at width dot $i has a hard edge: no partially covered pixel where its edge crosses the centre row"
    }
}
if (-not ($diam[0] -lt $diam[1] -and $diam[1] -lt $diam[2])) {
    $fail += "the discs do not grow with the width dot: $($diam -join ', ')"
}

Keys '{ESC}'
Start-Sleep -Milliseconds 400
if (-not $proc.HasExited) { $proc.Kill() }
if ($fail.Count) { "FAILURES: $($fail.Count)"; $fail | ForEach-Object { "  $_" }; exit 1 }
'PASS'
