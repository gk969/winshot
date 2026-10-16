# The magnifier-and-colour-picker card is there to help choose where the 选区
# starts. Once the user has dragged one out it has done its job, so it must not
# ride along behind the cursor any more — and it must go the moment the left
# button goes down, not trail across the region being drawn.
#
# The card's readout is a solid RGB(51,51,51) block 117x62 hanging under a 117x85
# magnifier, both centred on the cursor, so counting near-51 pixels in that rect
# says whether the card is up.
Add-Type -AssemblyName System.Drawing, System.Windows.Forms
Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class LP {
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint msg, IntPtr w, IntPtr l);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
    [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, System.Text.StringBuilder s, int n);
    [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint dx, uint dy, uint d, UIntPtr e);
    public delegate bool EnumProc(IntPtr h, IntPtr l);
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
    Start-Sleep -Milliseconds 120
}
function Down { [void][LP]::mouse_event($LEFTDOWN, 0, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 150 }
function Up { [void][LP]::mouse_event($LEFTUP, 0, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 250 }
function Find-Sink() {
    $found = New-Object System.Collections.ArrayList
    $cb = [LP+EnumProc] {
        param($h, $l)
        $t = New-Object System.Text.StringBuilder 256
        [void][LP]::GetWindowText($h, $t, 256)
        if ($t.ToString() -eq 'WinShotSink') { [void]$found.Add($h) }
        return $true
    }
    [void][LP]::EnumWindows($cb, [IntPtr]::Zero)
    return $found.ToArray()
}
# Pixels of the readout's flat 51,51,51 field in the rect the card would occupy
# for a cursor at (x,y).
function Readout($bmp, [int]$x, [int]$y) {
    $n = 0
    for ($j = ($y + 42); $j -lt ($y + 104); $j++) {
        for ($i = ($x - 58); $i -lt ($x + 59); $i++) {
            $c = $bmp.GetPixel($i, $j)
            if ([Math]::Abs($c.R - 51) -le 8 -and [Math]::Abs($c.G - 51) -le 8 -and
                [Math]::Abs($c.B - 51) -le 8) { $n++ }
        }
    }
    return $n
}

$fail = @()
MoveTo 3000 1900
Start-Sleep -Milliseconds 400
Get-Process winshot -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 600
$proc = Start-Process -FilePath 'D:\Project\winshot\x64\Debug\winshot.exe' -PassThru
Start-Sleep -Seconds 2

$sink = @(Find-Sink)
if ($sink.Count -eq 0) { 'FAIL: no sink window'; exit 1 }
[void][LP]::PostMessage($sink[0], 0x8002, [IntPtr]::Zero, [IntPtr]::Zero)
Start-Sleep -Seconds 2

# --- before any drag: the card is up ----------------------------------------
# The two later spots are measured here as well, while the card is elsewhere, so
# a dark stretch of desktop under them cannot be mistaken for the card later.
$p1 = @(1900, 900)
MoveTo $p1[0] $p1[1]
Start-Sleep -Milliseconds 350
$s = Grab 'D:\Project\winshot\obj\lp_before.png'
$a = Readout $s $p1[0] $p1[1]
$base1 = Readout $s 2150 1100
$base2 = Readout $s 1500 1400
$s.Dispose()
"before the drag: card at ($($p1[0]),$($p1[1])) = $a px; bare desktop at (2150,1100) = $base1, at (1500,1400) = $base2"
if ($a -lt $base2 + 3000) { $fail += "the loupe was not up before the first drag ($a px, bare desktop there $base2)" }

# --- while the button is down: gone -----------------------------------------
Down
MoveTo 2150 1100
Start-Sleep -Milliseconds 350
$s = Grab 'D:\Project\winshot\obj\lp_dragging.png'
$b = Readout $s 2150 1100
$s.Dispose()
"mid-drag at (2150,1100): $b px (bare desktop there was $base1)"
if ($b -gt $base1 + 300) { $fail += "the loupe followed the drag ($b px, bare desktop $base1)" }
Up

# --- after the selection exists: still gone, wherever the cursor goes -------
MoveTo 1500 1400
Start-Sleep -Milliseconds 400
$s = Grab 'D:\Project\winshot\obj\lp_after.png'
$c = Readout $s 1500 1400
$s.Dispose()
"after the drag at (1500,1400): $c px (bare desktop there was $base2)"
if ($c -gt $base2 + 300) { $fail += "the loupe came back once a selection existed ($c px, bare desktop $base2)" }

if (-not $proc.HasExited) { $proc.Kill() }
if ($fail.Count) { "FAILURES: $($fail.Count)"; $fail | ForEach-Object { "  $_" }; exit 1 }
'PASS'
