Add-Type -AssemblyName System.Drawing, System.Windows.Forms
Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class CP {
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")] public static extern bool GetCursorPos(out P p);
    [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint dx, uint dy, uint d, UIntPtr e);
    [DllImport("user32.dll")] public static extern IntPtr WindowFromPoint(P p);
    [DllImport("user32.dll")] public static extern IntPtr FindWindowEx(IntPtr p, IntPtr a, string c, string t);
    [DllImport("user32.dll")] public static extern int GetClassName(IntPtr h, System.Text.StringBuilder s, int n);
    [DllImport("user32.dll")] public static extern IntPtr GetAncestor(IntPtr h, uint f);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out R r);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern int GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("user32.dll")] public static extern IntPtr SendMessageTimeout(IntPtr h, uint m, IntPtr w, IntPtr l, uint f, uint ms, out IntPtr r);
    [StructLayout(LayoutKind.Sequential)] public struct P { public int x, y; }
    [StructLayout(LayoutKind.Sequential)] public struct R { public int left, top, right, bottom; }
}
"@
function Menu-List() {
    $o = @(); $h = [CP]::FindWindowEx([IntPtr]::Zero, [IntPtr]::Zero, '#32768', $null)
    while ($h -ne [IntPtr]::Zero) { $o += $h; $h = [CP]::FindWindowEx([IntPtr]::Zero, $h, '#32768', $null) }
    return $o
}
$x = [int]$args[0]; $y = [int]$args[1]
"menus open before: $(@(Menu-List).Count)"
foreach ($m in @(Menu-List)) {
    $r = New-Object CP+R; [void][CP]::GetWindowRect($m, [ref]$r)
"  menu $m rect $($r.left),$($r.top) $($r.right-$r.left)x$($r.bottom-$r.top)" }
$p = New-Object CP+P
[void][CP]::SetCursorPos($x, $y)
Start-Sleep -Milliseconds 300
[void][CP]::GetCursorPos([ref]$p)
"cursor now at $($p.x),$($p.y)  (asked for $x,$y)"
$h = [CP]::WindowFromPoint($p)
$cn = New-Object System.Text.StringBuilder 256
[void][CP]::GetClassName($h, $cn, 256)
$root = [CP]::GetAncestor($h, 2)
$rc = New-Object System.Text.StringBuilder 256
[void][CP]::GetClassName($root, $rc, 256)
$pid2 = [uint32]0; [void][CP]::GetWindowThreadProcessId($root, [ref]$pid2)
"window at point: $h class='$($cn.ToString())'  root=$root class='$($rc.ToString())' pid=$pid2"
"foreground: $([CP]::GetForegroundWindow())"
[void][CP]::mouse_event(0x0008, 0, 0, 0, [UIntPtr]::Zero)
Start-Sleep -Milliseconds 150
[void][CP]::mouse_event(0x0010, 0, 0, 0, [UIntPtr]::Zero)
Start-Sleep -Milliseconds 1200
$after = @(Menu-List)
"menus open after: $($after.Count)"
foreach ($m in $after) {
    $r = New-Object CP+R; [void][CP]::GetWindowRect($m, [ref]$r)
"  menu $m rect $($r.left),$($r.top) $($r.right-$r.left)x$($r.bottom-$r.top)" }
