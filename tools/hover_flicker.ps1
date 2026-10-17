# Hovering from toolbar button to button used to repaint the whole 3840x2160
# client, because showing or withdrawing a tooltip card invalidated the overlay
# with a null rect. The user sees that as the selection frame and the dim ground
# flashing together. So: park the pointer on each button in turn and sample the
# dim ground, the frame edge and the hole many times over the hover, including
# across the moment the tooltip appears. Any spread at a fixed point is a flash.
Add-Type -AssemblyName System.Drawing, System.Windows.Forms
Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class HF {
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

function MoveTo([int]$x, [int]$y) {
    [System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point($x, $y)
    Start-Sleep -Milliseconds 60
}
function Down { [void][HF]::mouse_event($LEFTDOWN, 0, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 150 }
function Up { [void][HF]::mouse_event($LEFTUP, 0, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 300 }
function Find-Wins([string]$title) {
    $found = New-Object System.Collections.ArrayList
    $cb = [HF+EnumProc] {
        param($h, $l)
        $t = New-Object System.Text.StringBuilder 256
        [void][HF]::GetWindowText($h, $t, 256)
        if ($t.ToString() -eq $title) { [void]$found.Add($h) }
        return $true
    }
    [void][HF]::EnumWindows($cb, [IntPtr]::Zero)
    return $found.ToArray()
}
function Rect-Of([IntPtr]$h) {
    $r = New-Object HF+RECT
    [void][HF]::GetWindowRect($h, [ref]$r)
    return $r
}
# The three fixed points, sampled from a full-screen grab.
function Sample($bmp) {
    return @(
        $bmp.GetPixel(400, 400),      # dimmed ground outside the selection
        $bmp.GetPixel(799, 825),      # the frame's left edge
        $bmp.GetPixel(1150, 825)     # inside the hole
    )
}
function GrabPoints() {
    $b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    $bmp = New-Object System.Drawing.Bitmap $b.Width, $b.Height
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen($b.Location, [System.Drawing.Point]::Empty, $bmp.Size)
    $p = Sample $bmp
    $g.Dispose(); $bmp.Dispose()
    return $p
}

$fail = @()
MoveTo 3000 1900
Start-Sleep -Milliseconds 400
Get-Process winshot -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 600
# A full-window repaint leaves the same settled pixels as a partial one, so the
# colour samples above cannot see the old behaviour on their own. The paint log
# says how much of the client each repaint actually covered.
Remove-Item 'D:\Project\winshot\obj\paint.log' -ErrorAction SilentlyContinue
$env:WINSHOT_PAINTLOG = '1'
$proc = Start-Process -FilePath 'D:\Project\winshot\x64\Debug\winshot.exe' -PassThru
Start-Sleep -Seconds 2

$sink = @(Find-Wins 'WinShotSink')
if ($sink.Count -eq 0) { 'FAIL: no sink window'; exit 1 }
[void][HF]::PostMessage($sink[0], 0x8002, [IntPtr]::Zero, [IntPtr]::Zero)
Start-Sleep -Seconds 2

MoveTo 800 600
Down
foreach ($i in 1..8) { MoveTo (800 + $i * 87) (600 + $i * 56) }
Start-Sleep -Milliseconds 200
Up
Start-Sleep -Milliseconds 400

$ov = @(Find-Wins 'WinShotOverlay')
if ($ov.Count -eq 0) { 'FAIL: no overlay window'; exit 1 }
$kids = New-Object System.Collections.ArrayList
$cb2 = [HF+EnumProc] {
    param($h, $l)
    $t = New-Object System.Text.StringBuilder 256
    [void][HF]::GetWindowText($h, $t, 256)
    if ($t.ToString() -eq 'WinShotToolbar') { [void]$kids.Add($h) }
    return $true
}
[void][HF]::EnumChildWindows($ov[0], $cb2, [IntPtr]::Zero)
if ($kids.Count -eq 0) { 'FAIL: no toolbar window under the overlay'; exit 1 }
$tr = Rect-Of $kids[0]
$scale = ($tr.bottom - $tr.top) / 32.0
$cell = [int][Math]::Round(27 * $scale)
$pad = [int][Math]::Round(4 * $scale)
$cy = [int](($tr.top + $tr.bottom) / 2)

# A baseline with the pointer well away from the bars.
MoveTo 2400 1700
Start-Sleep -Milliseconds 500
$base = GrabPoints
$names = @('dim@400,400', 'frame@799,825', 'hole@1150,825')
'baseline: ' + ((0..2 | ForEach-Object { "$($names[$_])=$($base[$_].R),$($base[$_].G),$($base[$_].B)" }) -join '  ')

# Where the log stands before the sweep, so the judgement below reads only the
# hovers. The app truncates the log on its first paint and flushes every line,
# so this is a real offset; the summon and the selection drag before it each
# legitimately repaint the whole client.
$skip = @(Get-Content 'D:\Project\winshot\obj\paint.log' -ErrorAction SilentlyContinue).Count
"paints logged before the sweep: $skip"

# Sweep the pointer across every slot, sampling through the tooltip delay.
$spread = @(0, 0, 0)
for ($slot = 0; $slot -le 14; $slot++) {
    $x = $tr.left + $pad + $slot * $cell + [int]($cell / 2)
    MoveTo $x $cy
    for ($k = 0; $k -lt 9; $k++) {
        $p = GrabPoints
        for ($i = 0; $i -lt 3; $i++) {
            foreach ($ch in @('R', 'G', 'B')) {
                $d = [Math]::Abs($p[$i].$ch - $base[$i].$ch)
                if ($d -gt $spread[$i]) { $spread[$i] = $d }
            }
        }
        Start-Sleep -Milliseconds 40
    }
}
"worst spread per point across the sweep: " + ((0..2 | ForEach-Object { "$($names[$_])=$($spread[$_])" }) -join '  ')

# Paints during the sweep, from the app's own stamps: duration in 100ns ticks,
# then the update region's width and height. The app keeps the log open, so it
# has to be read after the process is gone.
if (-not $proc.HasExited) { $proc.Kill(); Start-Sleep -Milliseconds 300 }
if (-not (Test-Path 'D:\Project\winshot\obj\paint.log')) { 'FAIL: no paint.log'; exit 1 }
$rows = @(Get-Content 'D:\Project\winshot\obj\paint.log' |
    Select-Object -Skip $skip | ForEach-Object {
    $f = $_.Split(' ')
    if ($f.Count -lt 3) { return }
    [pscustomobject]@{ ms = [double]$f[0] / 10000.0; area = [double]$f[1] * [double]$f[2] }
})
# Only the hovers are left here. A tooltip card dirties a box a few tens of
# thousands of pixels wide, and if every hover went back to the whole client the
# median would be 8.3M.
$tail = @($rows | Select-Object -Last 40)
$areas = @($tail | ForEach-Object { $_.area } | Sort-Object)
$med = $areas[[int]($areas.Count / 2)]
$full = @($tail | Where-Object { $_.area -ge 8000000 }).Count
"paints during the sweep: $($tail.Count)  median repaint area: $([Math]::Round($med / 1000))k px  whole-client paints: $full  worst paint: $([Math]::Round(($tail | Measure-Object -Maximum -Property ms).Maximum, 1)) ms"
if ($med -gt 200000) {
    $fail += "a median repaint of $([Math]::Round($med / 1000))k px across the toolbar sweep: the tooltip card is dirtying far more than its own box"
}
for ($i = 0; $i -lt 3; $i++) {
    if ($spread[$i] -gt 6) {
        $fail += "$($names[$i]) moved by $($spread[$i]) while the pointer crossed the toolbar (baseline $($base[$i].R),$($base[$i].G),$($base[$i].B))"
    }
}

if (-not $proc.HasExited) { $proc.Kill() }
if ($fail.Count) { "FAILURES: $($fail.Count)"; $fail | ForEach-Object { "  $_" }; exit 1 }
'PASS'
