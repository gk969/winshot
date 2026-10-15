Add-Type -AssemblyName System.Drawing, System.Windows.Forms
Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class W6L {
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

# 96dpi display: the app's logical sizes are its physical sizes.
$BOXW = 117; $BOXH = 85; $INFOH = 62; $SCALE = 5
$CARDH = $BOXH + $INFOH - 1

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
    Start-Sleep -Milliseconds 120
}
function Click([int]$x, [int]$y) {
    MoveTo $x $y
    [void][W6L]::mouse_event($LEFTDOWN, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 120
    [void][W6L]::mouse_event($LEFTUP, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 350
}
function Near($c, [int]$r, [int]$g, [int]$b, [int]$tol) {
    return ([Math]::Abs($c.R - $r) -le $tol -and [Math]::Abs($c.G - $g) -le $tol -and
            [Math]::Abs($c.B - $b) -le $tol)
}
function IsFrame($c) { return (Near $c 52 52 52 14) }
function IsInfo($c) { return (Near $c 51 51 51 10) }
# Tight: the selection frame's anti-aliased edge passes through this colour at
# a looser tolerance, and a full-screen frame contributes ~580 such pixels in
# every shot, which would mask the loupe entirely.
function IsCross($c) { return (Near $c 77 202 250 12) }
function CrossCount($bmp, [int]$x0, [int]$y0, [int]$x1, [int]$y1) {
    if ($x0 -lt 0) { $x0 = 0 }
    if ($y0 -lt 0) { $y0 = 0 }
    if ($x1 -gt $bmp.Width - 1) { $x1 = $bmp.Width - 1 }
    if ($y1 -gt $bmp.Height - 1) { $y1 = $bmp.Height - 1 }
    $n = 0
    for ($y = $y0; $y -le $y1; $y++) {
        for ($x = $x0; $x -le $x1; $x++) { if (IsCross ($bmp.GetPixel($x, $y))) { $n++ } }
    }
    return $n
}
function InkCount($bmp, [int]$x0, [int]$y0, [int]$x1, [int]$y1) {
    $n = 0
    for ($y = $y0; $y -le $y1; $y++) {
        for ($x = $x0; $x -le $x1; $x++) {
            $c = $bmp.GetPixel($x, $y)
            if ($c.R -gt 150 -and $c.G -gt 150 -and $c.B -gt 150) { $n++ }
        }
    }
    return $n
}
# CardRect, mirrored from the app: centred on the cursor, clamped to the screen.
function Card([int]$x, [int]$y) {
    $l = $x - [int]($BOXW / 2); $t = $y - [int]($BOXH / 2)
    if ($l -lt 0) { $l = 0 }
    if ($l + $BOXW -gt $scrW) { $l = $scrW - $BOXW }
    if ($t -lt 0) { $t = 0 }
    if ($t + $CARDH -gt $scrH) { $t = $scrH - $CARDH }
    return @($l, $t)
}
function VisibleBars($overlay) {
    $list = New-Object System.Collections.ArrayList
    $cb = [W6L+EnumProc] {
        param($h, $l)
        if ([W6L]::IsWindowVisible($h)) {
            $r = New-Object W6L+RECT
            if ([W6L]::GetWindowRect($h, [ref]$r)) {
                if (($r.right - $r.left) -gt 40 -and ($r.bottom - $r.top) -gt 10) {
                    [void]$list.Add(@{ h = $h; left = $r.left; top = $r.top;
                                       right = $r.right; bottom = $r.bottom })
                }
            }
        }
        return $true
    }
    [void][W6L]::EnumChildWindows($overlay, $cb, [IntPtr]::Zero)
    return $list
}

$scrB = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
$scrW = $scrB.Width; $scrH = $scrB.Height

Get-Process winshot -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 600
Get-ChildItem 'D:\Project\winshot\obj\s6_*.png' -ErrorAction SilentlyContinue | Remove-Item -Force

$fail = @()

# The loupe magnifies the frozen still, so the reference for every colour check
# is the desktop as it looks one moment before the hotkey.
MoveTo 3000 1900
Start-Sleep -Milliseconds 400
$before = Grab 'D:\Project\winshot\obj\s6_before.png'

$proc = Start-Process -FilePath 'D:\Project\winshot\x64\Debug\winshot.exe' -PassThru
Start-Sleep -Seconds 2

$sink = New-Object System.Collections.ArrayList
$ov = New-Object System.Collections.ArrayList
$cb = [W6L+EnumProc] {
    param($h, $l)
    $t = New-Object System.Text.StringBuilder 256
    [void][W6L]::GetWindowText($h, $t, 256)
    if ($t.ToString() -eq 'WinShotSink') { [void]$sink.Add($h) }
    if ($t.ToString() -eq 'WinShotOverlay') { [void]$ov.Add($h) }
    return $true
}
[void][W6L]::EnumWindows($cb, [IntPtr]::Zero)
if ($sink.Count -eq 0) { "FAIL: no sink window"; exit 1 }

[void][W6L]::PostMessage($sink[0], 0x8002, [IntPtr]::Zero, [IntPtr]::Zero)
Start-Sleep -Seconds 2
if ($ov.Count -eq 0) {
    $ov = New-Object System.Collections.ArrayList
    [void][W6L]::EnumWindows($cb, [IntPtr]::Zero)
}
if ($ov.Count -eq 0) { "FAIL: no overlay window"; exit 1 }

# A flat patch of desktop: the only place where an exact colour match proves the
# magnifier is sampling the still rather than the live screen.
$X = -1; $Y = -1
for ($cy = 400; $cy -le ($scrH - 500) -and $X -lt 0; $cy += 40) {
    for ($cx = 400; $cx -le ($scrW - 500); $cx += 40) {
        $ref = $before.GetPixel($cx, $cy)
        $flat = $true
        for ($yy = 0; $yy -lt 40 -and $flat; $yy += 4) {
            for ($xx = 0; $xx -lt 40; $xx += 4) {
                $c = $before.GetPixel($cx + $xx, $cy + $yy)
                if (-not (Near $c $ref.R $ref.G $ref.B 10)) { $flat = $false; break }
            }
        }
        if ($flat) { $X = $cx + 20; $Y = $cy + 20; break }
    }
}
if ($X -lt 0) { "FAIL: no flat desktop patch to sample"; exit 1 }
$src = $before.GetPixel($X, $Y)
"sample point: $X,$Y rgb=($($src.R),$($src.G),$($src.B))"

MoveTo $X $Y
Start-Sleep -Milliseconds 400
$s1 = Grab 'D:\Project\winshot\obj\s6_full1.png'

$cd = Card $X $Y
$L = $cd[0]; $T = $cd[1]
"card: $L,$T .. $($L + $BOXW - 1),$($T + $CARDH - 1)"
$fx = $L + 1; $fy = $T + 1; $fw = $BOXW - 2; $fh = $BOXH - 2
$iy = $T + $BOXH - 1

# --- frame, field, crosshair, readout --------------------------------------
# Top row and the two side columns: the box's bottom row belongs to the
# readout, which is why there is no frame colour to find down there.
$ring = @( @($L, $T), @(($L + 58), $T), @($L, ($T + 40)), @(($L + $BOXW - 1), ($T + 40)), @($L, ($T + $BOXH - 2)) )
foreach ($p in $ring) {
    if (-not (IsFrame ($s1.GetPixel($p[0], $p[1])))) {
        $c = $s1.GetPixel($p[0], $p[1])
        $fail += "frame ring at $($p[0]),$($p[1]) is rgb=($($c.R),$($c.G),$($c.B))"
    }
}

# Source window is field/5 centred on the cursor, so the sampled pixel sits at
# (fw/2, fh/2) in the field and every source pixel is a SCALE x SCALE block.
$bx = $fx + [int]($fw / $SCALE / 2) * $SCALE + 3 * $SCALE
$by = $fy + [int]($fh / $SCALE / 2) * $SCALE + 3 * $SCALE
$sum = 0; $spread = 0
$first = $s1.GetPixel($bx, $by)
for ($yy = 0; $yy -lt $SCALE; $yy++) {
    for ($xx = 0; $xx -lt $SCALE; $xx++) {
        $c = $s1.GetPixel($bx + $xx, $by + $yy)
        $sum += [Math]::Abs($c.R - $src.R) + [Math]::Abs($c.G - $src.G) + [Math]::Abs($c.B - $src.B)
        $spread = [Math]::Max($spread, [Math]::Abs($c.R - $first.R))
        $spread = [Math]::Max($spread, [Math]::Abs($c.G - $first.G))
        $spread = [Math]::Max($spread, [Math]::Abs($c.B - $first.B))
    }
}
$mean = [int]($sum / ($SCALE * $SCALE))
"field block at ${bx},${by} mean diff=$mean spread=$spread (want <20 / <8)"
if ($mean -ge 20) { $fail += 'field does not show the still under the cursor' }
if ($spread -ge 8) { $fail += 'field block not upscaled uniformly' }

$cross = CrossCount $s1 $fx $fy ($fx + $fw - 1) ($fy + $fh - 1)
"crosshair px in field: $cross (want > 300)"
if ($cross -lt 300) { $fail += 'no crosshair in the field' }
# The crosshair has to sit on the cursor, not on the field's centre alone: the
# two agree only while the centring chain is right.
$bad = 0
for ($yy = $fy + 10; $yy -lt $fy + $fh - 10; $yy += 7) {
    $hit = $false
    for ($xx = $X - 3; $xx -le $X + 3; $xx++) { if (IsCross ($s1.GetPixel($xx, $yy))) { $hit = $true; break } }
    if (-not $hit) { $bad++ }
}
for ($xx = $fx + 10; $xx -lt $fx + $fw - 10; $xx += 7) {
    $hit = $false
    for ($yy = $Y - 3; $yy -le $Y + 3; $yy++) { if (IsCross ($s1.GetPixel($xx, $yy))) { $hit = $true; break } }
    if (-not $hit) { $bad++ }
}
"crosshair off-cursor rows/cols: $bad (want 0)"
if ($bad -gt 0) { $fail += "crosshair not on the cursor ($bad)" }

$backPts = @( @(($L + 2), ($iy + 59)), @(($L + $BOXW - 3), ($iy + 30)), @(($L + 2), ($iy + 2)) )
foreach ($p in $backPts) {
    if (-not (IsInfo ($s1.GetPixel($p[0], $p[1])))) {
        $c = $s1.GetPixel($p[0], $p[1])
        $fail += "readout back at $($p[0]),$($p[1]) is rgb=($($c.R),$($c.G),$($c.B))"
    }
}
$ink = InkCount $s1 ($L + 6) ($iy + 1) ($L + $BOXW - 7) ($iy + $INFOH - 2)
"readout ink: $ink px (want > 150)"
if ($ink -lt 150) { $fail += 'readout has no text' }

[void](Crop $s1 ($L - 6) ($T - 6) ($BOXW + 12) ($CARDH + 12) 'D:\Project\winshot\obj\s6_loupe.png')
[void](Crop $before ($X - 40) ($Y - 40) 80 80 'D:\Project\winshot\obj\s6_source.png')

# --- 按c复制色号 ------------------------------------------------------------
$want = 'RGB:({0},{1},{2})' -f $src.R, $src.G, $src.B
$got = ''
for ($try = 0; $try -lt 3; $try++) {
    [void][System.Windows.Forms.SendKeys]::SendWait('c')
    Start-Sleep -Milliseconds 400
    try { $got = [System.Windows.Forms.Clipboard]::GetText() } catch { $got = '' }
    if ($got -eq $want) { break }
}
"clipboard: '$got' (want '$want')"
if ($got -ne $want) { $fail += "c did not copy the sampled colour (got '$got')" }

# --- the magnifier gets out of the way -------------------------------------
$bars = @(VisibleBars $ov[0])
"visible bars: $($bars.Count)"
foreach ($b in $bars) { "  child $($b.left),$($b.top) .. $($b.right),$($b.bottom)" }
if ($bars.Count -eq 0) { $fail += 'no toolbar found to hide behind'; $bars = @(@{ left = 0; top = ($scrH - 40); right = 400; bottom = ($scrH - 8) }) }
# EnumChildWindows is recursive, so the widest one is the toolbar itself.
$bar = @($bars | Sort-Object { ($_.right - $_.left) } -Descending)[0]
"toolbar: $($bar.left),$($bar.top) .. $($bar.right),$($bar.bottom)"
$bx2 = [int](($bar.left + $bar.right) / 2); $by2 = [int](($bar.top + $bar.bottom) / 2)
$cd2 = Card $bx2 $by2
MoveTo $bx2 $by2
Start-Sleep -Milliseconds 400
$s2 = Grab 'D:\Project\winshot\obj\s6_full2.png'
$hidden = CrossCount $s2 ($cd2[0] - 4) ($cd2[1] - 4) ($cd2[0] + $BOXW + 3) ($cd2[1] + $CARDH + 3)
"crosshair px over the toolbar: $hidden (want 0)"
if ($hidden -gt 20) { $fail += 'magnifier still drawn over the toolbar' }

MoveTo $X $Y
Start-Sleep -Milliseconds 400
$s3 = Grab 'D:\Project\winshot\obj\s6_full3.png'
$back = CrossCount $s3 $fx $fy ($fx + $fw - 1) ($fy + $fh - 1)
"crosshair px after moving back: $back (want > 300)"
if ($back -lt 300) { $fail += 'magnifier did not come back' }

# --- and hides while a tool is armed ---------------------------------------
$rx = $bar.left + 4 + 13; $ry = [int](($bar.top + $bar.bottom) / 2)
for ($try = 0; $try -lt 3; $try++) {
    Click $rx $ry
    if (@(VisibleBars $ov[0]).Count -ge 2) { break }
}
$armed = @(VisibleBars $ov[0]).Count -ge 2
"tool armed (property bar up): $armed"
if (-not $armed) { $fail += 'could not arm the rect tool' }
else {
    MoveTo $X $Y
    Start-Sleep -Milliseconds 400
    $s4 = Grab 'D:\Project\winshot\obj\s6_full4.png'
    $withTool = CrossCount $s4 $fx $fy ($fx + $fw - 1) ($fy + $fh - 1)
    "crosshair px with a tool armed: $withTool (want 0)"
    if ($withTool -gt 20) { $fail += 'magnifier drawn while a tool is armed' }
}

if ($fail.Count) { "FAIL: " + ($fail -join '; '); exit 1 }
"PASS"
if (-not $proc.HasExited) { $proc.Kill() }
