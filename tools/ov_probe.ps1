Add-Type -AssemblyName System.Windows.Forms
Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class OP {
    public delegate bool EnumProc(IntPtr h, IntPtr l);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
    [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out R r);
    [DllImport("user32.dll")] public static extern IntPtr WindowFromPoint(P p);
    [DllImport("user32.dll")] public static extern IntPtr GetAncestor(IntPtr h, uint f);
    [DllImport("user32.dll")] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern IntPtr SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint dx, uint dy, uint d, UIntPtr e);
    [DllImport("user32.dll")] public static extern IntPtr SendMessageTimeout(IntPtr h, uint m, IntPtr w, IntPtr l, uint f, uint ms, out IntPtr r);
    [StructLayout(LayoutKind.Sequential)] public struct P { public int x, y; }
    [StructLayout(LayoutKind.Sequential)] public struct R { public int left, top, right, bottom; }
}
"@
function Find-Win([string]$t) {
  $f = New-Object System.Collections.ArrayList
  $cb = [OP+EnumProc] { param($h,$l)
    $s = New-Object System.Text.StringBuilder 256
    [void][OP]::GetWindowText($h,$s,256)
    if ($s.ToString() -eq $t) { [void]$f.Add($h) }
    return $true }
  [void][OP]::EnumWindows($cb,[IntPtr]::Zero)
  return $f.ToArray() }
Get-Process winshot -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 600
$env:WINSHOT_PAINTLOG = '1'
Remove-Item 'D:\Project\winshot\obj\paint.log' -ErrorAction SilentlyContinue
$p = Start-Process -FilePath 'D:\Project\winshot\x64\Debug\winshot.exe' -PassThru
Start-Sleep -Seconds 2
$sink = @(Find-Win 'WinShotSink')
"sink: $(@($sink).Count)"
[void][OP]::PostMessage($sink[0], 0x8002, [IntPtr]::Zero, [IntPtr]::Zero)
Start-Sleep -Seconds 2
$ov = @(Find-Win 'WinShotOverlay')
$ovN = @($ov).Count
"overlay windows: $ovN"
if ($ovN) {
    $h = @($ov)[0]
    $r = New-Object OP+R; [void][OP]::GetWindowRect($h, [ref]$r)
    "overlay $h visible=$([OP]::IsWindowVisible($h)) rect $($r.left),$($r.top) $($r.right-$r.left)x$($r.bottom-$r.top)"
    "foreground: $([OP]::GetForegroundWindow())  overlay=$h"
    $pt = New-Object OP+P; $pt.x = 900; $pt.y = 700
    $w = [OP]::WindowFromPoint($pt)
    $cn = New-Object System.Text.StringBuilder 256; [void][OP]::GetClassName($w,$cn,256)
    $root = [OP]::GetAncestor($w, 2)
    $rc = New-Object System.Text.StringBuilder 256; [void][OP]::GetClassName($root,$rc,256)
    "WindowFromPoint(900,700) = $w class='$($cn.ToString())' root=$root class='$($rc.ToString())'"
    [void][OP]::SetCursorPos(900,700); Start-Sleep -Milliseconds 200
    [void][OP]::mouse_event(0x0002,0,0,0,[UIntPtr]::Zero)
    Start-Sleep -Milliseconds 200
    for ($i=1; $i -le 20; $i++) {
        [void][OP]::SetCursorPos(900 + $i*40, 700 + $i*30)
        Start-Sleep -Milliseconds 12
    }
    [void][OP]::mouse_event(0x0004,0,0,0,[UIntPtr]::Zero)
    Start-Sleep -Seconds 1
    "paint.log lines after a manual drag: $(@(Get-Content 'D:\Project\winshot\obj\paint.log' -ErrorAction SilentlyContinue).Count)"
}
if (-not $p.HasExited) { $p.Kill() }
