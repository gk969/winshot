Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class MO2 {
    [DllImport("user32.dll")] public static extern IntPtr FindWindowEx(IntPtr p, IntPtr a, string c, string t);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("user32.dll")] public static extern IntPtr SendMessageTimeout(IntPtr h, uint m, IntPtr w, IntPtr l, uint f, uint ms, out IntPtr r);
    [DllImport("user32.dll")] public static extern bool PostThreadMessage(uint tid, uint m, IntPtr w, IntPtr l);
    [DllImport("user32.dll")] public static extern uint GetLastError();
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")] public static extern bool GetCursorPos(out P p);
    [StructLayout(LayoutKind.Sequential)] public struct P { public int x, y; }
}
"@
$h = [MO2]::FindWindowEx([IntPtr]::Zero, [IntPtr]::Zero, '#32768', $null)
if ($h -eq [IntPtr]::Zero) { 'no menu window'; exit }
$pid2 = [uint32]0; $tid = [MO2]::GetWindowThreadProcessId($h, [ref]$pid2)
$t = Get-Process -Id $pid2 -ErrorAction SilentlyContinue
"menu $h owner=$($t.ProcessName) pid=$pid2 tid=$tid responding=$($t.Responding) title=$($t.MainWindowTitle)"
# Does the owning thread answer a message at all?
$res = [IntPtr]::Zero
$ok = [MO2]::SendMessageTimeout($h, 0x0000, [IntPtr]::Zero, [IntPtr]::Zero, 0x0002, 1000, [ref]$res)
"WM_NULL round trip: ok=$ok err=$([System.Runtime.InteropServices.Marshal]::GetLastWin32Error())"
"PostThreadMessage WM_CANCELMODE: $([MO2]::PostThreadMessage($tid, 0x003A, [IntPtr]::Zero, [IntPtr]::Zero))"
Start-Sleep -Milliseconds 600
$p = New-Object MO2+P
[void][MO2]::SetCursorPos(3300, 2136)
[void][MO2]::GetCursorPos([ref]$p)
"cursor after SetCursorPos(3300,2136): $($p.x),$($p.y)"
"menu still there: $([bool]([MO2]::FindWindowEx([IntPtr]::Zero, [IntPtr]::Zero, '#32768', $null) -ne [IntPtr]::Zero))"
