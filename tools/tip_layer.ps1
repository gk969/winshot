# The 提示 card has to hang under the tool bar exactly as 工具栏-矩形-提示.png
# draws it, and once the 粗细/颜色 bar is open it has to float over that bar
# rather than be pushed below it. It used to be painted inside the overlay's
# client area, where a child window always covers it; it is now its own topmost
# window, which can.
#
# Proof without a z-order API: one shot with the pointer over a tool icon (card
# up) and one with the pointer inside the region (card gone), the property bar
# open in both. The difference is the card. Where it falls says whether the bar
# kept its old place under it or the card is floating over the bar.
Add-Type -AssemblyName System.Drawing, System.Windows.Forms
Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class TL {
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
function MoveTo([int]$x, [int]$y) {
    [System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point($x, $y)
    Start-Sleep -Milliseconds 160
}
function Drag([int]$x1, [int]$y1, [int]$x2, [int]$y2) {
    MoveTo $x1 $y1
    [void][TL]::mouse_event($LEFTDOWN, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 120
    for ($i = 1; $i -le 12; $i++) {
        MoveTo ([int]($x1 + ($x2-$x1) * $i / 12)) ([int]($y1 + ($y2-$y1) * $i / 12))
    }
    Start-Sleep -Milliseconds 150
    [void][TL]::mouse_event($LEFTUP, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 350
}
function Click([int]$x, [int]$y) {
    MoveTo $x $y
    [void][TL]::mouse_event($LEFTDOWN, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 120
    [void][TL]::mouse_event($LEFTUP, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 350
}
function Find-Wins([string]$title) {
    $found = New-Object System.Collections.ArrayList
    $cb = [TL+EnumProc] {
        param($h, $l)
        $t = New-Object System.Text.StringBuilder 256
        [void][TL]::GetWindowText($h, $t, 256)
        if ($t.ToString() -eq $title) { [void]$found.Add($h) }
        return $true
    }
    [void][TL]::EnumWindows($cb, [IntPtr]::Zero)
    return $found.ToArray()
}
function Find-Kids([IntPtr]$parent, [string]$title) {
    $found = New-Object System.Collections.ArrayList
    $cb = [TL+EnumProc] {
        param($h, $l)
        $t = New-Object System.Text.StringBuilder 256
        [void][TL]::GetWindowText($h, $t, 256)
        if ($t.ToString() -eq $title -and [TL]::IsWindowVisible($h)) { [void]$found.Add($h) }
        return $true
    }
    [void][TL]::EnumChildWindows($parent, $cb, [IntPtr]::Zero)
    return $found.ToArray()
}
function Rect-Of([IntPtr]$h) {
    $r = New-Object TL+RECT
    [void][TL]::GetWindowRect($h, [ref]$r)
    return $r
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
[void][TL]::PostMessage($sink[0], 0x8002, [IntPtr]::Zero, [IntPtr]::Zero)
Start-Sleep -Seconds 2

Drag $sel[0] $sel[1] $sel[2] $sel[3]
$ov = @(Find-Wins 'WinShotOverlay')
if ($ov.Count -eq 0) { 'FAIL: no overlay window'; exit 1 }

# Slot 0 is the rectangle tool; arming it is what opens the property bar.
$tb = @(Find-Kids $ov[0] 'WinShotToolbar')
if ($tb.Count -eq 0) { 'FAIL: no toolbar'; exit 1 }
$tr = Rect-Of $tb[0]
$s = ($tr.bottom - $tr.top) / 32.0
$cell = [int][Math]::Round(27 * $s); $pad = [int][Math]::Round(4 * $s)
Click ($tr.left + $pad + [int]($cell / 2)) ([int](($tr.top + $tr.bottom) / 2))

$pb = @(Find-Kids $ov[0] 'WinShotPropBar')
if ($pb.Count -eq 0) { 'FAIL: arming the rectangle tool did not open the property bar'; exit 1 }
$pr = Rect-Of $pb[0]
"toolbar  $($tr.left),$($tr.top) .. $($tr.right),$($tr.bottom)"
"propbar  $($pr.left),$($pr.top) .. $($pr.right),$($pr.bottom)"

# Hover the ellipse icon, the slot next to the armed one, so the card has to
# appear beside the tool that opened the property bar.
$hoverX = $tr.left + $pad + $cell + [int]($cell / 2)
$hoverY = [int](($tr.top + $tr.bottom) / 2)

# The card's box, from the difference between the pointer over the icon and the
# pointer away from the bars. Only the tool bar is skipped: hovering lights the
# icon inside it, and that change is not the card. The property bar is no longer
# skipped, because the card is now expected to lie on top of it.
function Card-Box([string]$onPath, [string]$offPath, $bars) {
    MoveTo $hoverX $hoverY
    Start-Sleep -Milliseconds 450
    $c1 = Grab $onPath
    MoveTo 1300 900
    Start-Sleep -Milliseconds 450
    $c0 = Grab $offPath

    $cl = -1; $ct = -1; $cr = -1; $cb2 = -1; $cn = 0; $cw = 0
    for ($y = ($sel[1] - 200); $y -lt [Math]::Min($sel[3] + 320, 2160); $y += 2) {
        for ($x = ($sel[0] - 60); $x -lt ($sel[2] + 60); $x += 2) {
            $covered = $false
            foreach ($q in $bars) {
                if ($x -ge $q.left -and $x -lt $q.right -and $y -ge $q.top -and $y -lt $q.bottom) {
                    $covered = $true; break
                }
            }
            if ($covered) { continue }
            $ca = $c1.GetPixel($x, $y); $cb = $c0.GetPixel($x, $y)
            $d = [Math]::Abs($ca.R - $cb.R) + [Math]::Abs($ca.G - $cb.G) + [Math]::Abs($ca.B - $cb.B)
            if ($d -lt 40) { continue }
            $cn++
            if ($cl -lt 0 -or $x -lt $cl) { $cl = $x }
            if ($x -gt $cr) { $cr = $x }
            if ($ct -lt 0) { $ct = $y }
            $cb2 = $y
            if ($ca.R -gt 235 -and $ca.G -gt 235 -and $ca.B -gt 235) { $cw++ }
        }
    }
    $c1.Dispose(); $c0.Dispose()
    if ($cl -lt 0) { return $null }
    return @{ l = $cl; t = $ct; r = $cr; b = $cb2; n = $cn; white = $cw }
}

$withBar = Card-Box 'D:\Project\winshot\obj\tip_on.png' 'D:\Project\winshot\obj\tip_off.png' @($tr)
if (-not $withBar) {
    $fail += 'hovering the tool icon changed nothing outside the tool bar; no 提示 card is visible'
} else {
    "with the property bar open: card $($withBar.l),$($withBar.t) .. $($withBar.r),$($withBar.b)" +
        "  ($($withBar.n) px, $($withBar.white) white)"
}

# Where the card lies over the property bar, read while both are still up: the
# card's own paper has to be what is there, not the bar's chrome. This has to be
# sampled now; the control case below closes the bar again.
$ovSeen = 0; $ovChrome = 0; $ovPaper = 0
if ($withBar) {
    MoveTo $hoverX $hoverY
    Start-Sleep -Milliseconds 450
    $shot = Grab 'D:\Project\winshot\obj\tip_over.png'
    $x0 = [Math]::Max($withBar.l, $pr.left); $x1 = [Math]::Min($withBar.r + 2, $pr.right)
    $y0 = [Math]::Max($withBar.t, $pr.top); $y1 = [Math]::Min($withBar.b + 2, $pr.bottom)
    for ($y = $y0; $y -lt $y1; $y += 2) {
        for ($x = $x0; $x -lt $x1; $x += 2) {
            $c = $shot.GetPixel($x, $y)
            $ovSeen++
            if ([Math]::Abs($c.R - 235) -le 6 -and [Math]::Abs($c.G - 239) -le 6 -and
                [Math]::Abs($c.B - 243) -le 6) { $ovChrome++ }
            elseif ($c.R -gt 245 -and $c.G -gt 245 -and $c.B -gt 245) { $ovPaper++ }
        }
    }
    $shot.Dispose()
    "over the bar: $ovSeen px sampled, $ovChrome of the bar's own chrome, $ovPaper of card paper"
}

# The same hover with the property bar closed is the control: there the card has
# the tool bar alone above it and is certainly whole, so its height is what a
# whole card measures. Anything shorter is a card a bar is eating.
Click ($tr.left + $pad + [int]($cell / 2)) ([int](($tr.top + $tr.bottom) / 2))
$pb2 = @(Find-Kids $ov[0] 'WinShotPropBar')
"property bar after disarming: $($pb2.Count) visible window(s) (want 0)"
$noBar = Card-Box 'D:\Project\winshot\obj\tip_on2.png' 'D:\Project\winshot\obj\tip_off2.png' @($tr)
if (-not $noBar) {
    $fail += 'the control case shows no card either, so the measurement proves nothing'
} else {
    "with the property bar closed: card $($noBar.l),$($noBar.t) .. $($noBar.r),$($noBar.b)" +
        "  ($($noBar.n) px, $($noBar.white) white)"
}

if ($withBar -and $noBar) {
    if ($withBar.white -lt 40) {
        $fail += "the card has only $($withBar.white) white px; 工具栏-矩形-提示.png shows a white card"
    }
    $hFull = $noBar.b - $noBar.t + 1
    $hOpen = $withBar.b - $withBar.t + 1
    "card height: $hOpen px with the property bar open, $hFull px without"
    if ($hOpen -lt $hFull - 2 -or $hOpen -gt $hFull + 2) {
        $fail += "the card is $hOpen px tall with the property bar open but $hFull px without; the bar is clipping it"
    }
    if ($withBar.white -lt ($noBar.white * 0.7) -or $noBar.white -lt ($withBar.white * 0.7)) {
        $fail += "the card shows $($withBar.white) white px with the property bar open against $($noBar.white) without"
    }

    # The card keeps the place 工具栏-矩形-提示.png gives it: hung 4px under the
    # tool bar, whether or not the property bar is open below it.
    $want = $tr.bottom + [int][Math]::Round(4 * $s)
    "card top: $($withBar.t) with the bar open, $($noBar.t) without; want $want"
    foreach ($c in @($withBar, $noBar)) {
        if ([Math]::Abs($c.t - $want) -gt 4) {
            $fail += "the card's top edge is at $($c.t), not the $want px below the tool bar it is drawn at"
        }
    }

    # And it has to overlap the property bar rather than be pushed under it, with
    # its own paper where the bar's chrome would otherwise be.
    $over = ($withBar.t -lt $pr.bottom) -and ($withBar.b -ge $pr.top)
    "card overlaps the property bar band $($pr.top)..$($pr.bottom): $over"
    if (-not $over) {
        $fail += "the card at $($withBar.t)..$($withBar.b) is clear of the property bar at $($pr.top)..$($pr.bottom); it was pushed away instead of drawn over it"
    }

    if ($ovSeen -eq 0) {
        $fail += "the card's box never falls inside the property bar, so nothing was sampled over it"
    } else {
        if ($ovChrome -gt ($ovSeen * 0.05)) {
            $fail += "$ovChrome of $ovSeen px inside the card's box over the property bar are still the bar's chrome colour; the card is under it"
        }
        if ($ovPaper -lt ($ovSeen * 0.4)) {
            $fail += "only $ovPaper of $ovSeen px over the property bar are the card's white paper"
        }
    }
}

if (-not $proc.HasExited) { $proc.Kill() }
if ($fail.Count) { "FAILURES: $($fail.Count)"; $fail | ForEach-Object { "  $_" }; exit 1 }
'PASS'
