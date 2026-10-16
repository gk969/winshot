# Where the frame actually is on each presented frame, during a drag as fast as
# a hand moves it. Grabs a strip across the frame's left edge at every vsync and
# reports the blue pixel's x next to the cursor's. Steady steps mean the motion
# is only late; a value that goes backwards means the frame jitters.
param([int]$Steps = 60, [int]$GapMs = 8)
Add-Type -AssemblyName System.Drawing, System.Windows.Forms
Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class JP {
    public delegate bool EnumProc(IntPtr h, IntPtr l);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
    [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint msg, IntPtr w, IntPtr l);
    [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint dx, uint dy, uint d, UIntPtr e);
    [DllImport("user32.dll")] public static extern bool GetCursorPos(out POINT p);
    [StructLayout(LayoutKind.Sequential)] public struct POINT { public int x, y; }
}
"@
$LEFTDOWN = 0x0002; $LEFTUP = 0x0004
function Find-Win([string]$title) {
    $found = New-Object System.Collections.ArrayList
    $cb = [JP+EnumProc] {
        param($h, $l)
        $t = New-Object System.Text.StringBuilder 256
        [void][JP]::GetWindowText($h, $t, 256)
        if ($t.ToString() -eq $title) { [void]$found.Add($h) }
        return $true
    }
    [void][JP]::EnumWindows($cb, [IntPtr]::Zero)
    return @($found)
}
Get-Process winshot -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 600
$p = Start-Process -FilePath 'D:\Project\winshot\x64\Debug\winshot.exe' -PassThru
Start-Sleep -Seconds 2
$sink = @(Find-Win 'WinShotSink')
if (-not $sink.Count) { 'FAIL: no sink'; exit 1 }
[void][JP]::PostMessage($sink[0], 0x8002, [IntPtr]::Zero, [IntPtr]::Zero)
Start-Sleep -Seconds 2
if (-not @(Find-Win 'WinShotOverlay').Count) { 'FAIL: no overlay'; exit 1 }

# The drag drags the selection's right edge, so its LEFT edge stays put and the
# strip instead crosses the top edge on its way down: sample a vertical strip at
# a fixed x inside the selection and find the topmost blue row.
$b = New-Object System.Drawing.Bitmap 1, 900
$g = [System.Drawing.Graphics]::FromImage($b)
function FrameTop([int]$x) {
    $g.CopyFromScreen($x, 300, 0, 0, $b.Size)
    for ($y = 0; $y -lt $b.Height; $y++) {
        $c = $b.GetPixel(0, $y)
        # The frame is the only bright blue thing on that column.
        if ($c.B -gt 150 -and $c.R -lt 90 -and $c.G -gt 110) { return 300 + $y }
    }
    return -1
}
[System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point(900, 700)
Start-Sleep -Milliseconds 200
[void][JP]::mouse_event($LEFTDOWN, 0, 0, 0, [UIntPtr]::Zero)
$rows = @(); $back = 0; $prev = -1
for ($i = 1; $i -le $Steps; $i++) {
    $x = 900 + $i * 12; $y = 700 + $i * 8
    [System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point($x, $y)
    $cp = New-Object JP+POINT
    [void][JP]::GetCursorPos([ref]$cp)
    $t = FrameTop 1200
    $d = -1
    if ($prev -ge 0 -and $t -ge 0 -and $t -lt $prev) { $d = $prev - $t; $back++ }
    $rows += , @{ i = $i; cur = $cp.y; top = $t; back = $d }
    $prev = $t
    Start-Sleep -Milliseconds $GapMs
}
[void][JP]::mouse_event($LEFTUP, 0, 0, 0, [UIntPtr]::Zero)
$g.Dispose(); $b.Dispose()
"cursor y -> frame top, per sample (back = how many px the frame moved UP):"
$rows | ForEach-Object { "  {0,3}  cur {1,5}  top {2,5}  back {3}" -f $_.i, $_.cur, $_.top, $_.back }
"samples where the frame moved backwards: $back of $($Steps - 1)"
[void][System.Windows.Forms.SendKeys]::SendWait('{ESC}')
Start-Sleep -Milliseconds 300
if (-not $p.HasExited) { $p.Kill() }
