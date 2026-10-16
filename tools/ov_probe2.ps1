Add-Type -AssemblyName System.Windows.Forms
Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class OP2 {
    public delegate bool EnumProc(IntPtr h, IntPtr l);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
    [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
    [DllImport("user32.dll")] public static extern IntPtr SendMessageTimeout(IntPtr h, uint m, IntPtr w, IntPtr l, uint f, uint ms, out IntPtr r);
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint dx, uint dy, uint d, UIntPtr e);
    [DllImport("user32.dll")] public static extern IntPtr WindowFromPoint(P p);
    [StructLayout(LayoutKind.Sequential)] public struct P { public int x, y; }
}
"@
function Find-Win([string]$t) {
  $f = New-Object System.Collections.ArrayList
  $cb = [OP2+EnumProc] { param($h,$l)
    $s = New-Object System.Text.StringBuilder 256
    [void][OP2]::GetWindowText($h,$s,256)
    if ($s.ToString() -eq $t) { [void]$f.Add($h) }
    return $true }
  [void][OP2]::EnumWindows($cb,[IntPtr]::Zero)
  return $f.ToArray() }
Get-Process winshot -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 600
$env:WINSHOT_PAINTLOG = '1'
Remove-Item 'D:\Project\winshot\obj\paint.log' -ErrorAction SilentlyContinue
$p = Start-Process -FilePath 'D:\Project\winshot\x64\Debug\winshot.exe' -PassThru
Start-Sleep -Seconds 2
$sink = @(Find-Win 'WinShotSink')
[void][OP2]::PostMessage(@($sink)[0], 0x8002, [IntPtr]::Zero, [IntPtr]::Zero)
Start-Sleep -Seconds 2
$ov = @(@(Find-Win 'WinShotOverlay')[0])
"overlay=$ov  paint.log exists=$(Test-Path 'D:\Project\winshot\obj\paint.log')  lines=$(@(Get-Content 'D:\Project\winshot\obj\paint.log' -ErrorAction SilentlyContinue).Count)"
$p.Refresh()
"process responding=$($p.Responding) title='$($p.MainWindowTitle)' handles=$($p.HandleCount)"
$r = [IntPtr]::Zero
$ok = [OP2]::SendMessageTimeout($ov, 0x0000, [IntPtr]::Zero, [IntPtr]::Zero, 0x0002, 1500, [ref]$r)
"WM_NULL round trip: ok=$ok"
# A move with the button up: the loupe path, which invalidates on its own.
[void][OP2]::SetCursorPos(1200, 800); Start-Sleep -Milliseconds 300
[void][OP2]::SetCursorPos(1240, 840); Start-Sleep -Milliseconds 300
[void][OP2]::SetCursorPos(1280, 880); Start-Sleep -Milliseconds 600
"lines after 3 plain moves: $(@(Get-Content 'D:\Project\winshot\obj\paint.log' -ErrorAction SilentlyContinue).Count)"
[void][OP2]::SetCursorPos(900,700); Start-Sleep -Milliseconds 200
[void][OP2]::mouse_event(0x0002,0,0,0,[UIntPtr]::Zero)
Start-Sleep -Milliseconds 500
"lines after left down: $(@(Get-Content 'D:\Project\winshot\obj\paint.log' -ErrorAction SilentlyContinue).Count)"
[void][OP2]::SetCursorPos(1400,1100); Start-Sleep -Milliseconds 500
"lines after a move with button down: $(@(Get-Content 'D:\Project\winshot\obj\paint.log' -ErrorAction SilentlyContinue).Count)"
[void][OP2]::mouse_event(0x0004,0,0,0,[UIntPtr]::Zero)
Start-Sleep -Milliseconds 800
"lines after left up: $(@(Get-Content 'D:\Project\winshot\obj\paint.log' -ErrorAction SilentlyContinue).Count)"
$p.Refresh(); "process responding now=$($p.Responding)"
if (-not $p.HasExited) { $p.Kill() }
