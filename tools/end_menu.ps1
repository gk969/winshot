Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class EM {
    [DllImport("user32.dll")] public static extern bool EndMenu();
    [DllImport("user32.dll")] public static extern bool ExitMenuMode(IntPtr h);
    [DllImport("user32.dll")] public static extern IntPtr FindWindowEx(IntPtr p, IntPtr a, string c, string t);
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")] public static extern bool GetCursorPos(out P p);
    [StructLayout(LayoutKind.Sequential)] public struct P { public int x, y; }
}
"@
function Count() { $n=0; $h=[EM]::FindWindowEx([IntPtr]::Zero,[IntPtr]::Zero,'#32768',$null)
  while ($h -ne [IntPtr]::Zero) { $n++; $h=[EM]::FindWindowEx([IntPtr]::Zero,$h,'#32768',$null) }; return $n }
"menus before: $(Count)"
"EndMenu: $([EM]::EndMenu())  err=$([System.Runtime.InteropServices.Marshal]::GetLastWin32Error())"
Start-Sleep -Milliseconds 500
"menus after EndMenu: $(Count)"
if ((Count) -gt 0) {
    "ExitMenuMode: $([EM]::ExitMenuMode([IntPtr]::Zero))  err=$([System.Runtime.InteropServices.Marshal]::GetLastWin32Error())"
    Start-Sleep -Milliseconds 500
    "menus after ExitMenuMode: $(Count)"
}
$p = New-Object EM+P
[void][EM]::SetCursorPos(3300, 2136); [void][EM]::GetCursorPos([ref]$p)
"cursor after SetCursorPos(3300,2136): $($p.x),$($p.y)"
