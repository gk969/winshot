# Summoning the capture used to leave the whole screen picked and nothing to go
# by but the magnifier. The requirement is that hovering the live desktop under
# the overlay draws the 选区's blue frame around the window underneath, follows
# the cursor between windows, respects z-order where they overlap, and turns into
# the real region on a click.
#
#   hover one window  -> the frame sits on that window's own edges, no markers
#   hover the overlap -> the frame moves to the topmost of the two
#   interior          -> still dimmed: the frame is a promise, not a hole
#   click             -> markers appear and the toolbar moves under the new region
#
# Two notepads are started by the script and moved to known rects, so the window
# geometry is known rather than guessed at. The expected frame rect is read back
# with DWMWA_EXTENDED_FRAME_BOUNDS - the same attribute the product uses - because
# GetWindowRect includes the invisible resize border and would put the assertion
# several pixels outside the edge the user can actually see.
Add-Type -AssemblyName System.Drawing, System.Windows.Forms
Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class HP {
    public delegate bool EnumProc(IntPtr h, IntPtr l);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
    [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr p, EnumProc cb, IntPtr l);
    [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("user32.dll")] public static extern bool MoveWindow(IntPtr h, int x, int y, int w, int ht, bool repaint);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint msg, IntPtr w, IntPtr l);
    [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint dx, uint dy, uint d, UIntPtr e);
    [DllImport("user32.dll")] public static extern int GetSystemMetrics(int idx);
    [DllImport("dwmapi.dll")] public static extern int DwmGetWindowAttribute(IntPtr h, int attr, out RECT val, int size);
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int left, top, right, bottom; }
}
"@

$LEFTDOWN = 0x0002; $LEFTUP = 0x0004
$DWMWA_EXTENDED_FRAME_BOUNDS = 9
# annot::kFrame = 0xFF1E9FD4.
$FR = 30; $FG = 159; $FB = 212
# Corner-Blue above this means a drag marker sits on the corner. See Corner-Blue.
$MARK = 30

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
    [void][HP]::mouse_event(0x8001, [uint32][int][Math]::Round(65535 * $x / 3839),
                            [uint32][int][Math]::Round(65535 * $y / 2159), 0,
                            [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 90
}
function Down { [void][HP]::mouse_event($LEFTDOWN, 0, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 150 }
function Up { [void][HP]::mouse_event($LEFTUP, 0, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 350 }
function Click([int]$x, [int]$y) { MoveTo $x $y; Down; Up }
function Find-Wins([string]$title) {
    $found = New-Object System.Collections.ArrayList
    $cb = [HP+EnumProc] {
        param($h, $l)
        $t = New-Object System.Text.StringBuilder 256
        [void][HP]::GetWindowText($h, $t, 256)
        if ($t.ToString() -eq $title) { [void]$found.Add($h) }
        return $true
    }
    [void][HP]::EnumWindows($cb, [IntPtr]::Zero)
    return $found.ToArray()
}
function Find-Kids([IntPtr]$parent, [string]$title) {
    $found = New-Object System.Collections.ArrayList
    $cb = [HP+EnumProc] {
        param($h, $l)
        $t = New-Object System.Text.StringBuilder 256
        [void][HP]::GetWindowText($h, $t, 256)
        if ($t.ToString() -eq $title -and [HP]::IsWindowVisible($h)) { [void]$found.Add($h) }
        return $true
    }
    [void][HP]::EnumChildWindows($parent, $cb, [IntPtr]::Zero)
    return $found.ToArray()
}
# The notepad's own top-level window: by pid, and by class rather than by title,
# because the title is the document name and changes under typing and untitled
# state.
function Find-PidWindow([int]$pid_, [string]$cls) {
    $found = New-Object System.Collections.ArrayList
    $cb = [HP+EnumProc] {
        param($h, $l)
        $p = [uint32]0
        [void][HP]::GetWindowThreadProcessId($h, [ref]$p)
        if ($p -eq $pid_ -and [HP]::IsWindowVisible($h)) {
            $c = New-Object System.Text.StringBuilder 64
            [void][HP]::GetClassName($h, $c, 64)
            if ($c.ToString() -eq $cls) { [void]$found.Add($h) }
        }
        return $true
    }
    [void][HP]::EnumWindows($cb, [IntPtr]::Zero)
    $a = $found.ToArray()
    if ($a.Count -eq 0) { return $null }
    return $a[0]
}
# The visible bounds, which is what the frame has to land on. E_FAIL for a window
# DWM holds no record of; the caller treats that as "no window to test against".
function Dwm-Bounds([IntPtr]$h) {
    $r = New-Object HP+RECT
    $hr = [HP]::DwmGetWindowAttribute($h, $DWMWA_EXTENDED_FRAME_BOUNDS, [ref]$r,
                                      [Runtime.InteropServices.Marshal]::SizeOf($r))
    if ($hr -ne 0 -or $r.right -le $r.left -or $r.bottom -le $r.top) { return $null }
    return $r
}
function Toolbar-Rect() {
    $t = @(Find-Kids $ov[0] 'WinShotToolbar')
    if ($t.Count -eq 0) { return $null }
    $r = New-Object HP+RECT
    [void][HP]::GetWindowRect($t[0], [ref]$r)
    return $r
}
function IsFrame($c) {
    return ([Math]::Abs($c.R - $FR) -le 24 -and [Math]::Abs($c.G - $FG) -le 24 -and
            [Math]::Abs($c.B - $FB) -le 24)
}
# Fraction of the positions along the four edges of $b that carry the frame within
# one pixel of the window's own edge. The 2px pen straddles that edge, so the two
# rows/columns either side of it are the whole answer; anything much below 1.0
# means the frame is somewhere else - the inflated GetWindowRect rect, most
# likely, which is the mistake this attribute was chosen to avoid.
function Edge-Frac($bmp, $b) {
    $hit = 0; $tot = 0
    for ($x = $b.left + 12; $x -le $b.right - 12; $x++) {
        $tot += 2
        if (IsFrame ($bmp.GetPixel($x, ($b.top - 1)))) { $hit++ }
        elseif (IsFrame ($bmp.GetPixel($x, $b.top))) { $hit++ }
        if (IsFrame ($bmp.GetPixel($x, ($b.bottom - 1)))) { $hit++ }
        elseif (IsFrame ($bmp.GetPixel($x, $b.bottom))) { $hit++ }
    }
    for ($y = $b.top + 12; $y -le $b.bottom - 12; $y++) {
        $tot += 2
        if (IsFrame ($bmp.GetPixel(($b.left - 1), $y))) { $hit++ }
        elseif (IsFrame ($bmp.GetPixel($b.left, $y))) { $hit++ }
        if (IsFrame ($bmp.GetPixel(($b.right - 1), $y))) { $hit++ }
        elseif (IsFrame ($bmp.GetPixel($b.right, $y))) { $hit++ }
    }
    if ($tot -eq 0) { return 0 }
    return ($hit / $tot)
}
# Blue pixels in the 9x9 box centred on a corner. Measured, not derived: the bare
# pre-selection frame gives 16..20 here (the clip band that keeps the frame's
# repaint cheap cuts the corner's inner arm), and a 7x7 drag marker on top of the
# frame gives 45..53. The split at 30 has ten pixels of margin either side.
function Corner-Blue($bmp, [int]$x, [int]$y) {
    $n = 0
    for ($yy = $y - 4; $yy -le $y + 4; $yy++) {
        for ($xx = $x - 4; $xx -le $x + 4; $xx++) {
            if (IsFrame ($bmp.GetPixel($xx, $yy))) { $n++ }
        }
    }
    return $n
}
function Corner-Blues($bmp, $b) {
    return @(
        (Corner-Blue $bmp $b.left $b.top), (Corner-Blue $bmp $b.right $b.top),
        (Corner-Blue $bmp $b.left $b.bottom), (Corner-Blue $bmp $b.right $b.bottom))
}
# Mean brightness over a grid inside the window. Notepad's page is white, so this
# is a direct read of the dim: 0.4 of the pre-summon value is kDim's 0x99 alpha.
function Interior-Mean($bmp, $b, [int]$inset) {
    $sum = 0; $n = 0
    for ($y = $b.top + $inset; $y -le $b.bottom - $inset; $y += 7) {
        for ($x = $b.left + $inset; $x -le $b.right - $inset; $x += 7) {
            $c = $bmp.GetPixel($x, $y)
            $sum += ([int]$c.R + [int]$c.G + [int]$c.B) / 3; $n++
        }
    }
    if ($n -eq 0) { return -1 }
    return ($sum / $n)
}
$fail = @()
function Bail([string]$msg) {
    foreach ($q in @($np1, $np2)) {
        if ($q -and -not $q.HasExited) { Stop-Process -Id $q.Id -Force -ErrorAction SilentlyContinue }
    }
    if ($proc -and -not $proc.HasExited) { $proc.Kill() }
    $all = @($msg) + $fail
    "FAILURES: $($all.Count)"
    $all | ForEach-Object { "  $_" }
    exit 1
}

MoveTo 3000 1900
Start-Sleep -Milliseconds 400
Get-Process winshot -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 600

# A full path, not `notepad`: Start-Process resolves a bare name off PATH and
# then refuses to run it here ("the system cannot find the security information"),
# because there is no zone for it to read.
$NOTEPAD = "$env:SystemRoot\System32\notepad.exe"
$np1 = Start-Process -FilePath $NOTEPAD -PassThru
Start-Sleep -Seconds 2
$np2 = Start-Process -FilePath $NOTEPAD -PassThru
Start-Sleep -Seconds 2
$h1 = Find-PidWindow $np1.Id 'Notepad'
$h2 = Find-PidWindow $np2.Id 'Notepad'
if (-not $h1 -or -not $h2) { Bail 'could not find the two notepad windows' }
# Overlapping on purpose: the point inside both is the z-order test.
[void][HP]::MoveWindow($h1, 600, 400, 1000, 600, $true)
[void][HP]::MoveWindow($h2, 900, 600, 1000, 600, $true)
[void][HP]::SetForegroundWindow($h2)
Start-Sleep -Milliseconds 900
$b1 = Dwm-Bounds $h1
$b2 = Dwm-Bounds $h2
if (-not $b1 -or -not $b2) { Bail 'DWM gave no visible bounds for the notepads' }
"window 1 $($b1.left),$($b1.top) .. $($b1.right),$($b1.bottom)"
"window 2 $($b2.left),$($b2.top) .. $($b2.right),$($b2.bottom)"
# A point inside window 1 alone, and one inside both.
$p1 = @(($b1.left + 60), ($b1.top + 60))
$ov2 = @(([Math]::Max($b1.left, $b2.left) + 60), ([Math]::Max($b1.top, $b2.top) + 60))
if ($ov2[0] -ge $b1.right -or $ov2[0] -ge $b2.right) { Bail 'the two windows do not overlap' }

$g0 = Grab 'D:\Project\winshot\obj\hp_before.png'
$lit0 = Interior-Mean $g0 $b1 40
$g0.Dispose()
"window 1 interior before the capture: $([Math]::Round($lit0, 1))"
if ($lit0 -lt 60) { Bail 'window 1 is not bright enough to measure a dim against' }

$proc = Start-Process -FilePath 'D:\Project\winshot\x64\Debug\winshot.exe' -PassThru
Start-Sleep -Seconds 2
$sink = @(Find-Wins 'WinShotSink')
if ($sink.Count -eq 0) { Bail 'no sink window' }
[void][HP]::PostMessage($sink[0], 0x8002, [IntPtr]::Zero, [IntPtr]::Zero)
Start-Sleep -Seconds 2
$ov = @(Find-Wins 'WinShotOverlay')
if ($ov.Count -eq 0) { Bail 'no overlay window' }

# --- hovering one window -------------------------------------------------------
MoveTo $p1[0] $p1[1]
Start-Sleep -Milliseconds 600
$g = Grab 'D:\Project\winshot\obj\hp_hover1.png'
$f1 = Edge-Frac $g $b1
$c1 = Corner-Blues $g $b1
$lit1 = Interior-Mean $g $b1 40
$g.Dispose()
"hover window 1: edge coverage $([Math]::Round($f1, 3))  corners $($c1 -join ',')  interior $([Math]::Round($lit1, 1))"
if ($f1 -lt 0.9) {
    $fail += "hovering window 1 put the frame on only $([Math]::Round($f1 * 100, 1))% of its edges; it is not on the window the cursor is over"
}
foreach ($v in $c1) {
    if ($v -gt $MARK) { $fail += "a hover pre-selection corner carries $v blue pixels where the bare frame gives at most 20: it has a drag marker before one was earned" }
}
$ratio = $lit1 / $lit0
"interior dim ratio $([Math]::Round($ratio, 3))"
if ($ratio -lt 0.3 -or $ratio -gt 0.52) {
    $fail += "the hovered window reads $([Math]::Round($ratio, 2)) of its pre-capture brightness; the frame has to stay a frame and leave the window dimmed"
}

# --- and the topmost one wins where they overlap --------------------------------
MoveTo $ov2[0] $ov2[1]
Start-Sleep -Milliseconds 600
$g = Grab 'D:\Project\winshot\obj\hp_hover2.png'
$f2 = Edge-Frac $g $b2
$stillOn1 = Edge-Frac $g $b1
$g.Dispose()
"hover the overlap: window 2 coverage $([Math]::Round($f2, 3))  window 1 coverage $([Math]::Round($stillOn1, 3))"
if ($f2 -lt 0.9) {
    $fail += "over the overlap the frame stayed off window 2 ($([Math]::Round($f2 * 100, 1))% of its edges): z-order did not decide the pre-selection"
}

# --- a click adopts it ----------------------------------------------------------
$tr0 = Toolbar-Rect
$cx = [int](($b2.left + $b2.right) / 2); $cy = [int](($b2.top + $b2.bottom) / 2)
Click $cx $cy
Start-Sleep -Milliseconds 700
$g = Grab 'D:\Project\winshot\obj\hp_clicked.png'
$c2 = Corner-Blues $g $b2
$g.Dispose()
$tr1 = Toolbar-Rect
"after the click: corners $($c2 -join ',')  toolbar $($(if ($tr1) { "$($tr1.left),$($tr1.top) .. $($tr1.right),$($tr1.bottom)" } else { 'gone' }))"
$with = 0
foreach ($v in $c2) { if ($v -gt $MARK) { $with++ } }
if ($with -lt 4) {
    $fail += "after clicking the hovered window only $with of its four corners have a drag marker (counts $($c2 -join ',')); the pre-selection did not become the region"
}
if (-not $tr1) {
    $fail += 'the toolbar disappeared when the pre-selection was adopted'
} elseif ($tr1.top -le $b2.bottom) {
    $fail += "the toolbar stayed at y=$($tr1.top) instead of moving under the adopted region ending at y=$($b2.bottom)"
} elseif ($tr0 -and $tr0.top -eq $tr1.top) {
    $fail += "the toolbar did not move at all: still at y=$($tr1.top) after the region changed"
}

foreach ($q in @($np1, $np2)) {
    if ($q -and -not $q.HasExited) { Stop-Process -Id $q.Id -Force -ErrorAction SilentlyContinue }
}
if (-not $proc.HasExited) { $proc.Kill() }
if ($fail.Count) { "FAILURES: $($fail.Count)"; $fail | ForEach-Object { "  $_" }; exit 1 }
'PASS'
