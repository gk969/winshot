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
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, IntPtr extra);
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int left, top, right, bottom; }
}
"@

$LEFTDOWN = 0x0002; $LEFTUP = 0x0004

# Windows refuses SetForegroundWindow from a process that is not already in the
# foreground, and the overlay only takes keys while it has focus. Pressing a key
# lifts that lock — the same thing a real click does.
function Force-Foreground([IntPtr]$h) {
    [void][W6L]::keybd_event(0x12, 0, 0, [IntPtr]::Zero)        # VK_MENU down
    [void][W6L]::keybd_event(0x12, 0, 2, [IntPtr]::Zero)        # VK_MENU up
    [void][W6L]::SetForegroundWindow($h)
}

# 96dpi display: the app's logical sizes are its physical sizes.
$BOXW = 117; $BOXH = 85; $INFOH = 62; $SCALE = 5; $GAP = 30
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
# loupe::CardRect, mirrored from the app: below-right of the cursor by $GAP so
# the card never covers the pixel it is reading, stepping to the right and then
# above only where that corner would run off the screen.
function Card([int]$x, [int]$y) {
    $l = $x + $GAP; $t = $y + $GAP
    if ($t + $CARDH -gt $scrH) { $t = $y - [int]($CARDH / 2) }
    if ($l + $BOXW -gt $scrW) { $l = $x - [int]($BOXW / 2); $t = $y - $GAP - $CARDH }
    $l = [Math]::Max(0, [Math]::Min($l, $scrW - $BOXW))
    $t = [Math]::Max(0, [Math]::Min($t, $scrH - $CARDH))
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
# is the desktop as it looks one moment before the hotkey. That reference only
# holds while the desktop itself is not moving: on a playing video the still and
# the grab taken seconds earlier differ, so the two checks that read $before
# pixel-for-pixel (the magnified field and the copied colour) go advisory and the
# checks that read pixels we drew stay hard.
MoveTo 3000 1900
Start-Sleep -Milliseconds 400
$g1 = Grab 'D:\Project\winshot\obj\s6_pre1.png'
Start-Sleep -Seconds 1
$g2 = Grab 'D:\Project\winshot\obj\s6_pre2.png'
$changed = 0; $sampled = 0
for ($py = 0; $py -lt $g1.Height; $py += 11) {
    for ($px = 0; $px -lt $g1.Width; $px += 11) {
        $c1 = $g1.GetPixel($px, $py); $c2 = $g2.GetPixel($px, $py)
        $sampled++
        if ([Math]::Abs($c1.R - $c2.R) -gt 3 -or [Math]::Abs($c1.G - $c2.G) -gt 3 -or
            [Math]::Abs($c1.B - $c2.B) -gt 3) { $changed++ }
    }
}
$g1.Dispose(); $g2.Dispose()
$staticDesk = ($changed -eq 0)
"desktop stability: $changed of $sampled sampled pixels changed in 1s -> " +
    $(if ($staticDesk) { 'still matches the pre-summon grab' } else { 'still-based checks are advisory'})
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
if ($mean -ge 20 -and $staticDesk) { $fail += 'field does not show the still under the cursor' }
if ($spread -ge 8) { $fail += 'field block not upscaled uniformly' }

$cross = CrossCount $s1 $fx $fy ($fx + $fw - 1) ($fy + $fh - 1)
"crosshair px in field: $cross (want > 300)"
if ($cross -lt 300) { $fail += 'no crosshair in the field' }
# The crosshair has to sit on the sampled pixel, not on the field's centre by
# coincidence. The card no longer covers the cursor, so the two are different
# points: the crosshair belongs at the centre of the source window, which is
# centred on the cursor, while the cursor itself sits $GAP up and left of the
# card entirely.
# Floor, not [int]: the app divides the field by the scale in integers, and
# [int] rounds a .5 half-source-window up, which lands the crosshair a block off.
$ccx = $fx + [int][Math]::Floor($fw / $SCALE / 2) * $SCALE + [int]($SCALE / 2)
$ccy = $fy + [int][Math]::Floor($fh / $SCALE / 2) * $SCALE + [int]($SCALE / 2)
$bad = 0
for ($yy = $fy + 10; $yy -lt $fy + $fh - 10; $yy += 7) {
    $hit = $false
    for ($xx = $ccx - 3; $xx -le $ccx + 3; $xx++) { if (IsCross ($s1.GetPixel($xx, $yy))) { $hit = $true; break } }
    if (-not $hit) { $bad++ }
}
for ($xx = $fx + 10; $xx -lt $fx + $fw - 10; $xx += 7) {
    $hit = $false
    for ($yy = $ccy - 3; $yy -le $ccy + 3; $yy++) { if (IsCross ($s1.GetPixel($xx, $yy))) { $hit = $true; break } }
    if (-not $hit) { $bad++ }
}
"crosshair off-centre rows/cols: $bad (want 0), at $ccx,$ccy"
if ($bad -gt 0) { $fail += "crosshair not on the sampled pixel ($bad)" }

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

# --- the card stays clear of the cursor ------------------------------------
# The whole point of the offset: the card reads the pixel under the pointer, so
# it may not sit on top of it.
if ($L -le $X -or $T -le $Y) {
    $fail += "card at $L,$T does not sit below-right of the cursor at $X,$Y"
}
if ($L - $X -lt $GAP - 2 -or $T - $Y -lt $GAP - 2) {
    $fail += "card at $L,$T is not $GAP px clear of the cursor at $X,$Y"
}

# --- and nothing has to get out of the way ---------------------------------
# This script never picks a region, and the bar only exists once one is picked, so
# there is no bar for the magnifier to yield to. It has to keep drawing at the
# bottom centre of the screen -- exactly where the toolbar used to sit, and where
# the card used to be retired because a bar was under the cursor there.
$bars = @(VisibleBars $ov[0])
"visible bars while the region is unpicked: $($bars.Count) (want 0)"
foreach ($b in $bars) { "  child $($b.left),$($b.top) .. $($b.right),$($b.bottom)" }
if ($bars.Count -ne 0) { $fail += "$($bars.Count) child bars were on screen before any region was picked" }
$bx2 = [int](($scrW - $BOXW) / 2); $by2 = ($scrH - 24)
$cd2 = Card $bx2 $by2
MoveTo $bx2 $by2
Start-Sleep -Milliseconds 400
$s2 = Grab 'D:\Project\winshot\obj\s6_full2.png'
$shown = CrossCount $s2 ($cd2[0] - 4) ($cd2[1] - 4) ($cd2[0] + $BOXW + 3) ($cd2[1] + $CARDH + 3)
"crosshair px at the bottom centre: $shown (want > 300)"
if ($shown -lt 300) { $fail += "the magnifier drew only $shown crosshair px at the bottom centre: something there is still hiding the card" }

MoveTo $X $Y
Start-Sleep -Milliseconds 400
$s3 = Grab 'D:\Project\winshot\obj\s6_full3.png'
$back = CrossCount $s3 $fx $fy ($fx + $fw - 1) ($fy + $fh - 1)
"crosshair px after moving back: $back (want > 300)"
if ($back -lt 300) { $fail += 'magnifier did not come back' }

# Arming a tool used to be a second way to hide the magnifier, and that state is
# gone rather than changed: the only way to arm one is to click a slot in the bar,
# and the bar is only on screen once a region is picked, at which point the card is
# already gone. stage5_test and anno_style still cover arming and disarming.

# --- 按c复制色号, and that is the whole capture ----------------------------
# Last, because copying the colour is the whole request: the capture ends there
# rather than waiting for a region that was never going to be picked. The key
# only reaches the overlay while it is the foreground window, and the sentinel
# rules out a leftover clipboard from whichever test ran last.
$want = '{0},{1},{2}' -f $src.R, $src.G, $src.B
# Back over the sampled point: the last section left the cursor at the bottom of
# the screen, and the key copies whatever the card is reading there, not $src.
MoveTo $X $Y
Start-Sleep -Milliseconds 400
[System.Windows.Forms.Clipboard]::SetText('sentinel')
Force-Foreground $ov[0]
Start-Sleep -Milliseconds 300
"foreground is overlay: $([W6L]::GetForegroundWindow() -eq $ov[0])"
$got = ''
for ($try = 0; $try -lt 3; $try++) {
    [void][System.Windows.Forms.SendKeys]::SendWait('c')
    Start-Sleep -Milliseconds 400
    try { $got = [System.Windows.Forms.Clipboard]::GetText() } catch { $got = '' }
    if ($got -eq $want) { break }
}
"clipboard: '$got' (want '$want')"
if ($got -notmatch '^\d{1,3},\d{1,3},\d{1,3}$') {
    $fail += "c did not copy a bare rgb triple (got '$got')"
} elseif ($got -ne $want -and $staticDesk) {
    $fail += "c copied the wrong colour (got '$got', want '$want')"
}

Start-Sleep -Milliseconds 600
$stillUp = New-Object System.Collections.ArrayList
$cb3 = [W6L+EnumProc] {
    param($h, $l)
    $t = New-Object System.Text.StringBuilder 256
    [void][W6L]::GetWindowText($h, $t, 256)
    if ($t.ToString() -eq 'WinShotOverlay') { [void]$stillUp.Add($h) }
    return $true
}
[void][W6L]::EnumWindows($cb3, [IntPtr]::Zero)
"overlay windows after c: $($stillUp.Count) (want 0)"
if ($stillUp.Count -gt 0) { $fail += 'c left the capture up' }

if ($fail.Count) { "FAIL: " + ($fail -join '; '); exit 1 }
"PASS"
if (-not $proc.HasExited) { $proc.Kill() }
