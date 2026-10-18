# Long-shot mode samples the hole every 150ms and can only match a page that
# moved less than 440px between two samples, so a fast wheel used to end the
# session with "change too large, stopped". A notch the stitcher has no credit
# for is now refused outright, so the page cannot outrun the sampling.
#
# The wheel is injected at the cursor, the way a hand turns it. That matters more
# here than anywhere else in the suite: the hole is cut out of the overlay's
# window region, so inside it the cursor is over the page and Windows addresses
# the wheel to the page, not to us. The gate therefore lives in a low-level hook
# that runs before that routing, and the only way to reach it is a real wheel
# event. An earlier version of this script posted WM_MOUSEWHEEL at the overlay,
# which is the one route that skips the hook entirely - it proved the gate works
# while testing a path no hand takes.
#
# Three things are checked. One notch through the overlay moves the page, so the
# route is live and a throttled result is not just a dead path. A burst of twelve
# notches moves the page far less than twelve notches' worth. And the session is
# still stitching afterwards: the document keeps growing, and its height equals
# the hole plus the page's total travel, which is what "no duplicated rows and no
# dropped ones" means.
Add-Type -AssemblyName System.Drawing, System.Windows.Forms
Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class LT {
    public delegate bool EnumProc(IntPtr h, IntPtr l);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
    [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr p, EnumProc cb, IntPtr l);
    [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint msg, IntPtr w, IntPtr l);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint dx, uint dy, int d, UIntPtr e);
    [DllImport("user32.dll")] public static extern bool GetCursorPos(out POINT p);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern IntPtr WindowFromPoint(POINT p);
    [DllImport("user32.dll")] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int left, top, right, bottom; }
    [StructLayout(LayoutKind.Sequential)] public struct POINT { public int x, y; }
}
"@

$LEFTDOWN = 0x0002; $LEFTUP = 0x0004
$MOUSEMOVE = 0x0001; $ABSOLUTE = 0x8000; $WHEEL = 0x0800
$SCREEN = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
$VSCREEN = $SCREEN
$HOTKEY = 0x8002

$PAD = 4; $CELL = 27; $SEP = 14
function SlotX([int]$barLeft, [int]$idx) {
    $seps = 0
    if ($idx -ge 7) { $seps = 1 }
    if ($idx -ge 13) { $seps = 2 }
    return $barLeft + $PAD + $idx * $CELL + $seps * $SEP
}

function Grab([string]$path) {
    $bmp = New-Object System.Drawing.Bitmap $VSCREEN.Width, $VSCREEN.Height
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen($VSCREEN.Location, [System.Drawing.Point]::Empty, $bmp.Size)
    if ($path) { $bmp.Save($path) }
    $g.Dispose()
    return $bmp
}
# Setting Cursor.Position stops working once Windows has decided this process is
# not responding, which it does while a long pixel scan runs without pumping.
function MoveTo([int]$x, [int]$y) {
    $mx = [int]($x * 65535 / ($VSCREEN.Width - 1))
    $my = [int]($y * 65535 / ($VSCREEN.Height - 1))
    for ($try = 0; $try -lt 3; $try++) {
        [void][System.Windows.Forms.Application]::DoEvents()
        [void][LT]::mouse_event(($MOUSEMOVE -bor $ABSOLUTE), $mx, $my, 0, [UIntPtr]::Zero)
        Start-Sleep -Milliseconds 100
        $gp2 = New-Object LT+POINT
        [void][LT]::GetCursorPos([ref]$gp2)
        if (([Math]::Abs($gp2.x - $x) -le 2) -and ([Math]::Abs($gp2.y - $y) -le 2)) {
            return $true
        }
    }
    return $false
}
function Click([int]$x, [int]$y) {
    MoveTo $x $y
    [void][LT]::mouse_event($LEFTDOWN, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 120
    [void][LT]::mouse_event($LEFTUP, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 350
}
function Drag([int]$x0, [int]$y0, [int]$x1, [int]$y1) {
    MoveTo $x0 $y0
    [void][LT]::mouse_event($LEFTDOWN, 0, 0, 0, [UIntPtr]::Zero)
    for ($i = 1; $i -le 8; $i++) {
        MoveTo ([int]($x0 + ($x1 - $x0) * $i / 8)) ([int]($y0 + ($y1 - $y0) * $i / 8))
    }
    [void][LT]::mouse_event($LEFTUP, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 400
}
# A real notch at the cursor. The system routes it from the cursor position, so
# the caller is responsible for having the cursor where a user would hold it.
function Notch([int]$notches) {
    [void][LT]::mouse_event($WHEEL, 0, 0, (120 * $notches), [UIntPtr]::Zero)
}
# One notch, given its own sample: this is the pace the throttle is meant to
# allow, and the stitcher has to keep up with it.
function Wheel([int]$x, [int]$y, [int]$notches) {
    MoveTo $x $y
    Notch $notches
    [void][System.Windows.Forms.Application]::DoEvents()
    Start-Sleep -Milliseconds 500
    [void][System.Windows.Forms.Application]::DoEvents()
}
function Find-Win([string]$title) {
    $found = New-Object System.Collections.ArrayList
    $cb = [LT+EnumProc] {
        param($h, $l)
        $t = New-Object System.Text.StringBuilder 512
        [void][LT]::GetWindowText($h, $t, 512)
        if ($t.ToString() -eq $title) { [void]$found.Add($h) }
        return $true
    }
    [void][LT]::EnumWindows($cb, [IntPtr]::Zero)
    return @($found)
}
function VisibleBars($parent) {
    $list = New-Object System.Collections.ArrayList
    $cb = [LT+EnumProc] {
        param($h, $l)
        if ([LT]::IsWindowVisible($h)) {
            $r = New-Object LT+RECT
            if ([LT]::GetWindowRect($h, [ref]$r)) {
                if (($r.right - $r.left) -gt 40 -and ($r.bottom - $r.top) -gt 10) {
                    [void]$list.Add(@{ h = $h; left = $r.left; top = $r.top;
                                       right = $r.right; bottom = $r.bottom })
                }
            }
        }
        return $true
    }
    [void][LT]::EnumChildWindows($parent, $cb, [IntPtr]::Zero)
    return $list
}
function Toolbar($overlay) {
    $bars = @(VisibleBars $overlay)
    if ($bars.Count -eq 0) { return $null }
    return @($bars | Sort-Object { ($_.right - $_.left) } -Descending)[0]
}
# The ring the app draws around the stitched preview: kFrame, the same blue as
# the selection frame.
function IsRing($bmp, [int]$x, [int]$y) {
    $c = $bmp.GetPixel($x, $y)
    return ([Math]::Abs($c.R - 30) -le 20 -and [Math]::Abs($c.G - 159) -le 20 -and
            [Math]::Abs($c.B - 212) -le 20)
}
# The preview panel sits in the dim band to the left of the hole and is drawn 1:1
# while the document fits the screen, so the height of its ring minus the 2px the
# ring sticks out is the document's row count.
function Doc-Height($bmp, [int]$scanFrom, [int]$sx0) {
    $col = -1
    foreach ($px in $scanFrom..($sx0 - 1)) {
        $n2 = 0
        for ($py = 0; $py -lt $SCREEN.Height; $py += 3) { if (IsRing $bmp $px $py) { $n2++ } }
        if ($n2 -gt 250) { $col = $px; break }
    }
    if ($col -lt 0) { return -1 }
    $t = -1; $bt = -1
    for ($py = 0; $py -lt $SCREEN.Height; $py++) {
        if (IsRing $bmp $col $py) { if ($t -lt 0) { $t = $py }; $bt = $py }
    }
    return @{ h = $bt - $t + 1 - 2; col = $col; top = $t }
}

$fail = @()

MoveTo 3400 1900
Start-Sleep -Milliseconds 400
Get-Process winshot -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 600
Get-ChildItem 'D:\Project\winshot\obj\lt_*.png' -ErrorAction SilentlyContinue | Remove-Item -Force

# The same scrollable target as ls_reverse: numbered lines in a read-only edit,
# so a notch moves the page a known amount and the document's rows can be checked
# against the page's travel.
$FX = 2200; $FY = 300; $FW = 900; $FH = 700
$sample = New-Object System.Windows.Forms.Form
$sample.Text = 'WinShotScrollSample'
$sample.FormBorderStyle = 'FixedSingle'
$sample.StartPosition = 'Manual'
$sample.Location = New-Object System.Drawing.Point($FX, $FY)
$sample.Size = New-Object System.Drawing.Size($FW, $FH)
$sample.BackColor = [System.Drawing.Color]::White
$box = New-Object System.Windows.Forms.TextBox
$box.Multiline = $true
$box.ReadOnly = $true
$box.ScrollBars = 'Vertical'
$box.Dock = 'Fill'
$box.Font = New-Object System.Drawing.Font('Consolas', 30)
$box.Text = (1..80 | ForEach-Object { 'LINE {0:D2} ------------------------------' -f $_ }) -join "`r`n"
[void]$sample.Controls.Add($box)
$sample.Show()
[System.Windows.Forms.Application]::DoEvents()
Start-Sleep -Milliseconds 800
[void][LT]::SetForegroundWindow($sample.Handle)
[System.Windows.Forms.Application]::DoEvents()
# Focusing an edit selects all its text, and the highlight repaints every row the
# stitcher compares.
$box.Select(0, 0)
[System.Windows.Forms.Application]::DoEvents()
$LINEH = $box.GetPositionFromCharIndex(40).Y - $box.GetPositionFromCharIndex(0).Y
# Rows of page above the top of the edit: char 0 sits that far above the client
# origin once the page has scrolled.
function Offset() { return (0 - [int]$box.GetPositionFromCharIndex(0).Y) }

$SX0 = 2250; $SY0 = 350; $SX1 = 3050; $SY1 = 950
$SH = $SY1 - $SY0
# Inside the hole and inside the edit, so the cursor never has to move between
# the calibration and the session. Off-centre on purpose: the 提示 card is placed
# at the hole's centre, and a wheel over that card goes to the card, which does
# not scroll.
$WX = 2320; $WY = 420

# One notch at the same point, before the session exists: the gate is not in that
# path, so this measures what an unthrottled notch is worth.
Wheel $WX $WY -1
$one = Offset
Wheel $box.Handle 1
$NOTCH = $one
"one notch of this page: $NOTCH px, line height $LINEH px"
if ($NOTCH -lt 60) { "FAIL: the sample page does not scroll by a notch ($NOTCH)"; exit 1 }

$proc = Start-Process -FilePath 'D:\Project\winshot\x64\Debug\winshot.exe' -PassThru
Start-Sleep -Seconds 2
$sink = @(Find-Win 'WinShotSink')
if ($sink.Count -eq 0) { "FAIL: no sink window"; exit 1 }
[void][LT]::PostMessage($sink[0], $HOTKEY, [IntPtr]::Zero, [IntPtr]::Zero)
Start-Sleep -Seconds 2
$ov = @(Find-Win 'WinShotOverlay')
if ($ov.Count -eq 0) { "FAIL: no overlay window"; exit 1 }

Drag $SX0 $SY0 $SX1 $SY1
$bar = Toolbar $ov[0]
if (-not $bar) { "FAIL: no toolbar after the drag"; exit 1 }
Click ((SlotX $bar.left 8) + [int]($CELL / 2)) ([int](($bar.top + $bar.bottom) / 2))
if (@(Find-Win 'WinShotLongBar').Count -eq 0) { "FAIL: long-shot mode did not start"; exit 1 }
[void][LT]::SetForegroundWindow($sample.Handle)
[System.Windows.Forms.Application]::DoEvents()
$box.Select(0, 0)
[System.Windows.Forms.Application]::DoEvents()
$offA = Offset

# Which window the wheel is addressed to decides which of the two paths a notch
# takes: the hook alone when it goes to the page, the hook and then the overlay's
# forward when it goes to the focus window. Worth printing when this test fails.
function Class-Of($h) {
    if ($h -eq [IntPtr]::Zero) { return '(none)' }
    $sb = New-Object System.Text.StringBuilder 256
    [void][LT]::GetClassName($h, $sb, 256)
    return $sb.ToString()
}
$hit = New-Object LT+POINT; $hit.x = $WX; $hit.y = $WY
"routing: focus=$(Class-Of ([LT]::GetForegroundWindow())) " +
    "under-cursor=$(Class-Of ([LT]::WindowFromPoint($hit)))"

# --- the route is live ------------------------------------------------------
# Without this the burst could read as throttled simply because the hook is not
# installed at all and the wheel never reaches the page.
Wheel $WX $WY -1
$offCtl = Offset
$ctl = $offCtl - $offA
"one notch inside the hole: page moved $ctl px (want about $NOTCH)"
if ($ctl -lt [int](0.6 * $NOTCH) -or $ctl -gt [int](1.6 * $NOTCH)) {
    "FAIL: a real notch inside the hole moved the page $ctl px, so the burst below proves nothing"
    exit 1
}

# --- the burst --------------------------------------------------------------
# Twelve notches with nothing between them: they are injected within a few
# milliseconds of each other, well inside one 150ms sample, so the hook should
# let the allowance through and swallow the rest.
MoveTo $WX $WY
for ($i = 0; $i -lt 12; $i++) { Notch -1 }
[void][System.Windows.Forms.Application]::DoEvents()
Start-Sleep -Milliseconds 1500
$offB = Offset
$burst = $offB - $offCtl
$b1 = Grab 'D:\Project\winshot\obj\lt_burst.png'
$d1 = Doc-Height $b1 1200 $SX0
$b1.Dispose()
"burst of 12 notches: page moved $burst px (unthrottled would be $([Math]::Abs(12 * $NOTCH))), document $(if ($d1) { $d1.h } else { '(no preview)' }) rows"
if (-not $d1) { "FAIL: no stitched preview beside the hole"; exit 1 }
if ($burst -lt $NOTCH) {
    $fail += "the burst moved the page only $burst px: the gate swallowed everything, not just the excess"
}
if ($burst -gt 6 * $NOTCH) {
    $fail += "the burst moved the page $burst px, more than 6 notches' worth ($([Math]::Abs(6 * $NOTCH))): the wheel is not throttled"
}
$want1 = $SH + ($offB - $offA)
if ([Math]::Abs($d1.h - $want1) -gt 2 * $LINEH) {
    $fail += "after the burst the document is $($d1.h) rows for $([Math]::Abs($offB - $offA))px of travel, want $want1"
}

# --- and it is still stitching ---------------------------------------------
# Three notches at the pace the gate allows. A session that had stopped on
# "change too large" would keep scrolling the page but add no rows, which is what
# this separates.
for ($i = 0; $i -lt 3; $i++) { Wheel $WX $WY -1 }
Start-Sleep -Milliseconds 800
$offC = Offset
$b2 = Grab 'D:\Project\winshot\obj\lt_after.png'
$d2 = Doc-Height $b2 1200 $SX0
$b2.Dispose()
"three more notches: page at $offC px, document $(if ($d2) { $d2.h } else { '(no preview)' }) rows (was $($d1.h))"
if (-not $d2) {
    $fail += 'the preview disappeared after the burst, i.e. the burst ended the session'
} else {
    $grew = $d2.h - $d1.h
    $wantG = $offC - $offB
    "document growth: $grew rows for $wantG px of travel (want about $([Math]::Abs(3 * $NOTCH)))"
    if ([Math]::Abs($grew - $wantG) -gt 2 * $LINEH) {
        $fail += "three allowed notches grew the document by $grew rows for $wantG px: the session stopped stitching"
    }
    $want2 = $SH + ($offC - $offA)
    if ([Math]::Abs($d2.h - $want2) -gt 2 * $LINEH) {
        $fail += "the document is $($d2.h) rows for $([Math]::Abs($offC - $offA))px of travel, want ${want2}: rows were duplicated or dropped"
    }
}

if (@(Find-Win 'WinShotLongBar').Count -eq 0) { $fail += 'the long-shot bar went away during the burst' }

if ($ov) { [void][System.Windows.Forms.SendKeys]::SendWait('{ESC}') }
Start-Sleep -Milliseconds 400
$sample.Close()
if ($proc -and -not $proc.HasExited) { $proc.Kill() }
if ($fail.Count) { "FAILURES: $($fail.Count)"; $fail | ForEach-Object { "  $_" }; exit 1 }
'PASS'
