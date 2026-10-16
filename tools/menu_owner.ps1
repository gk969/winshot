Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class MO {
    [DllImport("user32.dll")] public static extern IntPtr FindWindowEx(IntPtr p, IntPtr a, string c, string t);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("user32.dll")] public static extern bool IsWindowUnicode(IntPtr h);
    [DllImport("user32.dll")] public static extern IntPtr GetParent(IntPtr h);
    [DllImport("user32.dll")] public static extern bool GetCursorPos(out P p);
    [DllImport("user32.dll")] public static extern bool GetClipCursor(out R r);
    [StructLayout(LayoutKind.Sequential)] public struct P { public int x, y; }
    [StructLayout(LayoutKind.Sequential)] public struct R { public int left, top, right, bottom; }
}
"@
$h = [MO]::FindWindowEx([IntPtr]::Zero, [IntPtr]::Zero, '#32768', $null)
while ($h -ne [IntPtr]::Zero) {
    $pid2 = [uint32]0
    $tid = [MO]::GetWindowThreadProcessId($h, [ref]$pid2)
    $proc = Get-Process -Id $pid2 -ErrorAction SilentlyContinue
    "menu $h pid=$pid2 tid=$tid name=$($proc.ProcessName) parent=$([MO]::GetParent($h))"
    $h = [MO]::FindWindowEx([IntPtr]::Zero, $h, '#32768', $null)
}
$p = New-Object MO+P; [void][MO]::GetCursorPos([ref]$p)
$c = New-Object MO+R; [void][MO]::GetClipCursor([ref]$c)
"cursor $($p.x),$($p.y)  clip $($c.left),$($c.top) $($c.right-$c.left)x$($c.bottom-$c.top)"
