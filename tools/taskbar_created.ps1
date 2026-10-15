Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class W {
    public delegate bool EnumProc(IntPtr h, IntPtr l);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
    [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] public static extern uint RegisterWindowMessage(string s);
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint msg, IntPtr w, IntPtr l);
}
"@

$found = New-Object System.Collections.ArrayList
$cb = [W+EnumProc] {
    param($h, $l)
    $t = New-Object System.Text.StringBuilder 256
    [void][W]::GetWindowText($h, $t, 256)
    if ($t.ToString() -eq 'WinShotSink') {
        $c = New-Object System.Text.StringBuilder 256
        [void][W]::GetClassName($h, $c, 256)
        [void]$found.Add(@{ hwnd = $h; class = $c.ToString() })
    }
    return $true
}
[void][W]::EnumWindows($cb, [IntPtr]::Zero)

if ($found.Count -eq 0) { "no WinShotSink window found"; exit 1 }
foreach ($f in $found) { "found hwnd=$($f.hwnd) class=$($f.class)" }

$msg = [W]::RegisterWindowMessage('TaskbarCreated')
"TaskbarCreated message id = $msg"
foreach ($f in $found) {
    "posting -> $($f.hwnd): $([W]::PostMessage($f.hwnd, $msg, [IntPtr]::Zero, [IntPtr]::Zero))"
}
Start-Sleep -Seconds 2
