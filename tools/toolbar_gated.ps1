# Summoning used to put the drawing bar on screen straight away, over a desktop the
# user had not picked yet -- a row of tools with nothing to draw on. The rule now is
# that the bar is the reward for a region: one click on the desktop or on a window,
# or a drag of their own, and it appears under that region; a right-click outside the
# region resets and it goes away again.
#
#   after summon   no bar on screen, and the magnifier IS up
#   mid-drag       still no bar
#   after release  the bar, below the region just dragged
#   right-click    the bar gone again, and the magnifier back
#   a click        the bar back, because that click picked a region
#
# Two witnesses, and they are mutually exclusive states now: the card draws only
# while the region is unpicked (LoupeCursor returns early once it is picked), and the
# bar exists only once it is. The bar's own window is the primary one -- the child is
# created hidden and never destroyed, so its handle is there either way and only
# IsWindowVisible says which. The crosshair count is the secondary one, and it is the
# half that could regress silently: the card used to retire itself over the bar's
# rect, and GetWindowRect answers for a hidden window too, so an unguarded test
# would still hide the card over empty desktop where nothing is drawn at all.
Add-Type -AssemblyName System.Drawing, System.Windows.Forms
Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class TG {
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
$RIGHTDOWN = 0x0008; $RIGHTUP = 0x0010
# The card's crosshair is cyan on every channel pair, so blue and green both high
# with red out of the picture.
function IsCyan($c) { return ($c.R -lt 90 -and $c.G -gt 195 -and $c.B -gt 195) }

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
    [void][TG]::mouse_event(0x8001, [uint32][int][Math]::Round(65535 * $x / 3839),
                            [uint32][int][Math]::Round(65535 * $y / 2159), 0,
                            [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 90
}
function Down { [void][TG]::mouse_event($LEFTDOWN, 0, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 150 }
function Up { [void][TG]::mouse_event($LEFTUP, 0, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 350 }
function Walk([int]$x1, [int]$y1, [int]$x2, [int]$y2, [int]$steps) {
    for ($i = 1; $i -le $steps; $i++) {
        MoveTo ([int]($x1 + ($x2-$x1) * $i / $steps)) ([int]($y1 + ($y2-$y1) * $i / $steps))
    }
}
function Click([int]$x, [int]$y) { MoveTo $x $y; Down; Up }
# A real press and release, not an orphan up: the product's 框外右键 action is on the
# release, and an up with no down leaves the left button logically down behind it
# (0x0012 is RIGHTUP|LEFTDOWN, which is how that was found).
function RClick([int]$x, [int]$y) {
    MoveTo $x $y
    [void][TG]::mouse_event($RIGHTDOWN, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 150
    [void][TG]::mouse_event($RIGHTUP, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 350
}
function Find-Wins([string]$title) {
    $found = New-Object System.Collections.ArrayList
    $cb = [TG+EnumProc] {
        param($h, $l)
        $t = New-Object System.Text.StringBuilder 256
        [void][TG]::GetWindowText($h, $t, 256)
        if ($t.ToString() -eq $title) { [void]$found.Add($h) }
        return $true
    }
    [void][TG]::EnumWindows($cb, [IntPtr]::Zero)
    return $found.ToArray()
}
# The overlay's bars are children, so they cannot be found by EnumWindows, and they
# are named by their window text rather than by their MFC class. $mustSee is the
# whole point of this script: the same handle answers both questions.
function Find-Child([IntPtr]$parent, [string]$name, [bool]$mustSee) {
    $found = New-Object System.Collections.ArrayList
    $cb = [TG+EnumProc] {
        param($h, $l)
        $t = New-Object System.Text.StringBuilder 256
        [void][TG]::GetWindowText($h, $t, 256)
        if ($t.ToString() -eq $name -and (-not $mustSee -or [TG]::IsWindowVisible($h))) {
            [void]$found.Add($h)
        }
        return $true
    }
    [void][TG]::EnumChildWindows($parent, $cb, [IntPtr]::Zero)
    return $found.ToArray()
}
function Rect-Of([IntPtr]$h) {
    $r = New-Object TG+RECT
    [void][TG]::GetWindowRect($h, [ref]$r)
    return $r
}
$ov = $null
# The bar's handle whether or not it is on screen, or "no bar" and "no window" look
# the same to the caller. Place runs while hidden, so the rect is real either way.
function Bar() {
    $t = @(Find-Child $ov[0] 'WinShotToolbar' $false)
    if ($t.Count -eq 0) { return $null }
    return @{ h = $t[0]; vis = [TG]::IsWindowVisible($t[0]); r = (Rect-Of $t[0]) }
}
# Cyan pixels in the card's box, which COverlayWnd::LoupeCursor places at
# cursor + (14,14) and draws 117x146.
function CrossCount($bmp, [int]$cx, [int]$cy) {
    $n = 0
    for ($y = $cy + 14; $y -le $cy + 159; $y++) {
        for ($x = $cx + 14; $x -le $cx + 130; $x++) {
            if (IsCyan ($bmp.GetPixel($x, $y))) { $n++ }
        }
    }
    return $n
}
# The magnifier is up exactly when the card is drawing there. The count travels back
# in a hashtable: a bare string would join the output stream and arrive at the caller
# glued to the number, where it compares greater than any integer as text.
function Loupe([string]$tag, [int]$x, [int]$y, [string]$png) {
    MoveTo $x $y
    Start-Sleep -Milliseconds 400
    $g = Grab "D:\Project\winshot\obj\tg_$png.png"
    $n = CrossCount $g $x $y
    $g.Dispose()
    return @{ n = $n; msg = "${tag}: loupe crosshair $n cyan px at $x,$y" }
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
[void][TG]::PostMessage($sink[0], 0x8002, [IntPtr]::Zero, [IntPtr]::Zero)
Start-Sleep -Seconds 2
$ov = @(Find-Wins 'WinShotOverlay')
if ($ov.Count -eq 0) { 'FAIL: no overlay window'; exit 1 }

# --- summoned, nothing picked --------------------------------------------------
# 1900,1000 is mid-screen, which is where the bar used to sit and where the card
# therefore used to retire itself. It has to draw here now.
$b0 = Bar
if (-not $b0) { 'FAIL: the overlay has no WinShotToolbar child at all'; exit 1 }
$n0 = Loupe 'after summon' 1900 1000 'summon'
"after summon: toolbar window present, visible=$($b0.vis) at $($b0.r.left),$($b0.r.top)"
$n0.msg
if ($b0.vis) {
    $fail += "the toolbar was on screen at y=$($b0.r.top) the moment the capture was summoned, while the whole screen was still unpicked"
}
if ($n0.n -lt 300) {
    $fail += "the magnifier drew only $($n0.n) crosshair px mid-screen right after the summon: the card is still hiding itself for a bar that is not there"
}

# --- mid-drag: the press alone must not bring the bar up ------------------------
# SelectionModel::BeginCreate clears the default flag on the press, so a predicate
# that only asked IsDefault() would show the bar here, under the hand that is still
# dragging out the region.
MoveTo 700 500
Down
Walk 700 500 2200 1500 12
$bm = Bar
Start-Sleep -Milliseconds 300
"mid-drag: toolbar visible=$($bm.vis)"
if ($bm.vis) {
    $fail += "the toolbar came up at y=$($bm.r.top) while the region was still being dragged out"
}
Up
Start-Sleep -Milliseconds 500

# --- released: the bar is earned -------------------------------------------------
$br = Bar
"after the drag: toolbar visible=$($br.vis) at $($br.r.left),$($br.r.top) .. $($br.r.right),$($br.r.bottom), region ends at y=1500"
if (-not $br.vis) {
    $fail += 'the toolbar was still hidden after a region had been dragged out: it never came up'
} elseif ($br.r.top -lt 1500) {
    $fail += "the bar sits at y=$($br.r.top), on top of the region that ends at y=1500: it belongs below it"
}
# The card has to be gone now, or the two would be on screen together.
$n1 = Loupe 'after the drag' 1900 1000 'picked'
$n1.msg
if ($n1.n -gt 60) {
    $fail += "the magnifier still drew $($n1.n) crosshair px with a region picked and the bar on screen"
}

# --- right-click outside: back to nothing ----------------------------------------
# The reset goes through ResetCanvas, which restores the default selection and calls
# LayoutChrome, so the bar has no state of its own to remember.
RClick 300 300
Start-Sleep -Milliseconds 300
$bz = Bar
"after the right-click: toolbar visible=$($bz.vis)"
if ($bz.vis) {
    $fail += "the toolbar stayed on screen at y=$($bz.r.top) after a right-click outside the region reset the canvas"
}
$n2 = Loupe 'after the right-click' 1900 1000 'reset'
$n2.msg
if ($n2.n -lt 300) {
    $fail += "after the reset the magnifier drew only $($n2.n) crosshair px: the canvas reset but the card did not come back"
}

# --- a click picks, and the bar follows ------------------------------------------
# Whether this adopts a window or the whole screen depends on what is under the
# cursor, and either is a picked region; what is being asserted is only that a
# single press and release is now enough to earn the bar.
Click 1900 1000
Start-Sleep -Milliseconds 700
$bc = Bar
"after the click: toolbar visible=$($bc.vis) at $($bc.r.left),$($bc.r.top) .. $($bc.r.right),$($bc.r.bottom)"
$nc = Loupe 'after the click' 1900 1000 'clicked'
$nc.msg
if (-not $bc.vis) {
    # Two very different reasons for the same missing bar, and the card tells them
    # apart: still drawing means the press never picked anything at all, gone means
    # it picked and the bar failed to follow.
    if ($nc.n -gt 60) {
        $fail += 'a single click neither picked a region nor brought the toolbar up: the card is still drawing, so the press did nothing'
    } else {
        $fail += 'a single click picked a region but did not bring the toolbar up: the bar is still gated on something other than a picked region'
    }
}

if (-not $proc.HasExited) { $proc.Kill() }
if ($fail.Count) { "FAILURES: $($fail.Count)"; $fail | ForEach-Object { "  $_" }; exit 1 }
'PASS'
