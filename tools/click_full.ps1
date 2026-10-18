# Summoning used to leave the first click on the dimmed desktop doing nothing: the
# press started a rubber band, the release found it under 3px, and the region went
# back to exactly the whole screen it already was -- so the next press started the
# same gesture over again. The request is that this click picks the whole screen,
# and the press after it draws.
#
# Two witnesses that the pick really happened. The magnifier card is only drawn
# while the region is still unpicked, and its crosshair is a cyan no other part of
# the UI paints, so it vanishing says m_selPicked is set. The toolbar is placed
# from the region alone, so its rectangle not moving says the region is still the
# whole screen. Then the ellipse tool draws on the very next press.
Add-Type -AssemblyName System.Drawing, System.Windows.Forms
Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class CF {
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
    Start-Sleep -Milliseconds 90
}
function Down { [void][CF]::mouse_event($LEFTDOWN, 0, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 150 }
function Up { [void][CF]::mouse_event($LEFTUP, 0, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 350 }
function Walk([int]$x1, [int]$y1, [int]$x2, [int]$y2, [int]$steps) {
    for ($i = 1; $i -le $steps; $i++) {
        MoveTo ([int]($x1 + ($x2-$x1) * $i / $steps)) ([int]($y1 + ($y2-$y1) * $i / $steps))
    }
}
function Drag([int]$x1, [int]$y1, [int]$x2, [int]$y2) {
    MoveTo $x1 $y1; Down; Walk $x1 $y1 $x2 $y2 20; Up
}
function Find-Wins([string]$title) {
    $found = New-Object System.Collections.ArrayList
    $cb = [CF+EnumProc] {
        param($h, $l)
        $t = New-Object System.Text.StringBuilder 256
        [void][CF]::GetWindowText($h, $t, 256)
        if ($t.ToString() -eq $title) { [void]$found.Add($h) }
        return $true
    }
    [void][CF]::EnumWindows($cb, [IntPtr]::Zero)
    return $found.ToArray()
}
function Find-Kids([IntPtr]$parent, [string]$title) {
    $found = New-Object System.Collections.ArrayList
    $cb = [CF+EnumProc] {
        param($h, $l)
        $t = New-Object System.Text.StringBuilder 256
        [void][CF]::GetWindowText($h, $t, 256)
        if ($t.ToString() -eq $title -and [CF]::IsWindowVisible($h)) { [void]$found.Add($h) }
        return $true
    }
    [void][CF]::EnumChildWindows($parent, $cb, [IntPtr]::Zero)
    return $found.ToArray()
}
function Rect-Of([IntPtr]$h) {
    $r = New-Object CF+RECT
    [void][CF]::GetWindowRect($h, [ref]$r)
    return $r
}
function Same-Rect($a, $b) {
    return ($a.left -eq $b.left -and $a.top -eq $b.top -and
            $a.right -eq $b.right -and $a.bottom -eq $b.bottom)
}
function IsRed($c) { return ($c.R -gt 190 -and $c.G -lt 120 -and $c.B -lt 130) }
# loupe::kCross is (77,202,250), and nothing else on screen is that blue.
function IsCyan($c) {
    return ([Math]::Abs($c.R - 77) -le 40 -and [Math]::Abs($c.G - 202) -le 40 -and
            [Math]::Abs($c.B - 250) -le 25)
}
function CyanCount($bmp, [int]$x0, [int]$y0, [int]$x1, [int]$y1) {
    $n = 0
    for ($y = $y0; $y -le $y1; $y++) {
        for ($x = $x0; $x -le $x1; $x++) { if (IsCyan ($bmp.GetPixel($x, $y))) { $n++ } }
    }
    return $n
}
function In-Bars([int]$x, [int]$y, $bars) {
    foreach ($b2 in $bars) {
        if ($x -ge $b2.left -and $x -lt $b2.right -and
            $y -ge $b2.top -and $y -lt $b2.bottom) { return $true }
    }
    return $false
}
function Ink-Box($bmp, [int]$x0, [int]$y0, [int]$x1, [int]$y1, $skip = @()) {
    $l = -1; $t = -1; $r = -1; $b = -1; $n = 0
    for ($y = $y0; $y -le $y1; $y++) {
        for ($x = $x0; $x -le $x1; $x++) {
            if (In-Bars $x $y $skip) { continue }
            if (-not (IsRed ($bmp.GetPixel($x, $y)))) { continue }
            $n++
            if ($l -lt 0 -or $x -lt $l) { $l = $x }
            if ($x -gt $r) { $r = $x }
            if ($t -lt 0) { $t = $y }
            $b = $y
        }
    }
    if ($l -lt 0) { return $null }
    return @{ l = $l; t = $t; r = $r; b = $b; n = $n }
}

# The click lands mid-screen, clear of the toolbar, which sits at the bottom of
# the full-screen region. The loupe card hangs 30px below-right of the cursor and
# is 117x146.
$at = @(1900, 1000)
# Parenthesised: inside @() the comma binds tighter than +, so "$cx + 116" there
# would become two elements rather than one.
$cx = $at[0] + 30
$cy = $at[1] + 30
$card = @($cx, $cy, ($cx + 116), ($cy + 145))
$box = @(1000, 700, 1400, 900)
$fail = @()

MoveTo 3000 1900
Start-Sleep -Milliseconds 400
Get-Process winshot -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 600
$proc = Start-Process -FilePath 'D:\Project\winshot\x64\Debug\winshot.exe' -PassThru
Start-Sleep -Seconds 2

$sink = @(Find-Wins 'WinShotSink')
if ($sink.Count -eq 0) { 'FAIL: no sink window'; exit 1 }
[void][CF]::PostMessage($sink[0], 0x8002, [IntPtr]::Zero, [IntPtr]::Zero)
Start-Sleep -Seconds 2
$ov = @(Find-Wins 'WinShotOverlay')
if ($ov.Count -eq 0) { 'FAIL: no overlay window'; exit 1 }
$t = @(Find-Kids $ov[0] 'WinShotToolbar')
if ($t.Count -eq 0) { 'FAIL: no toolbar'; exit 1 }

# --- the magnifier is up while the whole screen is still unpicked ------------
MoveTo $at[0] $at[1]
$a = Grab 'D:\Project\winshot\obj\click_full_before.png'
$cyan0 = CyanCount $a $card[0] $card[1] $card[2] $card[3]
$a.Dispose()
$tr0 = Rect-Of $t[0]
"before the click: loupe crosshair $cyan0 cyan px in $($card[2]-$card[0]+1)x$($card[3]-$card[1]+1), toolbar at $($tr0.left),$($tr0.top)"
if ($cyan0 -lt 300) { $fail += "the magnifier card was not up before the click (crosshair=$cyan0)" }

# --- one click on the dimmed background --------------------------------------
Down; Up
$b = Grab 'D:\Project\winshot\obj\click_full_after.png'
$cyan1 = CyanCount $b $card[0] $card[1] $card[2] $card[3]
$b.Dispose()
$tr1 = Rect-Of $t[0]
"after the click:  loupe crosshair $cyan1 cyan px, toolbar at $($tr1.left),$($tr1.top)"
if ($cyan1 -gt 40) { $fail += "the magnifier is still up after the click (crosshair=$cyan1): the region was not picked" }
if (-not (Same-Rect $tr0 $tr1)) {
    $fail += "the toolbar moved from $($tr0.left),$($tr0.top) to $($tr1.left),$($tr1.top): the region is no longer the whole screen"
}

# --- the next press draws, instead of starting the gesture over --------------
# Slot 1 is the ellipse tool; slots 0..6 are plain cells before the first
# separator, so the pitch maths that slot 0 uses holds here too.
$s = ($tr1.bottom - $tr1.top) / 32.0
$cell = [int][Math]::Round(27 * $s); $pad = [int][Math]::Round(4 * $s)
$p = @(($tr1.left + $pad + [int]($cell / 2) + $cell), [int](($tr1.top + $tr1.bottom) / 2))
MoveTo $p[0] $p[1]; Down; Up
$pb = @(Find-Kids $ov[0] 'WinShotPropBar')
$bars = @()
if ($pb.Count) { $bars = @(Rect-Of $pb[0]) }
$bars += @(Rect-Of $t[0])

Drag $box[0] $box[1] $box[2] $box[3]
$c = Grab 'D:\Project\winshot\obj\click_full_ellipse.png'
$ink = Ink-Box $c 950 650 1450 950 $bars
$c.Dispose()
if (-not $ink) {
    $fail += 'the press after the click drew nothing: it started a new region instead'
} else {
    "ellipse ink: $($ink.l),$($ink.t) .. $($ink.r),$($ink.b) ($($ink.n) red px)"
    "  drag box:  $box"
    # An ellipse touches its box at the four extremes; the stroke reaches half its
    # width past them.
    # Hashtables, not nested arrays: PowerShell flattens the latter into one list.
    foreach ($d in @(@{ k = 'l'; i = 0 }, @{ k = 't'; i = 1 },
                     @{ k = 'r'; i = 2 }, @{ k = 'b'; i = 3 })) {
        $want = $box[$d.i]
        $got = $ink[$d.k]
        if ([Math]::Abs($got - $want) -gt 12) {
            $fail += "the ellipse's $($d.k) edge is at $got, want $want (the drag box)"
        }
    }
    if ($ink.n -lt 1000) { $fail += "the ellipse ink is thin ($($ink.n))" }
}

[void][System.Windows.Forms.SendKeys]::SendWait('{ESC}')
Start-Sleep -Milliseconds 400
if (-not $proc.HasExited) { $proc.Kill() }
if ($fail.Count) { "FAILURES: $($fail.Count)"; $fail | ForEach-Object { "  $_" }; exit 1 }
'PASS'
