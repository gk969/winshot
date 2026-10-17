# 编辑 used to spread the stitched document across the screen: the frame could
# still be dragged and resized, the document leaked past its own edges, there was
# no sign of where in a long document you were, and the wheel moved it the wrong
# way. The request is a locked frame with the document clipped inside it, a
# scrollbar that tracks the visible part, and a wheel that behaves like a wheel.
#
# The sample is a borderless page big enough that the 编辑 frame sits over it
# entirely, so every pixel outside the frame has a value the test can predict from
# the screenshot taken before the summon: the desktop the capture froze, dimmed.
# A leak is then a measurement rather than an impression.
Add-Type -AssemblyName System.Drawing, System.Windows.Forms
Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class LE {
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
# Setting Cursor.Position stops working once Windows decides this process is not
# responding, which it does while a pixel scan runs without pumping. The cursor
# then stays put and every later click lands somewhere else entirely, so the move
# goes through the input stream in normalized screen units, and the read-back
# catches a move that was dropped anyway.
function MoveTo([int]$x, [int]$y) {
    $mx = [int]($x * 65535 / ($VSCREEN.Width - 1))
    $my = [int]($y * 65535 / ($VSCREEN.Height - 1))
    for ($try = 0; $try -lt 3; $try++) {
        [void][System.Windows.Forms.Application]::DoEvents()
        [void][LE]::mouse_event(($MOUSEMOVE -bor $ABSOLUTE), $mx, $my, 0, [UIntPtr]::Zero)
        Start-Sleep -Milliseconds 100
        $gp2 = New-Object LE+POINT
        [void][LE]::GetCursorPos([ref]$gp2)
        if (([Math]::Abs($gp2.x - $x) -le 2) -and ([Math]::Abs($gp2.y - $y) -le 2)) { return }
    }
    throw "the cursor would not move to $x,${y}: injected input is being dropped"
}
function Click([int]$x, [int]$y) {
    MoveTo $x $y
    [void][LE]::mouse_event($LEFTDOWN, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 120
    [void][LE]::mouse_event($LEFTUP, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 350
}
function Drag([int]$x0, [int]$y0, [int]$x1, [int]$y1) {
    MoveTo $x0 $y0
    [void][LE]::mouse_event($LEFTDOWN, 0, 0, 0, [UIntPtr]::Zero)
    for ($i = 1; $i -le 8; $i++) {
        MoveTo ([int]($x0 + ($x1 - $x0) * $i / 8)) ([int]($y0 + ($y1 - $y0) * $i / 8))
    }
    [void][LE]::mouse_event($LEFTUP, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 400
}
# The wheel is routed by focus, not by cursor position, so post the message
# rather than injecting one.
function Wheel($hwnd, [int]$notches, [int]$px, [int]$py) {
    $w = [IntPtr]((120 * $notches) -shl 16)
    $l = [IntPtr]((($py -band 0xFFFF) -shl 16) -bor ($px -band 0xFFFF))
    [void][LE]::PostMessage($hwnd, 0x020A, $w, $l)
    [void][System.Windows.Forms.Application]::DoEvents()
    Start-Sleep -Milliseconds 500
    [void][System.Windows.Forms.Application]::DoEvents()
}
function Find-Win([string]$title) {
    $found = New-Object System.Collections.ArrayList
    $cb = [LE+EnumProc] {
        param($h, $l)
        $t = New-Object System.Text.StringBuilder 512
        [void][LE]::GetWindowText($h, $t, 512)
        if ($t.ToString() -eq $title) { [void]$found.Add($h) }
        return $true
    }
    [void][LE]::EnumWindows($cb, [IntPtr]::Zero)
    return @($found)
}
function VisibleBars($parent) {
    $list = New-Object System.Collections.ArrayList
    $cb = [LE+EnumProc] {
        param($h, $l)
        if ([LE]::IsWindowVisible($h)) {
            $r = New-Object LE+RECT
            if ([LE]::GetWindowRect($h, [ref]$r)) {
                if (($r.right - $r.left) -gt 40 -and ($r.bottom - $r.top) -gt 10) {
                    [void]$list.Add(@{ h = $h; left = $r.left; top = $r.top;
                                       right = $r.right; bottom = $r.bottom })
                }
            }
        }
        return $true
    }
    [void][LE]::EnumChildWindows($parent, $cb, [IntPtr]::Zero)
    return $list
}
function Toolbar($overlay) {
    $bars = @(VisibleBars $overlay)
    if ($bars.Count -eq 0) { return $null }
    return @($bars | Sort-Object { ($_.right - $_.left) } -Descending)[0]
}
# kThumb, 0xFF9AA0A6, drawn opaque down the right edge of the frame. A row counts
# only if most of the track's width is that grey, so anti-aliased text in the
# document behind it cannot pass for a thumb.
function IsThumb($bmp, [int]$x, [int]$y) {
    $c = $bmp.GetPixel($x, $y)
    return ([Math]::Abs($c.R - 154) -le 18 -and [Math]::Abs($c.G - 160) -le 18 -and
            [Math]::Abs($c.B - 166) -le 18)
}
function Thumb-Rect($bmp, [int]$trackL, [int]$trackR, [int]$y0, [int]$y1) {
    $tr = -1; $br = -1
    for ($ty = $y0; $ty -le $y1; $ty++) {
        $n4 = 0
        for ($tx = $trackL; $tx -lt $trackR; $tx++) {
            if (IsThumb $bmp $tx $ty) { $n4++ }
        }
        if ($n4 -ge (($trackR - $trackL) - 2)) {
            if ($tr -lt 0) { $tr = $ty }
            $br = $ty
        }
        if (($ty - $y0) % 400 -eq 0) { [void][System.Windows.Forms.Application]::DoEvents() }
    }
    if ($tr -lt 0) { return $null }
    return @{ top = $tr; bottom = $br; h = $br - $tr + 1 }
}
# How far a pixel outside the frame is from the desktop the capture froze, with
# the overlay's dim on top of it. kDim is 0x99 alpha, i.e. 60% black, so the
# desktop comes through at 40%; the un-dimmed factor is kept as a comparison in
# case that constant ever moves.
function Dim-Diff($shot, $desk, [int]$x, [int]$y, [double]$f) {
    $a = $shot.GetPixel($x, $y); $b = $desk.GetPixel($x, $y)
    return ([Math]::Abs($a.R - [int]($b.R * $f)) + [Math]::Abs($a.G - [int]($b.G * $f)) +
            [Math]::Abs($a.B - [int]($b.B * $f)))
}

$fail = @()
$SCREEN = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
$FRAME_H = [int]($SCREEN.Height * 80 / 100)
$GAP = 2

MoveTo 3400 1900
Start-Sleep -Milliseconds 400
Get-Process winshot -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 600
Get-ChildItem 'D:\Project\winshot\obj\le_*.png' -ErrorAction SilentlyContinue | Remove-Item -Force

# A borderless page: no title bar, so nothing on it changes between the reference
# screenshot and the one taken in 编辑, and the frame can sit over it with room on
# all four sides.
$FX = 1400; $FY = 150; $FW = 1050; $FH = 1900
$sample = New-Object System.Windows.Forms.Form
$sample.Text = 'WinShotScrollSample'
$sample.FormBorderStyle = 'None'
$sample.ShowInTaskbar = $false
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
[void][LE]::SetForegroundWindow($sample.Handle)
[System.Windows.Forms.Application]::DoEvents()
# Focusing an edit selects all its text, and the highlight repaints every row the
# stitcher compares.
$box.Select(0, 0)
[System.Windows.Forms.Application]::DoEvents()
function Offset() { return (0 - [int]$box.GetPositionFromCharIndex(0).Y) }

$SX0 = 1500; $SY0 = 300; $SX1 = 2300; $SY1 = 900
$SW = $SX1 - $SX0; $SH = $SY1 - $SY0

$before = Grab 'D:\Project\winshot\obj\le_before.png'
$offStart = (Offset)
"page offset at the start: $offStart"

$proc = Start-Process -FilePath 'D:\Project\winshot\x64\Debug\winshot.exe' -PassThru
Start-Sleep -Seconds 2
$sink = @(Find-Win 'WinShotSink')
if ($sink.Count -eq 0) { 'FAIL: no sink window'; exit 1 }
[void][LE]::PostMessage($sink[0], $HOTKEY, [IntPtr]::Zero, [IntPtr]::Zero)
Start-Sleep -Seconds 2
$ov = @(Find-Win 'WinShotOverlay')
if ($ov.Count -eq 0) { 'FAIL: no overlay window'; exit 1 }

Drag $SX0 $SY0 $SX1 $SY1
$bar = Toolbar $ov[0]
if (-not $bar) { 'FAIL: no toolbar after the drag'; exit 1 }
Click ((SlotX $bar.left 8) + [int]($CELL / 2)) ([int](($bar.top + $bar.bottom) / 2))
if (@(Find-Win 'WinShotLongBar').Count -eq 0) { 'FAIL: 长截图 did not start'; exit 1 }
[void][LE]::SetForegroundWindow($sample.Handle)
[System.Windows.Forms.Application]::DoEvents()

# One notch per message: the stitcher only searches 160 rows at a time, so a
# multi-notch jump looks like a page turn and stops the session.
$NOTCH = 0
for ($i = 0; $i -lt 14; $i++) {
    Wheel $box.Handle -1 2310 410
    if ($i -eq 0) { $NOTCH = (Offset) - $offStart }
}
$offEnd = (Offset)
"page offset after 14 notches: $offEnd (one notch = $NOTCH)"
if ($NOTCH -lt 100 -or $NOTCH -gt 200) {
    "FAIL: a wheel notch moved the page $NOTCH px, expected about 141"
    $sample.Close(); exit 1
}
# The document is the hole plus everything scrolled past since: tall enough that
# it cannot fit the 80%-of-screen frame, which is what makes the scrollbar appear.
$wantDoc = $SH + ($offEnd - $offStart)
"document should be about $wantDoc rows"

$lb = @(Find-Win 'WinShotLongBar')
if ($lb.Count -eq 0) { 'FAIL: the long-shot bar went away mid-session'; exit 1 }
$lr = New-Object LE+RECT
[void][LE]::GetWindowRect($lb[0], [ref]$lr)
Click ($lr.left + 22) ([int](($lr.top + $lr.bottom) / 2))
Start-Sleep -Milliseconds 700
$ov2 = @(Find-Win 'WinShotOverlay')
if ($ov2.Count -eq 0) { 'FAIL: 编辑 closed the capture'; exit 1 }
$bar2 = Toolbar $ov2[0]
if (-not $bar2) { 'FAIL: no toolbar after 编辑'; exit 1 }
if (@(Find-Win 'WinShotLongBar').Count -ne 0) { $fail += '编辑 left the long-shot bar up' }

# The frame: as wide as the document, 80% of the screen tall, centred, with the
# toolbar hanging 2px below it.
$FL = $bar2.left
$FB = $bar2.top - $GAP
$FT = $FB - $FRAME_H
$FR = $FL + $SW
$wantL = [int](($SCREEN.Width - $SW) / 2)
$wantT = [int](($SCREEN.Height - $FRAME_H) / 2)
"frame: $FL,$FT .. $FR,$FB  (want left=$wantL top=$wantT)"
if ($FL -ne $wantL -or $FT -ne $wantT) {
    $fail += "the 编辑 frame is at $FL,$FT, want $wantL,$wantT"
}

# --- 1. nothing of the document outside the frame -----------------------------
# Four bands just outside the frame, all of them over the sample page, compared
# against the desktop as it was when the capture started.
$edit = Grab 'D:\Project\winshot\obj\le_edit.png'
$bands = @(
    @{ x0 = $FL - 100; x1 = $FL - 20; y0 = $FT + 40; y1 = $FB - 40 },
    @{ x0 = $FR + 20;  x1 = $FR + 100; y0 = $FT + 40; y1 = $FB - 40 },
    # The W x H card hangs above the frame's top-left corner, so the band up
    # there starts clear of it.
    @{ x0 = $FL + 160; x1 = $FR - 40; y0 = $FT - 60; y1 = $FT - 20 },
    @{ x0 = $FL + 40;  x1 = $FR - 40; y0 = $FB + 40; y1 = $FB + 100 }
)
$d4 = 0.0; $d1 = 0.0; $n5 = 0; $bad4 = 0; $where = @()
foreach ($bd in $bands) {
    for ($by = $bd.y0; $by -le $bd.y1; $by += 13) {
        for ($bx = $bd.x0; $bx -le $bd.x1; $bx += 13) {
            $e4 = Dim-Diff $edit $before $bx $by 0.4
            $e1 = Dim-Diff $edit $before $bx $by 1.0
            $d4 += $e4; $d1 += $e1; $n5++
            if ($e4 -gt 30) { $bad4++; if ($where.Count -lt 6) { $where += "$bx,$by" } }
        }
        [void][System.Windows.Forms.Application]::DoEvents()
    }
}
"outside the frame: mean difference from the dimmed desktop $([Math]::Round($d4 / $n5, 1)), from the undimmed one $([Math]::Round($d1 / $n5, 1)), over $n5 points, $bad4 of them off by more than 30"
if ($d4 -gt $d1) {
    $fail += "the screen outside the frame is closer to the undimmed desktop than to the dimmed one, so the document is showing through"
}
if ($bad4 -gt 0) {
    $fail += "$bad4 of $n5 points outside the frame are not the dimmed desktop ($($where -join ' ')): the document leaks past the frame"
}
$edit.Dispose()

# --- 2. the scrollbar thumb ---------------------------------------------------
# The track is 8px wide, inset 3px from the frame's right edge.
$trackL = $FR - 11; $trackR = $FR - 3
$shot0 = Grab $null
$th0 = Thumb-Rect $shot0 $trackL $trackR $FT $FB
$shot0.Dispose()
if (-not $th0) {
    $fail += "no scrollbar thumb in the track at x $trackL..$trackR, although the document is taller than the frame"
} else {
    "thumb: y $($th0.top)..$($th0.bottom) ($($th0.h) px) in frame $FT..$FB"
    if ([Math]::Abs($th0.top - $FT) -gt 4) {
        $fail += "the thumb starts at $($th0.top) but the frame starts at ${FT}: the document does not start at its top"
    }
    if ($th0.h -ge ($FB - $FT)) { $fail += 'the thumb is as tall as the frame, so it is not a thumb' }
    # thumb height = frame height^2 / document height, which is the usual
    # proportion and the one the app draws.
    $docFromThumb = [int](($FRAME_H * $FRAME_H) / $th0.h)
    "document height implied by the thumb: $docFromThumb (want about $wantDoc)"
    if ([Math]::Abs($docFromThumb - $wantDoc) -gt ($wantDoc * 0.1)) {
        $fail += "the thumb implies a $docFromThumb row document, want about $wantDoc"
    }
}

# --- 3. dragging the thumb scrolls the document -------------------------------
if ($th0) {
    $grabY = $th0.top + 40
    Drag ($trackL + 4) $grabY ($trackL + 4) ($grabY + 400)
    $shot1 = Grab 'D:\Project\winshot\obj\le_drag.png'
    $th1 = Thumb-Rect $shot1 $trackL $trackR $FT $FB
    $shot1.Dispose()
    if (-not $th1) {
        $fail += 'the thumb vanished while it was being dragged'
    } else {
        "thumb after a 400px drag: y $($th1.top)..$($th1.bottom) (moved $($th1.top - $th0.top))"
        if ([Math]::Abs(($th1.top - $th0.top) - 400) -gt 30) {
            $fail += "dragging the thumb 400px moved it $($th1.top - $th0.top)px"
        }
    }
}

# --- 4. the wheel, in the right direction -------------------------------------
# A forward notch is the one that moves a page up, so it has to take the document
# back towards its top: the thumb moves up.
if ($th1) {
    Wheel $ov2[0] 1 ($FL + 300) ($FT + 300)
    $shot2 = Grab $null
    $th2 = Thumb-Rect $shot2 $trackL $trackR $FT $FB
    $shot2.Dispose()
    if (-not $th2) {
        $fail += 'the thumb disappeared after the wheel'
    } else {
        "thumb after one forward notch: y $($th2.top) (was $($th1.top))"
        if ($th2.top -ge $th1.top) {
            $fail += "a forward wheel notch moved the document down, not up (thumb $($th1.top) -> $($th2.top))"
        }
    }
    # Back to the top: the thumb returns to the frame's top edge and stays there.
    for ($i = 0; $i -lt 12; $i++) { Wheel $ov2[0] 1 ($FL + 300) ($FT + 300) }
    $shot3 = Grab 'D:\Project\winshot\obj\le_top.png'
    $th3 = Thumb-Rect $shot3 $trackL $trackR $FT $FB
    $shot3.Dispose()
    if (-not $th3) {
        $fail += 'the thumb disappeared while scrolling back to the top'
    } elseif ([Math]::Abs($th3.top - $FT) -gt 4) {
        $fail += "after scrolling up past the start the thumb sits at $($th3.top), want the frame top at $FT"
    } else {
        "thumb back at the frame top after scrolling up past the start"
    }
}

# --- 5. the frame is locked ---------------------------------------------------
# Inside the frame and on its edge used to be a move and a resize. Neither is a
# frame operation any more, and the toolbar hangs off the frame, so a frame that
# moved would show up here.
$frameBefore = "$FL,$FT,$FR,$FB"
Drag ($FL + 400) ($FT + 400) ($FL + 480) ($FT + 340)
$barA = Toolbar $ov2[0]
Drag ($FL - 5) ($FT - 5) ($FL + 45) ($FT + 45)
$barB = Toolbar $ov2[0]
if (-not $barA -or -not $barB) {
    $fail += 'pressing inside or on the edge of the 编辑 frame closed the toolbar'
} else {
    $after = "$($barA.left),$($barA.top - $GAP - $FRAME_H),$($barA.left + $SW),$($barA.top - $GAP)"
    $afterB = "$($barB.left),$($barB.top - $GAP - $FRAME_H),$($barB.left + $SW),$($barB.top - $GAP)"
    "frame after dragging inside it: $after"
    "frame after dragging its top-left edge: $afterB"
    if ($after -ne $frameBefore) { $fail += "dragging inside the 编辑 frame moved it from $frameBefore to $after" }
    if ($afterB -ne $frameBefore) { $fail += "dragging the 编辑 frame's edge moved it from $frameBefore to $afterB" }
}

# --- 6. the whole document is still the result --------------------------------
[System.Windows.Forms.Clipboard]::SetText('EMPTY')
Start-Sleep -Milliseconds 200
Click ((SlotX $bar2.left 14) + [int]($CELL / 2)) ([int](($bar2.top + $bar2.bottom) / 2))
Start-Sleep -Milliseconds 900
$do = [System.Windows.Forms.Clipboard]::GetDataObject()
$clip = $null
if ($do -and $do.GetDataPresent([System.Windows.Forms.DataFormats]::Bitmap)) {
    $clip = $do.GetData([System.Windows.Forms.DataFormats]::Bitmap)
}
if (-not $clip) {
    'FAIL: no image on the clipboard'
    exit 1
}
"clipboard image: $($clip.Width) x $($clip.Height) (want $SW x about $wantDoc)"
if ($clip.Width -ne $SW) { $fail += "the clipboard image is $($clip.Width) wide, want $SW" }
if ([Math]::Abs($clip.Height - $wantDoc) -gt ($wantDoc * 0.1)) {
    $fail += "the clipboard image is $($clip.Height) tall, want about $wantDoc"
}
$clip.Dispose(); $before.Dispose()

[void][System.Windows.Forms.SendKeys]::SendWait('{ESC}')
Start-Sleep -Milliseconds 300
if (-not $proc.HasExited) { $proc.Kill() }
$sample.Close()
if ($fail.Count) { "FAILURES: $($fail.Count)"; $fail | ForEach-Object { "  $_" }; exit 1 }
'PASS'
