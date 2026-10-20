# Summoning the capture left two blue frames on the screen at once: the region was
# still the whole screen, so its frame ran round the edge of the display, and the
# hover added a second one around the window under the cursor. The request is one
# frame at a time -- the desktop-wide frame only while the cursor is on the
# desktop itself, and only the hovered window's frame while it is on a window.
#
#   cursor on the desktop -> the frame is the edge of the screen
#   cursor on a window    -> the edge of the screen is bare again, and the frame
#                            sits on that window
#   back to the desktop   -> the edge of the screen picks the frame back up
#
# The third step is the one that costs something to get wrong: the frame is drawn
# into a band the overlay only repaints when it is told the band changed, and the
# hover code invalidates the ring around the window it moved to and from, which
# never reaches the edge of the screen.
#
# Which pixels count as the frame is calibrated rather than assumed. The wallpaper
# under the overlay is dimmed toward black but a blue wallpaper still reads as
# bluish, so the positions used for the assertions are the ones that were not
# frame-blue before the capture was summoned; on a desktop whose edge is blue
# everywhere there is nothing to assert and the script says so.
Add-Type -AssemblyName System.Drawing, System.Windows.Forms
Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class HD {
    public delegate bool EnumProc(IntPtr h, IntPtr l);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
    [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr p, EnumProc cb, IntPtr l);
    [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr h, int idx);
    [DllImport("user32.dll")] public static extern bool MoveWindow(IntPtr h, int x, int y, int w, int ht, bool repaint);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint msg, IntPtr w, IntPtr l);
    [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint dx, uint dy, uint d, UIntPtr e);
    [DllImport("dwmapi.dll")] public static extern int DwmGetWindowAttribute(IntPtr h, int attr, out RECT val, int size);
    [DllImport("dwmapi.dll", EntryPoint="DwmGetWindowAttribute")] public static extern int DwmGetInt(IntPtr h, int attr, out int val, int size);
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int left, top, right, bottom; }
}
"@

$LEFTDOWN = 0x0002; $LEFTUP = 0x0004
# annot::kFrame = 0xFF1E9FD4.
$FR = 30; $FG = 159; $FB = 212

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
    [void][HD]::mouse_event(0x8001, [uint32][int][Math]::Round(65535 * $x / 3839),
                            [uint32][int][Math]::Round(65535 * $y / 2159), 0,
                            [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 90
}
function Down { [void][HD]::mouse_event($LEFTDOWN, 0, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 150 }
function Up { [void][HD]::mouse_event($LEFTUP, 0, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 350 }
function Click([int]$x, [int]$y) { MoveTo $x $y; Down; Up }
function Find-Wins([string]$title) {
    $found = New-Object System.Collections.ArrayList
    $cb = [HD+EnumProc] {
        param($h, $l)
        $t = New-Object System.Text.StringBuilder 256
        [void][HD]::GetWindowText($h, $t, 256)
        if ($t.ToString() -eq $title) { [void]$found.Add($h) }
        return $true
    }
    [void][HD]::EnumWindows($cb, [IntPtr]::Zero)
    return $found.ToArray()
}
function Find-PidWindow([int]$pid_, [string]$cls) {
    $found = New-Object System.Collections.ArrayList
    $cb = [HD+EnumProc] {
        param($h, $l)
        $p = [uint32]0
        [void][HD]::GetWindowThreadProcessId($h, [ref]$p)
        if ($p -eq $pid_ -and [HD]::IsWindowVisible($h)) {
            $c = New-Object System.Text.StringBuilder 64
            [void][HD]::GetClassName($h, $c, 64)
            if ($c.ToString() -eq $cls) { [void]$found.Add($h) }
        }
        return $true
    }
    [void][HD]::EnumWindows($cb, [IntPtr]::Zero)
    $a = $found.ToArray()
    if ($a.Count -eq 0) { return $null }
    return $a[0]
}
function Dwm-Bounds([IntPtr]$h) {
    $r = New-Object HD+RECT
    # DWMWA_EXTENDED_FRAME_BOUNDS is 9: the rectangle the user sees, which is what
    # the frame lands on. GetWindowRect carries the invisible resize border.
    $hr = [HD]::DwmGetWindowAttribute($h, 9, [ref]$r,
                                      [Runtime.InteropServices.Marshal]::SizeOf($r))
    if ($hr -ne 0 -or $r.right -le $r.left -or $r.bottom -le $r.top) { return $null }
    return $r
}
function IsFrame($c) {
    return ([Math]::Abs($c.R - $FR) -le 24 -and [Math]::Abs($c.G - $FG) -le 24 -and
            [Math]::Abs($c.B - $FB) -le 24)
}
# The pixels the whole-screen frame can only ever ink: the one column or row just
# inside each edge, because the 2px pen is centred on the edge and its other half
# falls off the screen. 60px in from the corners keeps the run clear of the size
# card, which hangs off the top-left corner of the region.
function Border-Positions([int]$w, [int]$h) {
    $pts = New-Object System.Collections.ArrayList
    for ($x = 60; $x -le $w - 61; $x += 3) {
        [void]$pts.Add(@($x, 0)); [void]$pts.Add(@($x, ($h - 1)))
    }
    for ($y = 60; $y -le $h - 61; $y += 3) {
        [void]$pts.Add(@(0, $y)); [void]$pts.Add(@(($w - 1), $y))
    }
    return ,$pts
}
# The two columns on their own. Once a region is picked the toolbar is placed from
# its bottom edge, and for a region that is the whole screen that lands on the
# bottom border row, so only the sides are left to read.
function Side-Positions([int]$w, [int]$h) {
    $pts = New-Object System.Collections.ArrayList
    for ($y = 60; $y -le $h - 61; $y += 3) {
        [void]$pts.Add(@(0, $y)); [void]$pts.Add(@(($w - 1), $y))
    }
    return ,$pts
}
function Border-Frac($bmp, $pts) {
    if ($pts.Count -eq 0) { return -1 }
    $hit = 0
    foreach ($p in $pts) { if (IsFrame ($bmp.GetPixel($p[0], $p[1]))) { $hit++ } }
    return ($hit / $pts.Count)
}
# Fraction of the positions along the four edges of $b that carry the frame within
# one pixel of the window's own edge.
function Edge-Frac($bmp, $b) {
    $hit = 0; $tot = 0
    for ($x = $b.left + 12; $x -le $b.right - 12; $x += 3) {
        $tot += 2
        if (IsFrame ($bmp.GetPixel($x, ($b.top - 1)))) { $hit++ }
        elseif (IsFrame ($bmp.GetPixel($x, $b.top))) { $hit++ }
        if (IsFrame ($bmp.GetPixel($x, ($b.bottom - 1)))) { $hit++ }
        elseif (IsFrame ($bmp.GetPixel($x, $b.bottom))) { $hit++ }
    }
    for ($y = $b.top + 12; $y -le $b.bottom - 12; $y += 3) {
        $tot += 2
        if (IsFrame ($bmp.GetPixel(($b.left - 1), $y))) { $hit++ }
        elseif (IsFrame ($bmp.GetPixel($b.left, $y))) { $hit++ }
        if (IsFrame ($bmp.GetPixel(($b.right - 1), $y))) { $hit++ }
        elseif (IsFrame ($bmp.GetPixel($b.right, $y))) { $hit++ }
    }
    if ($tot -eq 0) { return 0 }
    return ($hit / $tot)
}
# The windows covering a point, on the product's own terms: the filter set mirrors
# winpick::IsDesktopLayer, and a cloaked window is "visible" to IsWindowVisible yet
# never wins a hover, so minimizing one would disturb the user for nothing.
function Get-Covering([int]$x, [int]$y) {
    $own = [System.Diagnostics.Process]::GetCurrentProcess().Id
    $found = New-Object System.Collections.ArrayList
    $cb = [HD+EnumProc] {
        param($h, $l)
        $p = [uint32]0
        [void][HD]::GetWindowThreadProcessId($h, [ref]$p)
        if ([int]$p -ne $own -and [HD]::IsWindowVisible($h) -and
            (([HD]::GetWindowLong($h, -20) -band 0x80) -eq 0)) {
            $c = New-Object System.Text.StringBuilder 64
            [void][HD]::GetClassName($h, $c, 64)
            $cl = $c.ToString()
            if ($cl -ne 'Progman' -and $cl -ne 'WorkerW' -and $cl -ne 'Shell_TrayWnd' -and
                $cl -ne 'Shell_SecondaryTrayWnd' -and
                $cl -ne 'ApplicationWindowLightDismiss') {
                $ck = [int]0
                # DWMWA_CLOAKED is 14.
                if ([HD]::DwmGetInt($h, 14, [ref]$ck, 4) -eq 0 -and $ck -eq 0) {
                    $r = New-Object HD+RECT
                    if ([HD]::DwmGetWindowAttribute($h, 9, [ref]$r,
                            [Runtime.InteropServices.Marshal]::SizeOf($r)) -ne 0) {
                        [void][HD]::GetWindowRect($h, [ref]$r)
                    }
                    if ($x -ge $r.left -and $x -lt $r.right -and
                        $y -ge $r.top -and $y -lt $r.bottom) {
                        [void]$found.Add($h)
                    }
                }
            }
        }
        return $true
    }
    [void][HD]::EnumWindows($cb, [IntPtr]::Zero)
    return $found.ToArray()
}
$script:restored = $false
function Restore-Windows {
    if ($script:restored) { return }
    $script:restored = $true
    foreach ($h in @($minimized)) { [void][HD]::ShowWindow($h, 9) }   # SW_RESTORE
}

# Mid-screen, clear of the toolbar the picked region earns, and clear of the
# notepad below: the point has to end up showing wallpaper.
$at = @(1900, 1000)
# The last hover step has to land somewhere new for the frame to change hands
# again, so it uses a point 40px away -- and that point needs the same clearance.
# It does not follow from the first point being clear: measured on 2026-10-21 a
# window at 1913,0..3847,2127 covered 1940,1040 and not 1900,1000, so the hover
# went to it and the screen edge read 33.9% -- the top row from x=1920 and the
# whole right column, which is where that window's own edge crosses the border.
$at2 = @(($at[0] + 40), ($at[1] + 40))
$fail = @()
$minimized = @()
$proc = $null
$np = $null
function Bail([string]$msg) {
    # The windows this script minimized have to come back whether the test passes
    # or not, which is why every exit goes through here.
    Restore-Windows
    if ($np -and -not $np.HasExited) { Stop-Process -Id $np.Id -Force -ErrorAction SilentlyContinue }
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

# A full path, not `notepad`: Start-Process resolves a bare name off PATH and then
# refuses to run it here, because there is no zone for it to read.
$NOTEPAD = "$env:SystemRoot\System32\notepad.exe"
$np = Start-Process -FilePath $NOTEPAD -PassThru
Start-Sleep -Seconds 2
$nh = Find-PidWindow $np.Id 'Notepad'
if (-not $nh) { Bail 'could not find the notepad window' }
[void][HD]::MoveWindow($nh, 400, 300, 900, 500, $true)
[void][HD]::SetForegroundWindow($nh)
Start-Sleep -Milliseconds 900
$nb = Dwm-Bounds $nh
if (-not $nb) { Bail 'DWM gave no visible bounds for the notepad' }
"notepad $($nb.left),$($nb.top) .. $($nb.right),$($nb.bottom)"
$nc = @([int](($nb.left + $nb.right) / 2), [int](($nb.top + $nb.bottom) / 2))
foreach ($p in @($at, $at2)) {
    if ($p[0] -ge $nb.left -and $p[0] -lt $nb.right -and
        $p[1] -ge $nb.top -and $p[1] -lt $nb.bottom) {
        Bail "the desktop point $($p[0]),$($p[1]) fell inside the notepad"
    }
}

# Clear both desktop points down to the wallpaper before the still is taken, so the
# frozen desktop and the live one underneath agree about what is there.
$minimized = @((Get-Covering $at[0] $at[1]) + (Get-Covering $at2[0] $at2[1]) |
               Select-Object -Unique)
foreach ($h in $minimized) { [void][HD]::ShowWindow($h, 6) }   # SW_MINIMIZE
Start-Sleep -Milliseconds 900
$still = @(Get-Covering $at[0] $at[1])
if ($still.Count) { Bail "the $($still.Count) windows covering $($at[0]),$($at[1]) did not minimize; there is no desktop to hover here" }
$still2 = @(Get-Covering $at2[0] $at2[1])
if ($still2.Count) { Bail "the $($still2.Count) windows covering $($at2[0]),$($at2[1]) did not minimize; there is no desktop to hover here" }
"minimized $($minimized.Count) windows to clear $($at[0]),$($at[1]) and $($at2[0]),$($at2[1])"

$bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
$all = Border-Positions $bounds.Width $bounds.Height
$sides = Side-Positions $bounds.Width $bounds.Height
$g0 = Grab 'D:\Project\winshot\obj\hd_before.png'
$pts = New-Object System.Collections.ArrayList
$sidePts = New-Object System.Collections.ArrayList
foreach ($p in $all) {
    if (-not (IsFrame ($g0.GetPixel($p[0], $p[1])))) { [void]$pts.Add($p) }
}
foreach ($p in $sides) {
    if (-not (IsFrame ($g0.GetPixel($p[0], $p[1])))) { [void]$sidePts.Add($p) }
}
$g0.Dispose()
"edge positions usable for the frame test: $($pts.Count) of $($all.Count)"
if ($pts.Count -lt 200) { Bail 'the wallpaper is frame-blue along nearly the whole edge; this desktop cannot tell a frame from itself' }
if ($sidePts.Count -lt 100) { Bail 'the wallpaper is frame-blue along both sides; the click cannot be checked here' }

$proc = Start-Process -FilePath 'D:\Project\winshot\x64\Debug\winshot.exe' -PassThru
Start-Sleep -Seconds 2
$sink = @(Find-Wins 'WinShotSink')
if ($sink.Count -eq 0) { Bail 'no sink window' }
[void][HD]::PostMessage($sink[0], 0x8002, [IntPtr]::Zero, [IntPtr]::Zero)
Start-Sleep -Seconds 2
$ov = @(Find-Wins 'WinShotOverlay')
if ($ov.Count -eq 0) { Bail 'no overlay window' }

# --- the cursor on the wallpaper: the screen itself is the pre-selection -------
MoveTo $at[0] $at[1]
Start-Sleep -Milliseconds 700
$g = Grab 'D:\Project\winshot\obj\hd_desktop.png'
$onDesk = Border-Frac $g $pts
$onWin = Edge-Frac $g $nb
$g.Dispose()
"cursor on the desktop: edge frame $([Math]::Round($onDesk * 100, 1))%  notepad edge $([Math]::Round($onWin * 100, 1))%"
if ($onDesk -lt 0.9) {
    $fail += "with the cursor on the desktop only $([Math]::Round($onDesk * 100, 1))% of the screen edge carries the frame: the whole-desktop pre-selection is missing"
}
if ($onWin -gt 0.1) {
    $fail += "with the cursor on the desktop the notepad's own edge also carries the frame at $([Math]::Round($onWin * 100, 1))%: two frames at once"
}

# --- and on a window: that window alone ----------------------------------------
MoveTo $nc[0] $nc[1]
Start-Sleep -Milliseconds 700
$g = Grab 'D:\Project\winshot\obj\hd_window.png'
$onWin2 = Edge-Frac $g $nb
$onDesk2 = Border-Frac $g $pts
$g.Dispose()
"cursor on the notepad: notepad edge $([Math]::Round($onWin2 * 100, 1))%  screen edge $([Math]::Round($onDesk2 * 100, 1))%"
if ($onWin2 -lt 0.9) {
    $fail += "with the cursor on the notepad its own edge carries the frame at only $([Math]::Round($onWin2 * 100, 1))%"
}
if ($onDesk2 -gt 0.1) {
    $fail += "with the cursor on the notepad $([Math]::Round($onDesk2 * 100, 1))% of the screen edge still carries the whole-desktop frame: the two frames are drawn together"
}

# --- back to the wallpaper: the screen edge takes it back ----------------------
# The hover code damages the ring around the window it came from and the one it
# went to, neither of which reaches the edge of the display, so this is the step
# that fails if the edge is not invalidated when the frame changes hands. $at2 is
# a different point so the hover really changes, and it is cleared to wallpaper
# with $at above -- hovering a window here would hide the edge frame correctly and
# read as this failure.
MoveTo $at2[0] $at2[1]
Start-Sleep -Milliseconds 700
$g = Grab 'D:\Project\winshot\obj\hd_back.png'
$onDesk3 = Border-Frac $g $pts
$onWin3 = Edge-Frac $g $nb
$g.Dispose()
"cursor back on the desktop: edge frame $([Math]::Round($onDesk3 * 100, 1))%  notepad edge $([Math]::Round($onWin3 * 100, 1))%"
if ($onDesk3 -lt 0.9) {
    $fail += "after leaving the window only $([Math]::Round($onDesk3 * 100, 1))% of the screen edge carries the frame again: the edge was left as the window had it"
}
if ($onWin3 -gt 0.1) {
    $fail += "after leaving the window its edge still carries the frame at $([Math]::Round($onWin3 * 100, 1))%: the frame was left behind"
}

# A click on the wallpaper still takes the whole screen, which is what the frame
# there promised; the frame around a window was never a region of its own. The
# sides only: the bar the picked region earns lands on the bottom border row.
Click $at[0] $at[1]
Start-Sleep -Milliseconds 700
$g = Grab 'D:\Project\winshot\obj\hd_clicked.png'
$onDesk4 = Border-Frac $g $sidePts
$g.Dispose()
"after clicking the desktop: side frame $([Math]::Round($onDesk4 * 100, 1))%"
if ($onDesk4 -lt 0.9) {
    $fail += "after clicking the desktop only $([Math]::Round($onDesk4 * 100, 1))% of the screen sides carry the frame: the whole-screen region the click promised is not there"
}

Restore-Windows
if ($np -and -not $np.HasExited) { Stop-Process -Id $np.Id -Force -ErrorAction SilentlyContinue }
if ($proc -and -not $proc.HasExited) { $proc.Kill() }
if ($fail.Count) { "FAILURES: $($fail.Count)"; $fail | ForEach-Object { "  $_" }; exit 1 }
'PASS'
