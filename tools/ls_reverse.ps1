# 长截图 used to only ever grow downwards. Scrolling back up landed the frame in
# the middle of the rows already stitched, where neither the down-search nor the
# up-search has a shift to find, so both gave up and the session stopped with
# "画面变化过大". And scrolling past the top of what had been captured never
# extended the document upwards at all.
#
# So the sample starts partway down the page, the session captures some ground
# below it, then comes back:
#   * back onto rows already captured  -> the document must not change at all;
#   * past the top of the session      -> the document must grow by exactly the
#     new rows, and its top must be the page as it stood there.
# The document's height is read off the preview panel beside the hole mid-session
# (it is drawn 1:1 while it fits the screen), and again from the clipboard at the
# end.
Add-Type -AssemblyName System.Drawing, System.Windows.Forms
Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class LR {
    public delegate bool EnumProc(IntPtr h, IntPtr l);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
    [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr p, EnumProc cb, IntPtr l);
    [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint msg, IntPtr w, IntPtr l);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint dx, uint dy, int d, UIntPtr e);
    [DllImport("user32.dll")] public static extern IntPtr WindowFromPoint(POINT p);
    [DllImport("user32.dll")] public static extern bool GetCursorPos(out POINT p);
    [DllImport("user32.dll")] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int left, top, right, bottom; }
    [StructLayout(LayoutKind.Sequential)] public struct POINT { public int x, y; }
}
"@

$LEFTDOWN = 0x0002; $LEFTUP = 0x0004
$MOUSEMOVE = 0x0001; $ABSOLUTE = 0x8000
$VSCREEN = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
$HOTKEY = 0x8002

$PAD = 4; $CELL = 27; $SEP = 14
function SlotX([int]$barLeft, [int]$idx) {
    $seps = 0
    if ($idx -ge 7) { $seps = 1 }
    if ($idx -ge 13) { $seps = 2 }
    return $barLeft + $PAD + $idx * $CELL + $seps * $SEP
}

function Grab([string]$path) {
    $b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    $bmp = New-Object System.Drawing.Bitmap $b.Width, $b.Height
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen($b.Location, [System.Drawing.Point]::Empty, $bmp.Size)
    if ($path) { $bmp.Save($path) }
    $g.Dispose()
    return $bmp
}
# Setting Cursor.Position stops working once Windows has decided this process is
# not responding, which it does while a long pixel scan runs without pumping. The
# cursor then stays put and every later click lands somewhere else entirely, so
# the move goes through the input stream instead, in normalized screen units.
function MoveTo([int]$x, [int]$y) {
    $mx = [int]($x * 65535 / ($VSCREEN.Width - 1))
    $my = [int]($y * 65535 / ($VSCREEN.Height - 1))
    for ($try = 0; $try -lt 3; $try++) {
        # The sample window stops pumping while a pixel scan runs, Windows marks
        # it not responding, and injected input to a hung foreground process is
        # dropped: the cursor stays put and every later click lands somewhere
        # else. Pumping first keeps it alive; the read-back catches the rest.
        [void][System.Windows.Forms.Application]::DoEvents()
        [void][LR]::mouse_event(($MOUSEMOVE -bor $ABSOLUTE), $mx, $my, 0, [UIntPtr]::Zero)
        Start-Sleep -Milliseconds 100
        $gp2 = New-Object LR+POINT
        [void][LR]::GetCursorPos([ref]$gp2)
        if (([Math]::Abs($gp2.x - $x) -le 2) -and ([Math]::Abs($gp2.y - $y) -le 2)) {
            return $true
        }
    }
    return $false
}
function Click([int]$x, [int]$y) {
    MoveTo $x $y
    [void][LR]::mouse_event($LEFTDOWN, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 120
    [void][LR]::mouse_event($LEFTUP, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 350
}
function Drag([int]$x0, [int]$y0, [int]$x1, [int]$y1) {
    MoveTo $x0 $y0
    [void][LR]::mouse_event($LEFTDOWN, 0, 0, 0, [UIntPtr]::Zero)
    for ($i = 1; $i -le 8; $i++) {
        MoveTo ([int]($x0 + ($x1 - $x0) * $i / 8)) ([int]($y0 + ($y1 - $y0) * $i / 8))
    }
    [void][LR]::mouse_event($LEFTUP, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 400
}
# The wheel is routed by focus, not by cursor position, so post the message the
# overlay forwards rather than injecting one.
function Wheel($hwnd, [int]$notches) {
    $w = [IntPtr]((120 * $notches) -shl 16)
    $l = [IntPtr](((410 -shl 16) -bor ((2310 -band 0xFFFF))))
    [void][LR]::PostMessage($hwnd, 0x020A, $w, $l)
    # A posted message only runs when this thread pumps.
    [System.Windows.Forms.Application]::DoEvents()
    Start-Sleep -Milliseconds 500
    [System.Windows.Forms.Application]::DoEvents()
}
function Find-Win([string]$title) {
    $found = New-Object System.Collections.ArrayList
    $cb = [LR+EnumProc] {
        param($h, $l)
        $t = New-Object System.Text.StringBuilder 512
        [void][LR]::GetWindowText($h, $t, 512)
        if ($t.ToString() -eq $title) { [void]$found.Add($h) }
        return $true
    }
    [void][LR]::EnumWindows($cb, [IntPtr]::Zero)
    return @($found)
}
function VisibleBars($parent) {
    $list = New-Object System.Collections.ArrayList
    $cb = [LR+EnumProc] {
        param($h, $l)
        if ([LR]::IsWindowVisible($h)) {
            $r = New-Object LR+RECT
            if ([LR]::GetWindowRect($h, [ref]$r)) {
                if (($r.right - $r.left) -gt 40 -and ($r.bottom - $r.top) -gt 10) {
                    [void]$list.Add(@{ h = $h; left = $r.left; top = $r.top;
                                       right = $r.right; bottom = $r.bottom })
                }
            }
        }
        return $true
    }
    [void][LR]::EnumChildWindows($parent, $cb, [IntPtr]::Zero)
    return $list
}
function Toolbar($overlay) {
    $bars = @(VisibleBars $overlay)
    if ($bars.Count -eq 0) { return $null }
    return @($bars | Sort-Object { ($_.right - $_.left) } -Descending)[0]
}
function Dpx($a, $ax, $ay, $b, $bx, $by) {
    $dp = $a.GetPixel($ax, $ay); $dq = $b.GetPixel($bx, $by)
    return [Math]::Abs($dp.R - $dq.R) + [Math]::Abs($dp.G - $dq.G) + [Math]::Abs($dp.B - $dq.B)
}
# Fraction of a grid of points in the image band at rows [$iy0,$iy1) that
# disagree with the desktop shot at the matching screen position. Only the two
# digits of the line number are sampled: every other glyph on the line reads the
# same wherever the page happens to be. Locals are prefixed because a PowerShell
# function shares its caller's scope.
function MismatchRate($img, $shot, [int]$iy0, [int]$iy1, [int]$sx, [int]$sy,
                      [int]$ix = 0, [int]$iy = 0) {
    $mBad = 0; $mN = 0
    for ($mr = 0; $mr -lt 8; $mr++) {
        $my = [int]($iy0 + ($iy1 - $iy0) * $mr / 7)
        for ($mc = 0; $mc -lt 10; $mc++) {
            $mx = [int](85 + 40 * $mc / 9)
            $mN++
            if ((Dpx $img ($ix + $mx) ($iy + $my) $shot ($sx + $mx) ($sy + ($my - $iy0))) -gt 24) {
                $mBad++
            }
        }
    }
    return ($mBad / $mN)
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
$SCREEN = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds

MoveTo 3400 1900
Start-Sleep -Milliseconds 400
Get-Process winshot -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 600
Get-ChildItem 'D:\Project\winshot\obj\lr_*.png' -ErrorAction SilentlyContinue | Remove-Item -Force

# The same scrollable target as stage8: numbered lines in a read-only edit, so a
# notch moves the page a known 100px and the stitched rows can be checked against
# screenshots of the real desktop.
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
[void][LR]::SetForegroundWindow($sample.Handle)
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
$SW = $SX1 - $SX0; $SH = $SY1 - $SY0

# --- start the session partway down the page --------------------------------
# Only then does scrolling up have anywhere to go, and only past the top of the
# session does it have anything new to add.
# One message with four notches' worth of delta moves the edit twelve lines at
# once; the stitcher is not running yet, so the size of the step does not matter.
Wheel $box.Handle -4
$offStart = Offset
$NOTCH = [int]($offStart / 4)
"page offset at the session start: $offStart px, one notch = $NOTCH px"
if ($offStart -lt 300 -or $offStart -gt 1200) {
    "FAIL: the sample did not land partway down the page (at $offStart)"
    $sample.Close(); exit 1
}
$start = Grab 'D:\Project\winshot\obj\lr_start.png'

$proc = Start-Process -FilePath 'D:\Project\winshot\x64\Debug\winshot.exe' -PassThru
Start-Sleep -Seconds 2
$sink = @(Find-Win 'WinShotSink')
if ($sink.Count -eq 0) { "FAIL: no sink window"; exit 1 }
[void][LR]::PostMessage($sink[0], $HOTKEY, [IntPtr]::Zero, [IntPtr]::Zero)
Start-Sleep -Seconds 2
$ov = @(Find-Win 'WinShotOverlay')
if ($ov.Count -eq 0) { "FAIL: no overlay window"; exit 1 }

Drag $SX0 $SY0 $SX1 $SY1
$bar = Toolbar $ov[0]
if (-not $bar) { "FAIL: no toolbar after the drag"; exit 1 }
Click ((SlotX $bar.left 8) + [int]($CELL / 2)) ([int](($bar.top + $bar.bottom) / 2))
if (@(Find-Win 'WinShotLongBar').Count -eq 0) { "FAIL: 长截图 did not start"; exit 1 }
[void][LR]::SetForegroundWindow($sample.Handle)
[System.Windows.Forms.Application]::DoEvents()
$box.Select(0, 0)
[System.Windows.Forms.Application]::DoEvents()

# --- down, then back onto ground already captured ---------------------------
# One notch per message: the stitcher only searches 160 rows of overlap and 440px
# of travel, so four notches arriving at once look like a page turn to it.
for ($i = 0; $i -lt 4; $i++) { Wheel $box.Handle -1 }
Start-Sleep -Milliseconds 800
$down = Grab 'D:\Project\winshot\obj\lr_down.png'
$d1 = Doc-Height $down 1200 $SX0
$offDown = Offset
"after scrolling down to $offDown px: document $(if ($d1) { $d1.h } else { '(no preview)' }) rows, preview ring col $(if ($d1) { $d1.col } else { '-' })"
if (-not $d1) { "FAIL: no stitched preview beside the hole"; exit 1 }
$want1 = $SH + ($offDown - $offStart)
if ([Math]::Abs($d1.h - $want1) -gt 2 * $LINEH) {
    $fail += "scrolling down $($offDown - $offStart)px made the document $($d1.h) rows, want $want1"
}

# Back up two notches: still inside the rows already stitched, so nothing here
# may change.
Wheel $box.Handle 1
Wheel $box.Handle 1
Start-Sleep -Milliseconds 800
$back = Grab 'D:\Project\winshot\obj\lr_back.png'
$d2 = Doc-Height $back 1200 $SX0
$offBack = Offset
"after scrolling back to $offBack px: document $(if ($d2) { $d2.h } else { '(no preview)' }) rows (want unchanged at $($d1.h))"
if (-not $d2) {
    $fail += 'scrolling back onto captured ground lost the preview, i.e. ended the session'
} elseif ($d2.h -ne $d1.h) {
    $fail += "scrolling back onto rows already captured changed the document from $($d1.h) to $($d2.h) rows"
}

# --- and past the top of the session ----------------------------------------
# Up past the top of the session and on to the top of the page.
$up = [int]($offBack / $NOTCH) + 3
for ($i = 0; $i -lt $up; $i++) { Wheel $box.Handle 1 }
Start-Sleep -Milliseconds 800
$top = Grab 'D:\Project\winshot\obj\lr_top.png'
$d3 = Doc-Height $top 1200 $SX0
$offTop = Offset
"after scrolling up to $offTop px: document $(if ($d3) { $d3.h } else { '(no preview)' }) rows (want $($d1.h + ($offStart - $offTop)))"
if (-not $d3) {
    $fail += 'scrolling past the top of the session lost the preview'
} else {
    $want3 = $d1.h + ($offStart - $offTop)
    if ([Math]::Abs($d3.h - $want3) -gt 2 * $LINEH) {
        $fail += "scrolling $([Math]::Abs($offStart - $offTop))px past the top of the session made the document $($d3.h) rows, want $want3"
    }
}

# --- finish: the clipboard has to agree -------------------------------------
$lb = @(Find-Win 'WinShotLongBar')
if ($lb.Count -eq 0) { "FAIL: the long-shot bar went away mid-session"; exit 1 }
$lr = New-Object LR+RECT
[void][LR]::GetWindowRect($lb[0], [ref]$lr)
# 编辑 is the bar's first slot: client x 4..40, so the middle of it is 22.
Click ($lr.left + 22) ([int](($lr.top + $lr.bottom) / 2))
Start-Sleep -Milliseconds 600
$ov2 = @(Find-Win 'WinShotOverlay')
if ($ov2.Count -eq 0) { "FAIL: 编辑 closed the capture"; exit 1 }
if (@(Find-Win 'WinShotLongBar').Count -ne 0) { $fail += '编辑 left the long-shot bar up' }
$bar2 = Toolbar $ov2[0]
if (-not $bar2) { "FAIL: no toolbar to finish with"; exit 1 }
[System.Windows.Forms.Clipboard]::SetText('EMPTY')
Start-Sleep -Milliseconds 200
Click ((SlotX $bar2.left 14) + [int]($CELL / 2)) ([int](($bar2.top + $bar2.bottom) / 2))
Start-Sleep -Milliseconds 900
$do = [System.Windows.Forms.Clipboard]::GetDataObject()
$clip = $null
if ($do -and $do.GetDataPresent([System.Windows.Forms.DataFormats]::Bitmap)) {
    $clip = $do.GetData([System.Windows.Forms.DataFormats]::Bitmap)
}
if (-not $clip) { "FAIL: no image on the clipboard"; exit 1 }
"clipboard image: $($clip.Width) x $($clip.Height)"
if ($d3 -and [Math]::Abs($clip.Height - $d3.h) -gt 4) {
    $fail += "the export is $($clip.Height) rows but the preview showed $($d3.h)"
}

# The rows the session added on the way up are the top of the document, and they
# are the page as it stood at the top — not as it stood when the session started.
$topVsTop = MismatchRate $clip $top 0 40 $SX0 $SY0
$topVsDown = MismatchRate $clip $down 0 40 $SX0 $SY0
$desktops = MismatchRate $top $down 0 40 $SX0 $SY0 $SX0 $SY0
$botVsDown = MismatchRate $clip $down ($clip.Height - 40) ($clip.Height - 6) $SX0 ($SY1 - 40)
"document top rows vs the page at the top: mismatch $([Math]::Round($topVsTop * 100))% (want 0%)"
"document top rows vs the page as it stood at the bottom: mismatch $([Math]::Round($topVsDown * 100))% (the two views differ by $([Math]::Round($desktops * 100))%)"
"document bottom rows vs the page as it stood at the bottom: mismatch $([Math]::Round($botVsDown * 100))% (want 0%)"
if ($topVsTop -gt 0.05) { $fail += 'the top of the stitched image is not the page as it stood at the top' }
if ($desktops -lt 0.1) { $fail += 'the two views of the page are identical, so the check proves nothing' }
if ($topVsDown - $topVsTop -lt 0.1) { $fail += 'the top of the stitched image is still the view the session started from' }
if ($botVsDown -gt 0.05) { $fail += 'the bottom of the stitched image is not the page as it stood at the bottom of the scroll' }

if ($clip) {
    $c = $clip.Clone([System.Drawing.Rectangle]::new(0, 0, $clip.Width, $clip.Height), $clip.PixelFormat)
    $c.Save('D:\Project\winshot\obj\lr_result.png'); $c.Dispose()
    $clip.Dispose()
}
foreach ($b in @($start, $down, $back, $top)) { if ($b) { $b.Dispose() } }
$sample.Close()
if ($proc -and -not $proc.HasExited) { $proc.Kill() }
if ($fail.Count) { "FAILURES: $($fail.Count)"; $fail | ForEach-Object { "  $_" }; exit 1 }
'PASS'
