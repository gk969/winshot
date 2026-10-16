# Diagnostic: how the shell exposes the tray icons, so the right-click test can
# aim at one. Prints every descendant of the tray windows and of the overflow
# flyout, with Name, HelpText, rect and offscreen.
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes, WindowsBase
Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class TL {
    [DllImport("user32.dll")] public static extern IntPtr FindWindowEx(IntPtr p, IntPtr a, string c, string t);
    [DllImport("user32.dll")] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern IntPtr SendMessage(IntPtr h, uint m, IntPtr w, string l);
    public const int TB_BUTTONCOUNT = 0x0418;
}
"@
function Children([IntPtr]$h, [int]$depth, [string]$path) {
    $pane = [Windows.Automation.AutomationElement]::FromHandle($h)
    if ($null -eq $pane) { "$('  ' * $path)$path : no UIA provider"; return }
    foreach ($e in $pane.FindAll([Windows.Automation.TreeScope]::Children,
                                [Windows.Automation.Condition]::TrueCondition)) {
        $b = $e.Current.BoundingRectangle
        '{0}{1} name={2} help={3} rect={4},{5} {6}x{7} off={8}' -f ('  ' * $depth),
            $e.Current.ControlType.ProgrammaticName, $e.Current.Name,
            $e.Current.HelpText, [int]$b.X, [int]$b.Y, [int]$b.Width, [int]$b.Height,
            $e.Current.IsOffscreen
        # Recurse through the raw view by handle when the child has one.
        $hp = $e.Current.NativeWindowHandle
        if ($hp -ne 0) { Children ([IntPtr]$hp) ($depth + 1) '' }
    }
}
foreach ($cls in 'Shell_TrayWnd', 'NotifyIconOverflowWindow') {
    $h = [TL]::FindWindowEx([IntPtr]::Zero, [IntPtr]::Zero, $cls, $null)
    "=== $cls  hwnd=$h ==="
    if ($h -eq [IntPtr]::Zero) { continue }
    Children $h 0 ''
    # The native toolbar button count, which does not depend on UIA at all.
    $t = [TL]::FindWindowEx($h, [IntPtr]::Zero, 'ToolbarWindow32', $null)
    while ($t -ne [IntPtr]::Zero) {
        $cn = New-Object System.Text.StringBuilder 256
        [void][TL]::GetClassName($t, $cn, 256)
        "  toolbar $t buttons=$([int][TL]::SendMessage($t, [TL]::TB_BUTTONCOUNT, [IntPtr]::Zero, ''))"
        $t = [TL]::FindWindowEx($h, $t, 'ToolbarWindow32', $null)
    }
}
