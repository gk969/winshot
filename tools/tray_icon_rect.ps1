# Where the shell says each tray icon is, read from the toolbar itself.
#
# The tray icons are buttons of a ToolbarWindow32. TB_BUTTONCOUNT /
# TB_GETBUTTONTEXTW / TB_GETITEMRECT answer across processes, but the buffer
# argument is a pointer in the TARGET's address space, so it has to be
# allocated with VirtualAllocEx and read back. The text is the tooltip, which
# names the owner exactly — the only way to tell a live icon from the corpse a
# killed process left behind, and from the taskbar background between them.
Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class TI {
    [DllImport("user32.dll")] public static extern IntPtr FindWindowEx(IntPtr p, IntPtr a, string c, string t);
    // The overload for "no filter": PowerShell marshals a $null string argument
    // as "", which matches only windows whose class name is empty, so a null
    // class has to go through as a null pointer instead.
    [DllImport("user32.dll", EntryPoint = "FindWindowExW")] public static extern IntPtr FindWindowExAny(IntPtr p, IntPtr a, IntPtr c, IntPtr t);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] public static extern IntPtr SendMessageTimeoutW(IntPtr h, uint m, IntPtr w, IntPtr l, uint f, uint ms, out IntPtr res);
    [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr h, ref POINT p);
    [DllImport("user32.dll")] public static extern void GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("kernel32.dll")] public static extern IntPtr OpenProcess(uint access, bool inherit, uint pid);
    // SIZE_T as IntPtr, not UIntPtr: PowerShell 5.1 cannot cast a literal to
    // UIntPtr, and a 64-bit signed slot carries any size under 4 GB.
    [DllImport("kernel32.dll")] public static extern IntPtr VirtualAllocEx(IntPtr h, IntPtr addr, IntPtr size, uint alloc, uint protect);
    [DllImport("kernel32.dll")] public static extern bool VirtualFreeEx(IntPtr h, IntPtr addr, IntPtr size, uint free);
    [DllImport("kernel32.dll")] public static extern bool WriteProcessMemory(IntPtr h, IntPtr addr, byte[] buf, IntPtr size, out IntPtr written);
    [DllImport("kernel32.dll")] public static extern bool ReadProcessMemory(IntPtr h, IntPtr addr, byte[] buf, IntPtr size, out IntPtr read);
    [DllImport("kernel32.dll")] public static extern bool CloseHandle(IntPtr h);
    [StructLayout(LayoutKind.Sequential)] public struct POINT { public int x, y; }
    public const uint TB_BUTTONCOUNT = 0x0418;    // WM_USER + 24
    public const uint TB_GETITEMRECT = 0x0414;    // WM_USER + 20
    public const uint TB_GETBUTTONTEXTW = 0x044B; // WM_USER + 75
    public const uint SMTO_ABORTIFHUNG = 0x0002;
    public const uint PROCESS_RW = 0x0008 | 0x0010 | 0x0020; // VM_OPERATION|VM_READ|VM_WRITE
    public const uint MEM_COMMIT_RESERVE = 0x3000, PAGE_RW = 0x04, MEM_RELEASE = 0x8000;
}
"@
function SMT([IntPtr]$h, [uint32]$msg, [IntPtr]$w, [IntPtr]$l) {
    $r = [IntPtr]::Zero
    [void][TI]::SendMessageTimeoutW($h, $msg, $w, $l, [TI]::SMTO_ABORTIFHUNG, 1500, [ref]$r)
    return $r
}
# Every ToolbarWindow32 under the two windows that hold tray icons, at any
# depth: the visible ones sit under TrayNotifyWnd\SysPager, so a child-only
# search misses them.
function Tray-Toolbars() {
    $out = @(); $seen = @{}
    $stack = New-Object System.Collections.Stack
    foreach ($root in 'Shell_TrayWnd', 'NotifyIconOverflowWindow') {
        $h = [TI]::FindWindowEx([IntPtr]::Zero, [IntPtr]::Zero, $root, $null)
        if ($h -ne [IntPtr]::Zero) { $stack.Push($h) }
    }
    $visited = 0; $classes = @()
    while ($stack.Count) {
        $w = $stack.Pop()
        $key = $w.ToInt64()
        if ($seen.ContainsKey($key)) { continue }
        $seen[$key] = $true
        $visited++
        $cn = New-Object System.Text.StringBuilder 256
        [void][TI]::GetClassName($w, $cn, 256)
        if ($cn.ToString() -eq 'ToolbarWindow32') { $out += $w }
        if ($classes.Count -lt 40) { $classes += $cn.ToString() }
        $c = [TI]::FindWindowExAny($w, [IntPtr]::Zero, [IntPtr]::Zero, [IntPtr]::Zero)
        while ($c -ne [IntPtr]::Zero) { $stack.Push($c)
            $c = [TI]::FindWindowExAny($w, $c, [IntPtr]::Zero, [IntPtr]::Zero) }
    }
    # Anything this function emits lands in its return value, so the DFS summary
    # travels in a script variable instead of being printed here.
    $script:dfsInfo = "DFS visited $visited windows; classes: $(($classes -join ' '))"
    return $out
}
function Read-Buttons([IntPtr]$tb) {
    $pid2 = [uint32]0
    [void][TI]::GetWindowThreadProcessId($tb, [ref]$pid2)
    $proc = [TI]::OpenProcess([TI]::PROCESS_RW, $false, $pid2)
    if ($proc -eq [IntPtr]::Zero) { return $null }
    $buf = [TI]::VirtualAllocEx($proc, [IntPtr]::Zero, [IntPtr]1024,
                                [TI]::MEM_COMMIT_RESERVE, [TI]::PAGE_RW)
    $res = @()
    if ($buf -ne [IntPtr]::Zero) {
        $n = [int](SMT $tb ([TI]::TB_BUTTONCOUNT) ([IntPtr]::Zero) ([IntPtr]::Zero))
        for ($i = 0; $i -lt $n; $i++) {
            $wr = [IntPtr]::Zero
            [void][TI]::WriteProcessMemory($proc, $buf, (New-Object byte[] 512), [IntPtr]512, [ref]$wr)
            [void](SMT $tb ([TI]::TB_GETBUTTONTEXTW) ([IntPtr]$i) $buf)
            $bytes = New-Object byte[] 512
            $rr = [IntPtr]::Zero
            [void][TI]::ReadProcessMemory($proc, $buf, $bytes, [IntPtr]512, [ref]$rr)
            $text = [System.Text.Encoding]::Unicode.GetString($bytes)
            $z = $text.IndexOf([char]0)
            if ($z -ge 0) { $text = $text.Substring(0, $z) }

            [void][TI]::WriteProcessMemory($proc, $buf, (New-Object byte[] 16), [IntPtr]16, [ref]$wr)
            [void](SMT $tb ([TI]::TB_GETITEMRECT) ([IntPtr]$i) $buf)
            $rb = New-Object byte[] 16
            [void][TI]::ReadProcessMemory($proc, $buf, $rb, [IntPtr]16, [ref]$rr)
            $l = [BitConverter]::ToInt32($rb, 0); $t = [BitConverter]::ToInt32($rb, 4)
            $rt = [BitConverter]::ToInt32($rb, 8); $bt = [BitConverter]::ToInt32($rb, 12)

            $p = New-Object TI+POINT
            $p.x = [int](($l + $rt) / 2); $p.y = [int](($t + $bt) / 2)
            [void][TI]::ClientToScreen($tb, [ref]$p)
            $res += , @{ text = $text; x = $p.x; y = $p.y
                         box = "$l,$t $($rt-$l)x$($bt-$t)" }
        }
        [void][TI]::VirtualFreeEx($proc, $buf, [IntPtr]0, [TI]::MEM_RELEASE)
    }
    [void][TI]::CloseHandle($proc)
    return , $res
}

$tbs = Tray-Toolbars
$dfsInfo
"tray toolbars found: $(@($tbs).Count)"
foreach ($t in $tbs) {
    $b = Read-Buttons $t
    if ($null -eq $b) { "toolbar $t : not readable (access denied)"; continue }
    if (-not $b.Count) { continue }
    "toolbar $t : $($b.Count) buttons"
    foreach ($e in $b) { "   '{0}' client {1} -> screen ({2},{3})" -f $e.text, $e.box, $e.x, $e.y }
}
