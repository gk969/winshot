# What size does the app think the selection is after arrow-key nudges? The
# clipboard image on Accept is cropped to the selection, so its dimensions are
# the model's answer, independent of how the overlay painted.
Add-Type -AssemblyName System.Drawing, System.Windows.Forms
Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class W3 {
    public delegate bool EnumProc(IntPtr h, IntPtr l);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
    [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint msg, IntPtr w, IntPtr l);
    [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint dx, uint dy, uint d, UIntPtr e);
}
"@

$LEFTDOWN = 0x0002; $LEFTUP = 0x0004

function MoveTo([int]$x, [int]$y) {
    [System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point($x, $y)
    Start-Sleep -Milliseconds 120
}
function Drag([int]$x1, [int]$y1, [int]$x2, [int]$y2) {
    MoveTo $x1 $y1
    [void][W3]::mouse_event($LEFTDOWN, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 120
    for ($i = 1; $i -le 12; $i++) {
        MoveTo ([int]($x1 + ($x2-$x1) * $i / 12)) ([int]($y1 + ($y2-$y1) * $i / 12))
    }
    Start-Sleep -Milliseconds 150
    [void][W3]::mouse_event($LEFTUP, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 300
}

Get-Process winshot -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 500
MoveTo 3000 1900
Start-Sleep -Milliseconds 400

Start-Process -FilePath 'D:\Project\winshot\x64\Debug\winshot.exe'
Start-Sleep -Seconds 2

$sink = New-Object System.Collections.ArrayList
$cb = [W3+EnumProc] {
    param($h, $l)
    $t = New-Object System.Text.StringBuilder 256
    [void][W3]::GetWindowText($h, $t, 256)
    if ($t.ToString() -eq 'WinShotSink') { [void]$sink.Add($h) }
    return $true
}
[void][W3]::EnumWindows($cb, [IntPtr]::Zero)
if ($sink.Count -eq 0) { 'no sink window'; exit 1 }
[void][W3]::PostMessage($sink[0], 0x8002, [IntPtr]::Zero, [IntPtr]::Zero)
Start-Sleep -Seconds 2

Drag 800 600 1400 1000
'created 600x400 at [800,600,1400,1000]'

for ($i = 0; $i -lt 5; $i++) { [System.Windows.Forms.SendKeys]::SendWait('{RIGHT}'); Start-Sleep -Milliseconds 150 }
for ($i = 0; $i -lt 5; $i++) { [System.Windows.Forms.SendKeys]::SendWait('+{RIGHT}'); Start-Sleep -Milliseconds 150 }
for ($i = 0; $i -lt 3; $i++) { [System.Windows.Forms.SendKeys]::SendWait('+{DOWN}'); Start-Sleep -Milliseconds 150 }
Start-Sleep -Milliseconds 500
'nudged +55 right, +30 down'

[System.Windows.Forms.SendKeys]::SendWait('{ENTER}')
Start-Sleep -Milliseconds 800
$img = $null
for ($try = 0; $try -lt 10 -and $null -eq $img; $try++) {
    $img = [System.Windows.Forms.Clipboard]::GetImage()
    if ($null -eq $img) { Start-Sleep -Milliseconds 300 }
}
if ($null -eq $img) { 'clipboard: empty' }
else { "clipboard: $($img.Width) x $($img.Height)  (want 600 x 400)" }
if ($img) { $img.Dispose() }

Get-Process winshot -ErrorAction SilentlyContinue | Stop-Process -Force
