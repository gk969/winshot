Add-Type -AssemblyName System.Windows.Forms
Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class KM2 {
    [DllImport("user32.dll")] public static extern IntPtr FindWindowEx(IntPtr p, IntPtr a, string c, string t);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out R r);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint dx, uint dy, uint d, UIntPtr e);
    [StructLayout(LayoutKind.Sequential)] public struct R { public int left, top, right, bottom; }
}
"@
function Menus() { $o=@(); $h=[KM2]::FindWindowEx([IntPtr]::Zero,[IntPtr]::Zero,'#32768',$null)
  while ($h -ne [IntPtr]::Zero) { $o += $h; $h=[KM2]::FindWindowEx([IntPtr]::Zero,$h,'#32768',$null) }; return $o }
for ($try = 0; $try -lt 6; $try++) {
    $ms = @(Menus); if (-not $ms.Count) { "clear after $try tries"; break }
    foreach ($m in $ms) {
        $r = New-Object KM2+R; [void][KM2]::GetWindowRect($m, [ref]$r)
        $p = [uint32]0; [void][KM2]::GetWindowThreadProcessId($m, [ref]$p)
        $n = (Get-Process -Id $p -ErrorAction SilentlyContinue).ProcessName
        "menu $m owner=$n rect $($r.left),$($r.top) $($r.right-$r.left)x$($r.bottom-$r.top)"
        # Clicking an item of a menu that ignores ESC and WM_CANCELMODE is the
        # only thing that ends its loop.
        [void][KM2]::SetCursorPos([int](($r.left+$r.right)/2), [int](($r.top+$r.bottom)/2))
        Start-Sleep -Milliseconds 250
        [void][KM2]::mouse_event(0x0002,0,0,0,[UIntPtr]::Zero)
        Start-Sleep -Milliseconds 150
        [void][KM2]::mouse_event(0x0004,0,0,0,[UIntPtr]::Zero)
    }
    Start-Sleep -Milliseconds 700
}
"final: $(@(Menus).Count) menu(s)"
