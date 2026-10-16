# Dragging a drawn shape has to take it with the cursor. It used to leave a copy
# sitting at the origin until the button came up, so the measure is the ink at the
# shape's old place while the button is still down: it has to be gone then, not
# only after the release.
Add-Type -AssemblyName System.Drawing, System.Windows.Forms
Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class DG {
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
function Down { [void][DG]::mouse_event($LEFTDOWN, 0, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 150 }
function Up { [void][DG]::mouse_event($LEFTUP, 0, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 300 }
function Click([int]$x, [int]$y) { MoveTo $x $y; Down; Up }
function Drag([int]$x1, [int]$y1, [int]$x2, [int]$y2) {
    MoveTo $x1 $y1
    Down
    for ($i = 1; $i -le 12; $i++) {
        MoveTo ([int]($x1 + ($x2-$x1) * $i / 12)) ([int]($y1 + ($y2-$y1) * $i / 12))
    }
    Start-Sleep -Milliseconds 150
    Up
}
function Find-Wins([string]$title) {
    $found = New-Object System.Collections.ArrayList
    $cb = [DG+EnumProc] {
        param($h, $l)
        $t = New-Object System.Text.StringBuilder 256
        [void][DG]::GetWindowText($h, $t, 256)
        if ($t.ToString() -eq $title) { [void]$found.Add($h) }
        return $true
    }
    [void][DG]::EnumWindows($cb, [IntPtr]::Zero)
    return $found.ToArray()
}
function Rect-Of([IntPtr]$h) {
    $r = New-Object DG+RECT
    [void][DG]::GetWindowRect($h, [ref]$r)
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
[void][DG]::PostMessage($sink[0], 0x8002, [IntPtr]::Zero, [IntPtr]::Zero)
Start-Sleep -Seconds 2

Drag $sel[0] $sel[1] $sel[2] $sel[3]

$ov = @(Find-Wins 'WinShotOverlay')
if ($ov.Count -eq 0) { 'FAIL: no overlay window'; exit 1 }
$kids = New-Object System.Collections.ArrayList
$cb2 = [DG+EnumProc] {
    param($h, $l)
    $t = New-Object System.Text.StringBuilder 256
    [void][DG]::GetWindowText($h, $t, 256)
    if ($t.ToString() -eq 'WinShotToolbar') { [void]$kids.Add($h) }
    return $true
}
[void][DG]::EnumChildWindows($ov[0], $cb2, [IntPtr]::Zero)
if ($kids.Count -eq 0) { 'FAIL: no toolbar window under the overlay'; exit 1 }
$tr = Rect-Of $kids[0]
$scale = ($tr.bottom - $tr.top) / 32.0
if ($scale -lt 0.5 -or $scale -gt 4) { "FAIL: implausible toolbar height"; exit 1 }
$cell = [int][Math]::Round(27 * $scale)
$pad = [int][Math]::Round(4 * $scale)
$rectX = $tr.left + $pad + [int]($cell / 2)
$rectY = [int](($tr.top + $tr.bottom) / 2)
Click $rectX $rectY

# One rect, then grab its top stroke a quarter along — a quarter along so the
# press is not on one of the edge-midpoint handles.
Drag 900 700 1100 850
$grab = @(950, 700)
Click $grab[0] $grab[1]

$old = @(880, 680, 1120, 870)
$new = @(1130, 680, 1370, 870)
$s = Grab 'D:\Project\winshot\obj\dg_selected.png'
$before = Red-Count $s $old[0] $old[1] $old[2] $old[3]
$s.Dispose()
"rect at (900,700)..(1100,850): red px in the old box=$before"
if ($before -lt 2000) { "FAIL: the rect is not there to be dragged ($before px)"; exit 1 }

# --- the drag, measured with the button still down ---------------------------
MoveTo $grab[0] $grab[1]
Down
foreach ($i in 1..10) { MoveTo ($grab[0] + $i * 25) $grab[1] }
Start-Sleep -Milliseconds 350
$s = Grab 'D:\Project\winshot\obj\dg_middrag.png'
$oldMid = Red-Count $s $old[0] $old[1] $old[2] $old[3]
$newMid = Red-Count $s $new[0] $new[1] $new[2] $new[3]
$s.Dispose()
Up

$s = Grab 'D:\Project\winshot\obj\dg_after.png'
$oldUp = Red-Count $s $old[0] $old[1] $old[2] $old[3]
$newUp = Red-Count $s $new[0] $new[1] $new[2] $new[3]
$s.Dispose()

"mid-drag (button down, shape at (1150,700)..(1350,850)): old box=$oldMid  new box=$newMid"
"after release: old box=$oldUp  new box=$newUp"
if ($newMid -lt 0.8 * $before) { $fail += "the shape did not follow the cursor mid-drag (new box $newMid of $before)" }
if ($oldMid -gt 200) { $fail += "a copy of the shape stayed at the origin while dragging ($oldMid px there, $oldUp after release)" }
if ($oldUp -gt 200) { $fail += "the shape never left the origin ($oldUp px there after release)" }

if (-not $proc.HasExited) { $proc.Kill() }
if ($fail.Count) { "FAILURES: $($fail.Count)"; $fail | ForEach-Object { "  $_" }; exit 1 }
'PASS'
