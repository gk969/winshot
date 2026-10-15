Add-Type -AssemblyName System.Drawing, System.Windows.Forms
Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class W2 {
    public delegate bool EnumProc(IntPtr h, IntPtr l);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
    [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint msg, IntPtr w, IntPtr l);
    [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint dx, uint dy, uint d, UIntPtr e);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern IntPtr GetFocus();
    [DllImport("user32.dll")] public static extern IntPtr WindowFromPoint(POINT p);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    public struct POINT { public int x, y; public POINT(int a,int b){x=a;y=b;} }
}
"@

function TitleOf([IntPtr]$h) {
    $t = New-Object System.Text.StringBuilder 256
    [void][W2]::GetWindowText($h, $t, 256)
    return $t.ToString()
}
function FindWindows([string]$title) {
    $list = New-Object System.Collections.ArrayList
    $cb = [W2+EnumProc] {
        param($h, $l)
        $t = New-Object System.Text.StringBuilder 256
        [void][W2]::GetWindowText($h, $t, 256)
        if ($t.ToString() -eq $title) { [void]$list.Add($h) }
        return $true
    }
    [void][W2]::EnumWindows($cb, [IntPtr]::Zero)
    return $list
}

Get-Process winshot -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 500
$p = Start-Process -FilePath 'D:\Project\winshot\x64\Debug\winshot.exe' -PassThru
Start-Sleep -Seconds 2

$sink = FindWindows 'WinShotSink'
if ($sink.Count -eq 0) { "no sink window"; exit 1 }
[void][W2]::PostMessage($sink[0], 0x8002, [IntPtr]::Zero, [IntPtr]::Zero)
Start-Sleep -Seconds 2

$ov = FindWindows 'WinShotOverlay'
"overlay windows: $($ov.Count)"
"foreground after create: '$(TitleOf ([W2]::GetForegroundWindow()))'"

# A real click should activate the overlay.
[System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point(1900, 1100)
Start-Sleep -Milliseconds 200
[void][W2]::mouse_event(0x0002, 0, 0, 0, [UIntPtr]::Zero)
[void][W2]::mouse_event(0x0004, 0, 0, 0, [UIntPtr]::Zero)
Start-Sleep -Milliseconds 400
"foreground after click: '$(TitleOf ([W2]::GetForegroundWindow()))'"
"window under (1900,1100): '$(TitleOf ([W2]::WindowFromPoint((New-Object W2+POINT(1900,1100)))))'"

# One Shift+Right, then check whether the selection moved, using the frame colour
# as the marker: scan row 1100 for #1E9FD4.
function FrameRuns([int]$row) {
    $b = New-Object System.Drawing.Bitmap 3840, 2160
    $g = [System.Drawing.Graphics]::FromImage($b)
    $g.CopyFromScreen(0, 0, 0, 0, $b.Size)
    $g.Dispose()
    $runs = @()
    $start = -1
    for ($x = 0; $x -lt 3840; $x++) {
        $c = $b.GetPixel($x, $row)
        $isFrame = ([Math]::Abs($c.R-30) -lt 40 -and [Math]::Abs($c.G-159) -lt 40 -and [Math]::Abs($c.B-212) -lt 40)
        if ($isFrame -and $start -lt 0) { $start = $x }
        if (-not $isFrame -and $start -ge 0) { $runs += "$start..$($x-1)"; $start = -1 }
    }
    $b.Dispose()
    return $runs
}
"frame runs before keys (row 1100): $(FrameRuns 1100)"

[System.Windows.Forms.SendKeys]::SendWait('+{RIGHT}')
Start-Sleep -Milliseconds 600
"foreground after key: '$(TitleOf ([W2]::GetForegroundWindow()))'"
"frame runs after 1x Shift+Right (row 1100): $(FrameRuns 1100)"

for ($i = 0; $i -lt 5; $i++) { [System.Windows.Forms.SendKeys]::SendWait('+{RIGHT}'); Start-Sleep -Milliseconds 80 }
Start-Sleep -Milliseconds 600
"frame runs after 5 more Shift+Right (row 1100): $(FrameRuns 1100)"

[System.Windows.Forms.SendKeys]::SendWait('{ESC}')
Start-Sleep -Seconds 1
"overlay windows after ESC: $((FindWindows 'WinShotOverlay').Count)"
"winshot still running: $([bool](Get-Process winshot -ErrorAction SilentlyContinue))"
