# Is a shape visible while it is still being drawn (button down, m_pending)?
# If it is not, the chrome buffer is being cleared over the selection interior by
# something that draws after the annotations, and that one fault explains both the
# missing selection marker and the shape that vanishes while it is dragged.
Add-Type -AssemblyName System.Drawing, System.Windows.Forms
Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class DP {
    public delegate bool EnumProc(IntPtr h, IntPtr l);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
    [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr p, EnumProc cb, IntPtr l);
    [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
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
function Down { [void][DP]::mouse_event($LEFTDOWN, 0, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 150 }
function Up { [void][DP]::mouse_event($LEFTUP, 0, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 300 }
function Click([int]$x, [int]$y) { MoveTo $x $y; Down; Up }
function Find-Wins([string]$title) {
    $found = New-Object System.Collections.ArrayList
    $cb = [DP+EnumProc] {
        param($h, $l)
        $t = New-Object System.Text.StringBuilder 256
        [void][DP]::GetWindowText($h, $t, 256)
        if ($t.ToString() -eq $title) { [void]$found.Add($h) }
        return $true
    }
    [void][DP]::EnumWindows($cb, [IntPtr]::Zero)
    return $found.ToArray()
}
function Rect-Of([IntPtr]$h) {
    $r = New-Object DP+RECT
    [void][DP]::GetWindowRect($h, [ref]$r)
    return $r
}
function IsRed($c) { return ($c.R -gt 190 -and $c.G -lt 120 -and $c.B -lt 130) }
function Red-Count($bmp, [int]$x0, [int]$y0, [int]$x1, [int]$y1) {
    $n = 0
    for ($y = $y0; $y -le $y1; $y++) {
        for ($x = $x0; $x -le $x1; $x++) {
            if (IsRed ($bmp.GetPixel($x, $y))) { $n++ }
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

$sink = @(Find-Wins 'WinShotSink')
if ($sink.Count -eq 0) { 'FAIL: no sink window'; exit 1 }
[void][DP]::PostMessage($sink[0], 0x8002, [IntPtr]::Zero, [IntPtr]::Zero)
Start-Sleep -Seconds 2

# A selection first.
MoveTo 800 600
Down
foreach ($i in 1..8) { MoveTo (800 + $i * 87) (600 + $i * 56) }
Start-Sleep -Milliseconds 200
Up

# Pick the rect tool off the toolbar window.
$ov = @(Find-Wins 'WinShotOverlay')
$kids = New-Object System.Collections.ArrayList
$cb2 = [DP+EnumProc] {
    param($h, $l)
    $t = New-Object System.Text.StringBuilder 256
    [void][DP]::GetWindowText($h, $t, 256)
    if ($t.ToString() -eq 'WinShotToolbar') { [void]$kids.Add($h) }
    return $true
}
[void][DP]::EnumChildWindows($ov[0], $cb2, [IntPtr]::Zero)
if ($kids.Count -eq 0) { 'FAIL: no toolbar window under the overlay'; exit 1 }
$tr = Rect-Of $kids[0]
$scale = ($tr.bottom - $tr.top) / 32.0
$cell = [int][Math]::Round(27 * $scale)
$pad = [int][Math]::Round(4 * $scale)
Click ($tr.left + $pad + [int]($cell / 2)) ([int](($tr.top + $tr.bottom) / 2))

# Draw a rect and look at it with the button still down.
MoveTo 900 700
Down
foreach ($i in 1..8) { MoveTo (900 + $i * 25) (700 + $i * 19) }
Start-Sleep -Milliseconds 350
$s = Grab 'D:\Project\winshot\obj\dp_pendrag.png'
$mid = Red-Count $s 890 690 1110 860
$s.Dispose()
Up
Start-Sleep -Milliseconds 300
$s = Grab 'D:\Project\winshot\obj\dp_pendone.png'
$up = Red-Count $s 890 690 1110 860
$s.Dispose()

"pending rect: mid-drag (button down)=$mid  after release=$up"
if ($mid -lt 0.6 * $up) { $fail += "the shape being drawn is not on screen until the button comes up ($mid px mid-drag, $up px after)" }

if (-not $proc.HasExited) { $proc.Kill() }
if ($fail.Count) { "FAILURES: $($fail.Count)"; $fail | ForEach-Object { "  $_" }; exit 1 }
'PASS'
