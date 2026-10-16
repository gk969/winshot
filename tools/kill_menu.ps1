Add-Type -AssemblyName System.Windows.Forms
Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class KM {
    [DllImport("user32.dll")] public static extern IntPtr FindWindowEx(IntPtr p, IntPtr a, string c, string t);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out R r);
    [DllImport("user32.dll")] public static extern IntPtr GetAncestor(IntPtr h, uint f);
    [DllImport("user32.dll")] public static extern IntPtr PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
    [DllImport("user32.dll")] public static extern IntPtr SendMessageTimeout(IntPtr h, uint m, IntPtr w, IntPtr l, uint f, uint ms, out IntPtr r);
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint dx, uint dy, uint d, UIntPtr e);
    [StructLayout(LayoutKind.Sequential)] public struct R { public int left, top, right, bottom; }
}
"@
function Menus() { $o=@(); $h=[KM]::FindWindowEx([IntPtr]::Zero,[IntPtr]::Zero,'#32768',$null)
  while ($h -ne [IntPtr]::Zero) { $o += $h; $h=[KM]::FindWindowEx([IntPtr]::Zero,$h,'#32768',$null) }; return $o }
for ($try = 0; $try -lt 5; $try++) {
    $ms = @(Menus)
    "try ${try}: $(@($ms).Count) menu(s)"
    if (-not $ms.Count) { "  clear"; break }
    foreach ($m in $ms) {
        $r = New-Object KM+R; [void][KM]::GetWindowRect($m, [ref]$r)
        $root = [KM]::GetAncestor($m, 2)
        "  menu $m root=$root rect $($r.left),$($r.top) $($r.right-$r.left)x$($r.bottom-$r.top)"
        $res = [IntPtr]::Zero
        [void][KM]::SendMessageTimeout($m, 0x003A, [IntPtr]::Zero, [IntPtr]::Zero, 0x0002, 800, [ref]$res)
        [void][KM]::PostMessage($m, 0x003A, [IntPtr]::Zero, [IntPtr]::Zero)
    }
    Start-Sleep -Milliseconds 400
    if (@(Menus).Count) {
        "  still there; trying ESC"
        [void][System.Windows.Forms.SendKeys]::SendWait('{ESC}')
        Start-Sleep -Milliseconds 400
    }
    if (@(Menus).Count) {
        "  still there; clicking inside it"
        $r = New-Object KM+R; [void][KM]::GetWindowRect(@(Menus)[0], [ref]$r)
        [void][KM]::SetCursorPos([int](($r.left+$r.right)/2), [int](($r.top+$r.bottom)/2))
        Start-Sleep -Milliseconds 200
        [void][KM]::mouse_event(0x0002,0,0,0,[UIntPtr]::Zero)
        Start-Sleep -Milliseconds 120
        [void][KM]::mouse_event(0x0004,0,0,0,[UIntPtr]::Zero)
        Start-Sleep -Milliseconds 500
    }
    "  after: $(@(Menus).Count) menu(s)"
}
"final: $(@(Menus).Count) menu(s)"
