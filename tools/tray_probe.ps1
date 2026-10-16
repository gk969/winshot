# What the shell actually sends the icon callback for a real right click.
#
# The version-0 and version-4 layouts of the callback's wParam/lParam disagree
# about where the event id and the point live, and getting it wrong makes the
# switch match nothing, which looks like "the icon ignores right click". This
# launches the app with WINSHOT_TRAYLOG set, right-clicks the icon found by its
# tooltip (the only locator that names the owner exactly), and prints the raw
# parameters the sink saw.
param([switch]$Left)

Add-Type -AssemblyName System.Drawing, System.Windows.Forms
Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class TP {
    [DllImport("user32.dll")] public static extern IntPtr FindWindowEx(IntPtr p, IntPtr a, string c, string t);
    [DllImport("user32.dll", EntryPoint = "FindWindowExW")] public static extern IntPtr FindWindowExAny(IntPtr p, IntPtr a, IntPtr c, IntPtr t);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")] public static extern bool GetCursorPos(out POINT p);
    [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint dx, uint dy, uint d, UIntPtr e);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr h, ref POINT p);
    [DllImport("user32.dll")] public static extern IntPtr SendMessageTimeoutW(IntPtr h, uint m, IntPtr w, IntPtr l, uint f, uint ms, out IntPtr res);
    [DllImport("kernel32.dll")] public static extern IntPtr OpenProcess(uint access, bool inherit, uint pid);
    [DllImport("kernel32.dll")] public static extern IntPtr VirtualAllocEx(IntPtr h, IntPtr addr, IntPtr size, uint alloc, uint protect);
    [DllImport("kernel32.dll")] public static extern bool VirtualFreeEx(IntPtr h, IntPtr addr, IntPtr size, uint free);
    [DllImport("kernel32.dll")] public static extern bool WriteProcessMemory(IntPtr h, IntPtr addr, byte[] buf, IntPtr size, out IntPtr written);
    [DllImport("kernel32.dll")] public static extern bool ReadProcessMemory(IntPtr h, IntPtr addr, byte[] buf, IntPtr size, out IntPtr read);
    [DllImport("kernel32.dll")] public static extern bool CloseHandle(IntPtr h);
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int left, top, right, bottom; }
    [StructLayout(LayoutKind.Sequential)] public struct POINT { public int x, y; }
    public const uint TB_BUTTONCOUNT = 0x0418, TB_GETITEMRECT = 0x0414, TB_GETBUTTONTEXTW = 0x044B;
    public const uint SMTO_ABORTIFHUNG = 0x0002;
    public const uint PROCESS_RW = 0x0008 | 0x0010 | 0x0020;
    public const uint MEM_COMMIT_RESERVE = 0x3000, PAGE_RW = 0x04, MEM_RELEASE = 0x8000;
}
"@

function SMT([IntPtr]$h, [uint32]$msg, [IntPtr]$w, [IntPtr]$l) {
    $r = [IntPtr]::Zero
    [void][TP]::SendMessageTimeoutW($h, $msg, $w, $l, [TP]::SMTO_ABORTIFHUNG, 1500, [ref]$r)
    return $r
}
function Tray-Toolbars() {
    $out = @(); $seen = @{}
    $stack = New-Object System.Collections.Stack
    foreach ($root in 'Shell_TrayWnd', 'NotifyIconOverflowWindow') {
        $h = [TP]::FindWindowEx([IntPtr]::Zero, [IntPtr]::Zero, $root, $null)
        if ($h -ne [IntPtr]::Zero) { $stack.Push($h) }
    }
    while ($stack.Count) {
        $w = $stack.Pop()
        $k = $w.ToInt64(); if ($seen.ContainsKey($k)) { continue }
        $seen[$k] = $true
        $cn = New-Object System.Text.StringBuilder 256
        [void][TP]::GetClassName($w, $cn, 256)
        if ($cn.ToString() -eq 'ToolbarWindow32') { $out += $w }
        $c = [TP]::FindWindowExAny($w, [IntPtr]::Zero, [IntPtr]::Zero, [IntPtr]::Zero)
        while ($c -ne [IntPtr]::Zero) { $stack.Push($c)
            $c = [TP]::FindWindowExAny($w, $c, [IntPtr]::Zero, [IntPtr]::Zero) }
    }
    return $out
}
# Our icon, by tooltip. A killed run leaves its icon behind as a dead button with
# the same tooltip, so every match is returned and the caller tries them in turn.
function Find-Icon([string]$tip) {
    $res = @()
    foreach ($tb in @(Tray-Toolbars)) {
        $pid2 = [uint32]0
        [void][TP]::GetWindowThreadProcessId($tb, [ref]$pid2)
        $proc = [TP]::OpenProcess([TP]::PROCESS_RW, $false, $pid2)
        if ($proc -eq [IntPtr]::Zero) { continue }
        $buf = [TP]::VirtualAllocEx($proc, [IntPtr]::Zero, [IntPtr]1024,
                                    [TP]::MEM_COMMIT_RESERVE, [TP]::PAGE_RW)
        if ($buf -ne [IntPtr]::Zero) {
            $n = [int](SMT $tb ([TP]::TB_BUTTONCOUNT) ([IntPtr]::Zero) ([IntPtr]::Zero))
            for ($i = 0; $i -lt $n; $i++) {
                $wr = [IntPtr]::Zero
                [void][TP]::WriteProcessMemory($proc, $buf, (New-Object byte[] 512), [IntPtr]512, [ref]$wr)
                [void](SMT $tb ([TP]::TB_GETBUTTONTEXTW) ([IntPtr]$i) $buf)
                $bytes = New-Object byte[] 512
                $rr = [IntPtr]::Zero
                [void][TP]::ReadProcessMemory($proc, $buf, $bytes, [IntPtr]512, [ref]$rr)
                $t = [System.Text.Encoding]::Unicode.GetString($bytes)
                $z = $t.IndexOf([char]0); if ($z -ge 0) { $t = $t.Substring(0, $z) }
                if ($t -notlike "*$tip*") { continue }
                [void][TP]::WriteProcessMemory($proc, $buf, (New-Object byte[] 16), [IntPtr]16, [ref]$wr)
                [void](SMT $tb ([TP]::TB_GETITEMRECT) ([IntPtr]$i) $buf)
                $rb = New-Object byte[] 16
                [void][TP]::ReadProcessMemory($proc, $buf, $rb, [IntPtr]16, [ref]$rr)
                $p = New-Object TP+POINT
                $p.x = [int](([BitConverter]::ToInt32($rb, 0) + [BitConverter]::ToInt32($rb, 8)) / 2)
                $p.y = [int](([BitConverter]::ToInt32($rb, 4) + [BitConverter]::ToInt32($rb, 12)) / 2)
                [void][TP]::ClientToScreen($tb, [ref]$p)
                $res += , @{ x = $p.x; y = $p.y; tb = $tb }
            }
            [void][TP]::VirtualFreeEx($proc, $buf, [IntPtr]0, [TP]::MEM_RELEASE)
        }
        [void][TP]::CloseHandle($proc)
    }
    return , $res
}
function Menu-Wins() {
    $list = New-Object System.Collections.ArrayList
    $h = [TP]::FindWindowEx([IntPtr]::Zero, [IntPtr]::Zero, '#32768', $null)
    while ($h -ne [IntPtr]::Zero) { [void]$list.Add($h)
        $h = [TP]::FindWindowEx([IntPtr]::Zero, $h, '#32768', $null) }
    return $list.ToArray()
}

$DOWN = 0x0002; $UP = 0x0004
if ($Left) { $DOWN = 0x0002; $UP = 0x0004 } else { $DOWN = 0x0008; $UP = 0x0010 }

Get-Process winshot -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 800
Remove-Item 'D:\Project\winshot\obj\tray.log' -ErrorAction SilentlyContinue
$env:WINSHOT_TRAYLOG = '1'
$p = Start-Process -FilePath 'D:\Project\winshot\x64\Debug\winshot.exe' -PassThru
Start-Sleep -Seconds 3

# TB_GETITEMRECT came back 0,0 for our button, so the click point comes from the
# pixels the shell drew instead: the red dot is ~5px across and only our icon has
# one. The tooltip lookup stays as a cross-check of where the shell thinks it is.
function Scan-Tray-Icons {
    $va = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    $x0 = $va.Right - 620; $x1 = $va.Right - 44
    $w = $x1 - $x0; $h = $va.Bottom - ($va.Bottom - 48)
    $y0 = $va.Bottom - 48; $y1 = $va.Bottom; $h = $y1 - $y0
    $bmp = New-Object System.Drawing.Bitmap $w, $h
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen([System.Drawing.Point]::new($x0, $y0),
                      [System.Drawing.Point]::Empty, $bmp.Size)
    $g.Dispose()
    $red = New-Object int[] $w; $white = New-Object int[] $w
    for ($x = 0; $x -lt $w; $x++) {
        for ($y = 0; $y -lt $h; $y++) {
            $c = $bmp.GetPixel($x, $y)
            if ($c.R -gt 230 -and $c.G -gt 230 -and $c.B -gt 230) { $white[$x]++ }
            elseif ($c.R -gt 190 -and $c.G -lt 110 -and $c.B -lt 110) { $red[$x]++ }
        }
    }
    $bmp.Dispose()
    $out = @()
    for ($x = 0; $x -lt $w; $x++) {
        if ($red[$x] -lt 3) { continue }
        $c = $x
        while ($c -lt $w -and $red[$c] -ge 3) { $c++ }
        if ($c - $x -gt 10) { $x = $c; continue }
        $m = [int](($x + $c - 1) / 2)
        $field = 0
        for ($k = [Math]::Max(0, $m - 14); $k -le [Math]::Min($w - 1, $m + 14); $k++) {
            if ($white[$k] -ge 2) { $field++ }
        }
        if ($field -ge 12) { $out += , @{ x = $x0 + $m; y = [int](($y0 + $y1) / 2) } }
        $x = $c
    }
    return $out
}

$byTip = @(Find-Icon 'WinShot')
"shell says our button is at: $(($byTip | ForEach-Object { "($($_.x),$($_.y))" }) -join ' ')"
# The shell animates the icon in and reorders the strip; an early scan comes back
# empty rather than partial.
$cands = @()
for ($i = 0; $i -lt 12; $i++) {
    $cands = @(Scan-Tray-Icons)
    if ($cands.Count) { break }
    Start-Sleep -Milliseconds 500
}
"icon-shaped pixels: $(($cands | ForEach-Object { "($($_.x),$($_.y))" }) -join ' ')"
if (-not $cands.Count) { 'FAIL: no icon-shaped pixel in the tray strip'; exit 1 }

$before = @(Menu-Wins)
$hit = $null
foreach ($c in $cands) {
    [void][TP]::SetCursorPos($c.x, $c.y)
    Start-Sleep -Milliseconds 250
    $gp = New-Object TP+POINT
    [void][TP]::GetCursorPos([ref]$gp)
    if ([Math]::Abs($gp.x - $c.x) -gt 4) {
        "  ($($c.x),$($c.y)): cursor stopped at $($gp.x) — a menu elsewhere confines it"; continue
    }
    [void][TP]::mouse_event($DOWN, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 120
    [void][TP]::mouse_event($UP, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 1200
    $new = @( @(Menu-Wins) | Where-Object { $before -notcontains $_ })
    "  ($($c.x),$($c.y)): menu appeared = $($new.Count -gt 0)"
    if ($new.Count) { $hit = $c; break }
}
Start-Sleep -Milliseconds 400
[void][System.Windows.Forms.SendKeys]::SendWait('{ESC}')
Start-Sleep -Milliseconds 300
Get-Process winshot -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 300

if (-not (Test-Path 'D:\Project\winshot\obj\tray.log')) { 'no tray.log written'; exit 1 }
'--- what the sink saw ---'
Get-Content 'D:\Project\winshot\obj\tray.log'
if ($hit) { "menu opened at ($($hit.x),$($hit.y))" } else { 'no candidate opened a menu' }
