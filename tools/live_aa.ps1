# A shape still under the button is anti-aliased against whatever is already on
# the surface it is drawn onto, and it used to be drawn onto the chrome buffer --
# a DIB cleared to transparent black. GDI+ resolves an edge against the
# destination colour and writes the result premultiplied, so a pixel at coverage
# a came out as ink*a*a instead of ink*a: the colour pulled toward black and the
# alpha multiplied in a second time. That is darker than the ground beside it,
# so a dragged arrow or ellipse carried a dark fringe
# the committed one never had -- DrawBase blends over the still.
#
# The witness is the difference between the two frames of one drag. Call the still
# S, the ink I and the coverage a. Drawn onto the assembled frame the live pixel is
# I*a + S*(1-a) and the committed one is the same, so the two frames have to match
# pixel for pixel. Drawn onto the transparent buffer it is I*a*a + S*(1-a), darker
# than the committed pixel at every coverage below 1 -- about -10 at a=0.2 -- so the
# sign of the difference is the whole test: no pixel in the shape's box may fall
# more than 6 below the committed frame.
#
# The second thing this used to watch for, a live-brighter-than-done pixel in a
# 30..120 band, only existed because kDim was blended over the committed ink and not
# over the live one. A tool can only be armed once a region is picked, and a picked
# region is never dimmed, so that term left along with the dim. What keeps the drag
# from being vacuous now is that both frames have to carry the same ink.
Add-Type -AssemblyName System.Drawing, System.Windows.Forms
Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class LA {
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
# Absolute mouse_event rather than Cursor.Position: the latter stops moving
# without error once Windows starts flagging the script's process "(未响应)".
function MoveTo([int]$x, [int]$y) {
    [void][LA]::mouse_event(0x8001, [uint32][int][Math]::Round(65535 * $x / 3839),
                            [uint32][int][Math]::Round(65535 * $y / 2159), 0,
                            [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 90
}
function Down { [void][LA]::mouse_event($LEFTDOWN, 0, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 150 }
function Up { [void][LA]::mouse_event($LEFTUP, 0, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 350 }
function Walk([int]$x1, [int]$y1, [int]$x2, [int]$y2, [int]$steps) {
    for ($i = 1; $i -le $steps; $i++) {
        MoveTo ([int]($x1 + ($x2-$x1) * $i / $steps)) ([int]($y1 + ($y2-$y1) * $i / $steps))
    }
}
function Find-Wins([string]$title) {
    $found = New-Object System.Collections.ArrayList
    $cb = [LA+EnumProc] {
        param($h, $l)
        $t = New-Object System.Text.StringBuilder 256
        [void][LA]::GetWindowText($h, $t, 256)
        if ($t.ToString() -eq $title) { [void]$found.Add($h) }
        return $true
    }
    [void][LA]::EnumWindows($cb, [IntPtr]::Zero)
    return $found.ToArray()
}
function Find-Kids([IntPtr]$parent, [string]$title) {
    $found = New-Object System.Collections.ArrayList
    $cb = [LA+EnumProc] {
        param($h, $l)
        $t = New-Object System.Text.StringBuilder 256
        [void][LA]::GetWindowText($h, $t, 256)
        if ($t.ToString() -eq $title -and [LA]::IsWindowVisible($h)) { [void]$found.Add($h) }
        return $true
    }
    [void][LA]::EnumChildWindows($parent, $cb, [IntPtr]::Zero)
    return $found.ToArray()
}
function Rect-Of([IntPtr]$h) {
    $r = New-Object LA+RECT
    [void][LA]::GetWindowRect($h, [ref]$r)
    return $r
}
$ov = $null
# Toolbar slots 0..6 are plain cells before the first separator: rect, ellipse,
# arrow, pen, mosaic, text, badge.
function Slot([int]$i) {
    $t = @(Find-Kids $ov[0] 'WinShotToolbar')
    if ($t.Count -eq 0) { return $null }
    $tr = Rect-Of $t[0]
    $s = ($tr.bottom - $tr.top) / 32.0
    $cell = [int][Math]::Round(27 * $s); $pad = [int][Math]::Round(4 * $s)
    return @(($tr.left + $pad + [int]($cell / 2) + $i * $cell),
             [int](($tr.top + $tr.bottom) / 2))
}
# live - done over the shape's box. Only the red byte is read: the ink is the
# default red, and the shape's own alpha ramp is what is under test, not the hue.
function Diff-Frames($live, $done, [int]$x0, [int]$y0, [int]$x1, [int]$y1) {
    $dark = 0; $min = 999; $max = -999
    for ($y = $y0; $y -le $y1; $y++) {
        for ($x = $x0; $x -le $x1; $x++) {
            $d = $live.GetPixel($x, $y).R - $done.GetPixel($x, $y).R
            if ($d -lt $min) { $min = $d }
            if ($d -gt $max) { $max = $d }
            if ($d -le -6) { $dark++ }
        }
    }
    return @{ dark = $dark; min = $min; max = $max }
}
# tb::kPalette[0] is (247,56,64) and, with the region picked, the ink is drawn
# undimmed, so the committed shape is that red exactly. Nothing else the script
# drags over is.
function Ink-Count($bmp, [int]$x0, [int]$y0, [int]$x1, [int]$y1) {
    $n = 0
    for ($y = $y0; $y -le $y1; $y++) {
        for ($x = $x0; $x -le $x1; $x++) {
            $c = $bmp.GetPixel($x, $y)
            if ($c.R -gt 215 -and $c.G -lt 100 -and $c.B -lt 115) { $n++ }
        }
    }
    return $n
}
# One drag, grabbed once with the button still down and once after the release.
function Measure-Drag([string]$what, [int]$x1, [int]$y1, [int]$x2, [int]$y2,
                      [int]$pad) {
    MoveTo $x1 $y1
    Down
    Walk $x1 $y1 $x2 $y2 20
    # The last move only queues a paint; give it time to land before grabbing.
    Start-Sleep -Milliseconds 250
    $live = Grab ("D:\Project\winshot\obj\la_{0}_live.png" -f $what)
    Up
    $done = Grab ("D:\Project\winshot\obj\la_{0}_done.png" -f $what)
    $r = Diff-Frames $live $done ($x1 - $pad) ($y1 - $pad) ($x2 + $pad) ($y2 + $pad)
    # Counted before both are disposed: the difference alone cannot tell a clean
    # drag from one that drew nothing at all, and those two used to be separated by
    # the half-covered-edge count that the dim used to supply.
    $li = Ink-Count $live ($x1 - $pad) ($y1 - $pad) ($x2 + $pad) ($y2 + $pad)
    $di = Ink-Count $done ($x1 - $pad) ($y1 - $pad) ($x2 + $pad) ($y2 + $pad)
    $live.Dispose(); $done.Dispose()
    "${what}: live - done over $($x2 - $x1 + 2*$pad)x$($y2 - $y1 + 2*$pad) px: " +
        "min $($r.min), max $($r.max), $($r.dark) px at or below -6; ink $li live / $di done"
    if ($r.dark -gt 0) {
        $script:fail += "the $what still under the button has $($r.dark) px darker than the committed shape (min $($r.min)): its anti-aliasing is blending toward black"
    }
    if ($di -lt 300) {
        $script:fail += "the committed $what has only $di ink px in its box: the drag drew nothing and the test proved nothing"
    } elseif ($li -ne $di) {
        $script:fail += "the $what under the button has $li ink px against $di committed: the live drag is not drawing the shape that gets committed"
    }
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
[void][LA]::PostMessage($sink[0], 0x8002, [IntPtr]::Zero, [IntPtr]::Zero)
Start-Sleep -Seconds 2
$ov = @(Find-Wins 'WinShotOverlay')
if ($ov.Count -eq 0) { 'FAIL: no overlay window'; exit 1 }

# A region first: the bar only comes up once there is something to draw on, so
# until one is dragged out there is no tool slot to click. Deliberately large -- the
# bar then lands below y=2050, clear of both measurement boxes, and both boxes sit
# inside the region so neither drag is clipped at its edge.
MoveTo 200 200; Down; Walk 200 200 3600 2050 20; Up
Start-Sleep -Milliseconds 400

# --- the ellipse: the curved edge gives an alpha ramp on all four sides -------
$e = Slot 1
if (-not $e) { 'FAIL: no toolbar'; exit 1 }
MoveTo $e[0] $e[1]; Down; Up
Start-Sleep -Milliseconds 300
Measure-Drag 'ellipse' 1000 700 1500 950 40

# --- the arrow: the user named it first, and its tail is thin enough that the
#     fringe sat along both flanks of it ---------------------------------------
$a = Slot 2
if (-not $a) { 'FAIL: the toolbar went away'; exit 1 }
MoveTo $a[0] $a[1]; Down; Up
Start-Sleep -Milliseconds 300
Measure-Drag 'arrow' 1000 1200 1600 1500 40

[void][System.Windows.Forms.SendKeys]::SendWait('{ESC}')
Start-Sleep -Milliseconds 400
if (-not $proc.HasExited) { $proc.Kill() }
if ($fail.Count) { "FAILURES: $($fail.Count)"; $fail | ForEach-Object { "  $_" }; exit 1 }
'PASS'
