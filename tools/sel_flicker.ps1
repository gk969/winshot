# Two flickers the colour samples so far have missed.
#
# One: clicking to select a drawn shape, and clicking again, flashes the ground.
# The worst band is the one level with the selection's height, because there the
# dim runs the whole width of the screen on both sides of it.
# Two: dragging the selection's size and position flashes its light-blue frame
# and the dimmed ground with it.
#
# The dim is black at alpha 153 over the still, so a dimmed 10 reads 4 and an
# undimmed 10 reads 25 — a pixel that loses its dim jumps by more than any
# antialiasing edge can. That makes the ground easy to test: every point on a
# scanline far from the gesture must hold the colour it had before.
#
# A single sample per step can miss a frame that is wrong and then right again,
# and the frame that flashes is up and gone inside the settle a click waits out,
# so the gestures put the pointer down and grab at once, back to back.
Add-Type -AssemblyName System.Drawing, System.Windows.Forms
$src = @"
using System;
using System.Text;
using System.Runtime.InteropServices;
using System.Drawing;
using System.Drawing.Imaging;
public static class SF {
    public delegate bool EnumProc(IntPtr h, IntPtr l);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
    [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr p, EnumProc cb, IntPtr l);
    [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint msg, IntPtr w, IntPtr l);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint dx, uint dy, uint d, UIntPtr e);
    [DllImport("user32.dll")] public static extern bool MoveWindow(IntPtr h, int x, int y, int w, int ht, bool repaint);
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int left, top, right, bottom; }

    // One row as BGR packed into ints. A single-row lock is DWORD aligned per
    // row already, so the stride is width*4 and the copy needs no padding math.
    static int[] Row(Bitmap b, int y) {
        BitmapData d = b.LockBits(new Rectangle(0, y, b.Width, 1),
            ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
        int[] px = new int[b.Width];
        Marshal.Copy(d.Scan0, px, 0, px.Length);
        b.UnlockBits(d);
        return px;
    }

    // {differing pixels, leftmost, rightmost} on one row, any channel over tol.
    public static int[] RowDiff(Bitmap a, Bitmap b, int y, int tol) {
        int[] ra = Row(a, y), rb = Row(b, y);
        int n = 0, lo = int.MaxValue, hi = -1;
        for (int x = 0; x < ra.Length; x++) {
            int p = ra[x], q = rb[x];
            if (Math.Abs((p & 255) - (q & 255)) > tol
                || Math.Abs(((p >> 8) & 255) - ((q >> 8) & 255)) > tol
                || Math.Abs(((p >> 16) & 255) - ((q >> 16) & 255)) > tol) {
                n++;
                if (x < lo) lo = x;
                if (x > hi) hi = x;
            }
        }
        if (hi < 0) { lo = 0; }
        return new int[] { n, lo, hi };
    }
}
"@
Add-Type -Language CSharp -ReferencedAssemblies @(
    'System', 'System.Core', 'System.Drawing', 'Microsoft.CSharp'
) -TypeDefinition $src

$LEFTDOWN = 0x0002; $LEFTUP = 0x0004
$sel = @(700, 550, 1700, 1250)
$scanY = 900
# Across the whole screen width at the selection's height: dimmed ground on both
# sides, undimmed still in between, and a point either side of each edge.
$xs = @(60, 300, 540, 690, 705, 1200, 1695, 1710, 1900, 2400, 3000, 3500, 3780)
# The ones far enough out to stay dimmed while the selection moves or shrinks.
$fars = @(60, 300, 540, 2400, 3000, 3500, 3780)
# Rows to measure when a grab is wrong: above, level with, and below the
# selection. Which ones move says whether the fault is one dim strip or all of
# them, and that is what separates a stale blend from a skipped DrawDim.
$rows = @(300, 900, 1600)
# Inside notepad's client once it has been moved below the selection.
$npPt = @(2350, 1600)
$fail = @()
$report = 0

function MoveTo([int]$x, [int]$y) { MoveNow $x $y; Start-Sleep -Milliseconds 90 }
function MoveNow([int]$x, [int]$y) {
    [System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point($x, $y)
}
function Down { DownNow; Start-Sleep -Milliseconds 150 }
function Up { UpNow; Start-Sleep -Milliseconds 350 }
function DownNow { [void][SF]::mouse_event($LEFTDOWN, 0, 0, 0, [UIntPtr]::Zero) }
function UpNow { [void][SF]::mouse_event($LEFTUP, 0, 0, 0, [UIntPtr]::Zero) }
function Click([int]$x, [int]$y) { MoveTo $x $y; Down; Up }
function Find-Wins([string]$title) {
    $found = New-Object System.Collections.ArrayList
    $cb = [SF+EnumProc] {
        param($h, $l)
        $t = New-Object System.Text.StringBuilder 256
        [void][SF]::GetWindowText($h, $t, 256)
        if ($t.ToString() -eq $title) { [void]$found.Add($h) }
        return $true
    }
    [void][SF]::EnumWindows($cb, [IntPtr]::Zero)
    return $found.ToArray()
}
function Grab {
    $b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    $bmp = New-Object System.Drawing.Bitmap $b.Width, $b.Height
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen($b.Location, [System.Drawing.Point]::Empty, $bmp.Size)
    $g.Dispose()
    return ,$bmp
}
# The scanline as one triple per $xs entry.
function Row-Of($bmp) {
    $o = New-Object System.Collections.ArrayList
    foreach ($x in $xs) {
        $c = $bmp.GetPixel($x, $scanY)
        [void]$o.Add(@($c.R, $c.G, $c.B))
    }
    return ,$o
}
# What a wrong grab looks like: how far the change runs along the line, and
# whether the rows above and below the selection carry it too.
function Explain([string]$when, $bmp) {
    if ($script:report -ge 3) { return }
    $script:report++
    $bmp.Save("D:\Project\winshot\obj\sf_$($when -replace '[^A-Za-z0-9]', '_').png")
    # Half a paint and a missing overlay both read as "the dim went away", so
    # tell them apart: notepad moved after the still was taken, so its white
    # client is on the live desktop and nowhere in the still. White here means
    # the overlay was absent from the frame; dark means it painted and the
    # frame it presented stopped short of the dim.
    $c = $bmp.GetPixel($npPt[0], $npPt[1])
    $b = $script:baseBmp.GetPixel($npPt[0], $npPt[1])
    "    $when  notepad point ($($npPt[0]),$($npPt[1])) : base $($b.R),$($b.G),$($b.B) -> flash $($c.R),$($c.G),$($c.B)"
    foreach ($y in $rows) {
        $d = [SF]::RowDiff($script:baseBmp, $bmp, $y, 6)
        "    $when  y=$y : $($d[0]) px, x $($d[1])..$($d[2])"
    }
}
# Back-to-back grabs: each costs about 15ms of CopyFromScreen, so six cover the
# hundred milliseconds a click takes to land and the frames after it. `only`
# narrows the point check to what must not change for a known reason, and
# `irows` are whole rows that hold their dim throughout the gesture — checking
# a row end to end is what catches a flash that misses the sampled points.
function Burst([string]$when, $base, [int]$times, $only, $irows) {
    $list = if ($only) { $only } else { $xs }
    for ($p = 1; $p -le $times; $p++) {
        $s = Grab
        $v = Row-Of $s
        $bad = $null
        foreach ($x in $list) {
            $j = [Array]::IndexOf($xs, $x)
            for ($ch = 0; $ch -lt 3; $ch++) {
                if ([Math]::Abs($v[$j][$ch] - $base[$j][$ch]) -gt 6) {
                    $bad = "x=$x channel $ch moved $([Math]::Abs($v[$j][$ch] - $base[$j][$ch])) ($($base[$j][$ch]) -> $($v[$j][$ch]))"
                    break
                }
            }
            if ($bad) { break }
        }
        if (-not $bad) {
            foreach ($y in $irows) {
                $d = [SF]::RowDiff($script:baseBmp, $s, $y, 6)
                if ($d[0] -gt 0) {
                    $bad = "y=$y : $($d[0]) px changed, x $($d[1])..$($d[2])"
                    break
                }
            }
        }
        if ($bad) {
            $script:fail += "$when grab $p : $bad"
            Explain $when $s
        }
        $s.Dispose()
        if ($bad) { return }
    }
}

# Notepad has to be on screen before the still is taken, so that the still and
# the live desktop differ once it is moved.
Get-Process notepad -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 300
$np = Start-Process "$env:SystemRoot\System32\notepad.exe" -PassThru
Start-Sleep -Milliseconds 1200
# The handle has to come from a fresh process object; the one Start-Process
# handed back was read before notepad had a window and never refreshes.
$npH = (Get-Process -Id $np.Id).MainWindowHandle
if (-not $npH) { 'FAIL: notepad has no window'; exit 1 }
[void][SF]::MoveWindow($npH, 2000, 300, 700, 500, $true)
Start-Sleep -Milliseconds 600

Get-Process winshot -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 600
$proc = Start-Process -FilePath 'D:\Project\winshot\x64\Debug\winshot.exe' -PassThru
Start-Sleep -Seconds 2
$sink = @(Find-Wins 'WinShotSink')
if ($sink.Count -eq 0) { 'FAIL: no sink window'; exit 1 }
[void][SF]::PostMessage($sink[0], 0x8002, [IntPtr]::Zero, [IntPtr]::Zero)
Start-Sleep -Seconds 2

MoveTo $sel[0] $sel[1]
Down
MoveTo $sel[2] $sel[3]
Up

$ov = @(Find-Wins 'WinShotOverlay')
if ($ov.Count -eq 0) { 'FAIL: no overlay window'; exit 1 }
$kids = New-Object System.Collections.ArrayList
$cb2 = [SF+EnumProc] {
    param($h, $l)
    $t = New-Object System.Text.StringBuilder 256
    [void][SF]::GetWindowText($h, $t, 256)
    if ($t.ToString() -eq 'WinShotToolbar') { [void]$kids.Add($h) }
    return $true
}
[void][SF]::EnumChildWindows($ov[0], $cb2, [IntPtr]::Zero)
if ($kids.Count -eq 0) { 'FAIL: no toolbar window under the overlay'; exit 1 }
$tr = New-Object SF+RECT
[void][SF]::GetWindowRect($kids[0], [ref]$tr)
$scale = ($tr.bottom - $tr.top) / 32.0
$cell = [int][Math]::Round(27 * $scale)
$pad = [int][Math]::Round(4 * $scale)
$cy = [int](($tr.top + $tr.bottom) / 2)

# A rect well clear of the scanline, so the line only ever carries ground.
Click ([int]($tr.left + $pad + $cell / 2)) $cy
MoveTo 820 640
Down
MoveTo 1050 800
Up
Click ([int]($tr.left + $pad + $cell / 2)) $cy

MoveTo 2400 1700
Start-Sleep -Milliseconds 500
$script:baseBmp = Grab
$base = Row-Of $script:baseBmp
Burst 'baseline' $base 2 $null $rows
'baseline: ' + (($base | ForEach-Object { "$($_[0]),$($_[1]),$($_[2])" }) -join ' ')

# Move it into the bottom dim strip. The overlay still shows the old desktop
# there, so nothing on screen changes; only a frame that lets the live desktop
# through reveals the move.
[void][SF]::MoveWindow($npH, 2000, 1400, 700, 500, $true)
Start-Sleep -Milliseconds 600

# --- clicking a shape to select it, and clicking away ------------------------
# Nothing moves during a click, so every row here holds its dim.
for ($round = 1; $round -le 3; $round++) {
    MoveNow 935 640
    DownNow
    Burst "select r$round down" $base 6 $null $rows
    UpNow
    Burst "select r$round up" $base 6 $null $rows
    Start-Sleep -Milliseconds 250

    MoveNow 1550 1150
    DownNow
    Burst "away r$round down" $base 6 $null $rows
    UpNow
    Burst "away r$round up" $base 6 $null $rows
    Start-Sleep -Milliseconds 250
}

# --- dragging the selection's size and position ------------------------------
# The selection itself moves, so the ground beside its edges is meant to change;
# only points and rows that stay outside it are checked. The resize runs first
# because it starts on the corner the selection still has, and each gesture ends
# somewhere the next one knows about.
#
# The resize takes the bottom-right corner from (1700,1250) to (1140,970); the
# move then shifts the result by (266,168). Across all of that y=300 stays above
# the top edge, y=1600 below the bottom, x=540 left of the left edge and the
# right-hand points right of the right one, so all of them are dimmed the whole
# time and must not move at all. y=900 crosses the selection, so it is checked
# only at the points that stay outside it.
function Drag-Sel([string]$what, [int]$x0, [int]$y0, [int]$dx, [int]$dy) {
    MoveNow $x0 $y0
    DownNow
    for ($i = 1; $i -le 14; $i++) {
        MoveNow ($x0 + $i * $dx) ($y0 + $i * $dy)
        Burst "$what step $i" $base 6 $fars @(300, 1600)
    }
    UpNow
    Burst "$what released" $base 6 $fars @(300, 1600)
    Start-Sleep -Milliseconds 250
}
Drag-Sel 'size sel' 1700 1250 -40 -20
Drag-Sel 'move sel' 900 760 19 12

if (-not $proc.HasExited) { $proc.Kill() }
if ($np -and -not $np.HasExited) { $np.Kill() }
if ($fail.Count) { "FAILURES: $($fail.Count)"; $fail | Select-Object -First 12 | ForEach-Object { "  $_" }; exit 1 }
'PASS'
