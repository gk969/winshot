Add-Type -AssemblyName System.Drawing, System.Windows.Forms
Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class W5 {
    public delegate bool EnumProc(IntPtr h, IntPtr l);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
    [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint msg, IntPtr w, IntPtr l);
    [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint dx, uint dy, uint d, UIntPtr e);

    [StructLayout(LayoutKind.Sequential)] public struct MI {
        public int dx, dy; public uint mouseData; public ushort dwFlags; public uint time; public IntPtr extra;
    }
    [StructLayout(LayoutKind.Explicit)] public struct INP {
        [FieldOffset(0)] public uint type;
        [FieldOffset(8)] public MI mi;
    }
    [DllImport("user32.dll")] public static extern uint SendInput(uint n, INP[] inputs, int cb);
    [DllImport("user32.dll")] public static extern IntPtr WindowFromPoint(POINT p);
    [DllImport("user32.dll")] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
    [StructLayout(LayoutKind.Sequential)] public struct POINT { public int x, y; }
    public static void Warp(int x, int y, int vw, int vh) {
        INP[] i = new INP[1];
        i[0].type = 0;
        i[0].mi.dx = (int)((long)x * 65535 / vw);
        i[0].mi.dy = (int)((long)y * 65535 / vh);
        i[0].mi.dwFlags = 0x0001 | 0x4000 | 0x8000;  // MOVE | ABSOLUTE | VIRTUALDESK
        SendInput(1, i, System.Runtime.InteropServices.Marshal.SizeOf(typeof(INP)));
    }
}
"@

$LEFTDOWN = 0x0002; $LEFTUP = 0x0004

function Grab([string]$path) {
    $b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    $bmp = New-Object System.Drawing.Bitmap $b.Width, $b.Height
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen($b.Location, [System.Drawing.Point]::Empty, $bmp.Size)
    $bmp.Save($path)
    $g.Dispose()
    return $bmp
}
function MoveTo([int]$x, [int]$y) {
    [W5]::Warp($x, $y, $screenW, $screenH)
    Start-Sleep -Milliseconds 120
}
function Drag([int]$x1, [int]$y1, [int]$x2, [int]$y2) {
    MoveTo $x1 $y1
    [void][W5]::mouse_event($LEFTDOWN, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 120
    for ($i = 1; $i -le 12; $i++) {
        MoveTo ([int]($x1 + ($x2-$x1) * $i / 12)) ([int]($y1 + ($y2-$y1) * $i / 12))
    }
    Start-Sleep -Milliseconds 150
    [void][W5]::mouse_event($LEFTUP, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 300
}
function IsBack($c) {
    return ([Math]::Abs($c.R - 235) -le 8 -and [Math]::Abs($c.G - 239) -le 8 -and
            [Math]::Abs($c.B - 243) -le 8)
}
# First y scanning up from $y1 at which the column sits in the chrome background.
function BandUp($bmp, [int]$x, [int]$y0, [int]$y1) {
    $bot = -1
    for ($y = $y1; $y -ge $y0; $y--) {
        if (IsBack ($bmp.GetPixel($x, $y))) { $bot = $y; break }
    }
    if ($bot -lt 0) { return $null }
    $top = $bot
    while ($top - 1 -ge $y0 -and (IsBack ($bmp.GetPixel($x, ($top - 1))))) { $top-- }
    return @($top, $bot)
}

$screenW = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds.Width
$screenH = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds.Height

MoveTo 3000 1900
Start-Sleep -Milliseconds 400

$p = Start-Process -FilePath 'D:\Project\winshot\x64\Debug\winshot.exe' -PassThru
Start-Sleep -Seconds 2

$sink = New-Object System.Collections.ArrayList
$cb = [W5+EnumProc] {
    param($h, $l)
    $t = New-Object System.Text.StringBuilder 256
    [void][W5]::GetWindowText($h, $t, 256)
    if ($t.ToString() -eq 'WinShotSink') { [void]$sink.Add($h) }
    return $true
}
[void][W5]::EnumWindows($cb, [IntPtr]::Zero)
if ($sink.Count -eq 0) { "no sink window"; exit 1 }

[void][W5]::PostMessage($sink[0], 0x8002, [IntPtr]::Zero, [IntPtr]::Zero)
Start-Sleep -Seconds 2

$screen = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
$bottom = $screen.Height - 12

# A selection that runs into the bottom edge: the toolbar has to flip above.
Drag 800 1700 1400 $bottom
$sel = @(800, 1700, 1400, $bottom)
$s = Grab 'D:\Project\winshot\obj\s3_flip.png'

$b = BandUp $s ($sel[0] + 6) ($sel[1] - 90) ($sel[1] - 1)
if (-not $b) { "FAIL: no toolbar above the selection" }
else {
    "flipped toolbar y=$($b[0])..$($b[1]) height=$($b[1] - $b[0] + 1)  (want top=$($sel[1] - 34), bottom=$($sel[1] - 3))"
}

# Hover the 4th slot (pen) and wait out the tooltip delay.
$tbTop = $b[0]
$cell = 27
$hx = $sel[0] + 4 + 3 * $cell + [int]($cell / 2)
$hy = [int](($b[0] + $b[1]) / 2)
"`nhovering pen slot at ($hx,$hy)"
MoveTo $hx $hy
Start-Sleep -Milliseconds 900
$t = Grab 'D:\Project\winshot\obj\s3_tip.png'

# The tooltip is a separate top-level window: a white card near the cursor that
# is neither the chrome background (235,239,243) nor the dimmed desktop.
function IsWhite($c) { return ($c.R -gt 246 -and $c.G -gt 246 -and $c.B -gt 246) }
$yLo = [Math]::Max(0, $hy - 80); $yHi = [Math]::Min($t.Height - 1, $hy + 80)
$xLo = [Math]::Max(0, $hx - 120); $xHi = [Math]::Min($t.Width - 1, $hx + 120)
$l = -1; $r = -1; $tp = -1; $bt = -1
for ($y = $yLo; $y -le $yHi; $y++) {
    for ($x = $xLo; $x -le $xHi; $x++) {
        if (IsWhite ($t.GetPixel($x, $y))) {
            if ($l -lt 0) { $l = $x }
            if ($x -gt $r) { $r = $x }
            if ($tp -lt 0) { $tp = $y }
            $bt = $y
        }
    }
}
$wfp = [W5]::WindowFromPoint([W5+POINT]::new($hx, $hy))
$cn = New-Object System.Text.StringBuilder 256
[void][W5]::GetClassName($wfp, $cn, 256)
"window under cursor: hwnd=$wfp class=$($cn.ToString())"
$hot = $t.GetPixel($hx, $b[0] + 2)
"cell pixel under cursor = #{0:X2}{1:X2}{2:X2}  (plain chrome = EBEFF3)" -f $hot.R, $hot.G, $hot.B
if ($l -lt 0) { "FAIL: no white tooltip card near the cursor" }
else {
    "tooltip card x=$l..$r w=$($r - $l + 1) y=$tp..$bt h=$($bt - $tp + 1)  (cursor ($hx,$hy))"
}

[void][System.Windows.Forms.SendKeys]::SendWait("{ESC}")
Start-Sleep -Milliseconds 500
"winshot still running: $(-not $p.HasExited)"
if (-not $p.HasExited) { $p.Kill() }
