# Does 按c复制色号 put the sampled colour on the clipboard? stage6_test compares
# the copied value against a live-desktop grab, which the frozen still cannot
# match on an animating desktop, so this checks only that the copy happened and
# produced an RGB:(r,g,b) string.
Add-Type -AssemblyName System.Drawing, System.Windows.Forms
Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class W6 {
    public delegate bool EnumProc(IntPtr h, IntPtr l);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
    [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint msg, IntPtr w, IntPtr l);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, IntPtr extra);
}
"@

# Windows refuses SetForegroundWindow from a process that is not already in the
# foreground. Pressing a key lifts that lock, so a background test harness can
# still hand focus to the window under test — the same thing a real click does.
function Force-Foreground([IntPtr]$h) {
    [void][W6]::keybd_event(0x12, 0, 0, [IntPtr]::Zero)        # VK_MENU down
    [void][W6]::keybd_event(0x12, 0, 2, [IntPtr]::Zero)        # VK_MENU up
    [void][W6]::SetForegroundWindow($h)
}

function Find-Win([string]$title) {
    $list = New-Object System.Collections.ArrayList
    $cb = [W6+EnumProc] {
        param($h, $l)
        $t = New-Object System.Text.StringBuilder 256
        [void][W6]::GetWindowText($h, $t, 256)
        if ($t.ToString() -eq $title) { [void]$list.Add($h) }
        return $true
    }
    [void][W6]::EnumWindows($cb, [IntPtr]::Zero)
    return $list
}

Get-Process winshot -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 500
[System.Windows.Forms.Clipboard]::SetText('sentinel')
[System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point(2200, 1100)
Start-Sleep -Milliseconds 400

Start-Process -FilePath 'D:\Project\winshot\x64\Debug\winshot.exe'
Start-Sleep -Seconds 2
$sink = Find-Win 'WinShotSink'
if ($sink.Count -eq 0) { 'no sink window'; exit 1 }
[void][W6]::PostMessage($sink[0], 0x8002, [IntPtr]::Zero, [IntPtr]::Zero)
Start-Sleep -Seconds 2

$ov = Find-Win 'WinShotOverlay'
if ($ov.Count -eq 0) { 'no overlay window'; exit 1 }
$ovh = $ov[0]
[System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point(2200, 1100)
Start-Sleep -Milliseconds 400
Force-Foreground $ovh
Start-Sleep -Milliseconds 300
"foreground is overlay: $([W6]::GetForegroundWindow() -eq $ovh)"

[void][System.Windows.Forms.SendKeys]::SendWait('c')
Start-Sleep -Milliseconds 600
$got = ''
try { $got = [System.Windows.Forms.Clipboard]::GetText() } catch { }
"clipboard after c: '$got'"
"copy happened: $(if ($got -match '^RGB:\(\d{1,3},\d{1,3},\d{1,3}\)$') {'yes'} else {'no'})"

[System.Windows.Forms.SendKeys]::SendWait('{ESC}')
Start-Sleep -Milliseconds 400
Get-Process winshot -ErrorAction SilentlyContinue | Stop-Process -Force
