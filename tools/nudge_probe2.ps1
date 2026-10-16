# Does the arrow-key nudge repaint the whole overlay correctly? CopyFromScreen
# captures whatever is on top, and this desktop is neither static nor always
# behind the overlay, so the pixel probes drift. PrintWindow asks the overlay
# itself to render, which tests our paint path and nothing else.
Add-Type -AssemblyName System.Drawing, System.Windows.Forms
Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class W4 {
    public delegate bool EnumProc(IntPtr h, IntPtr l);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
    [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint msg, IntPtr w, IntPtr l);
    [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint dx, uint dy, uint d, UIntPtr e);
    [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr dc, uint flags);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int left, top, right, bottom; }
}
"@

$LEFTDOWN = 0x0002; $LEFTUP = 0x0004

function MoveTo([int]$x, [int]$y) {
    [System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point($x, $y)
    Start-Sleep -Milliseconds 120
}
function Drag([int]$x1, [int]$y1, [int]$x2, [int]$y2) {
    MoveTo $x1 $y1
    [void][W4]::mouse_event($LEFTDOWN, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 120
    for ($i = 1; $i -le 12; $i++) {
        MoveTo ([int]($x1 + ($x2-$x1) * $i / 12)) ([int]($y1 + ($y2-$y1) * $i / 12))
    }
    Start-Sleep -Milliseconds 150
    [void][W4]::mouse_event($LEFTUP, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 300
}

function FindOverlay() {
    $list = New-Object System.Collections.ArrayList
    $cb = [W4+EnumProc] {
        param($h, $l)
        $t = New-Object System.Text.StringBuilder 256
        [void][W4]::GetWindowText($h, $t, 256)
        if ($t.ToString() -eq 'WinShotOverlay') { [void]$list.Add($h) }
        return $true
    }
    [void][W4]::EnumWindows($cb, [IntPtr]::Zero)
    return $list
}

# Renders the overlay into a bitmap and returns the locked bytes plus the
# window's screen rect, so the frame coordinates stay in screen space.
function Render($hwnd, [string]$path) {
    $r = New-Object W4+RECT
    [void][W4]::GetWindowRect($hwnd, [ref]$r)
    $w = $r.right - $r.left; $h = $r.bottom - $r.top
    $bmp = New-Object System.Drawing.Bitmap $w, $h
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    [void][W4]::PrintWindow($hwnd, $g.GetHdc(), 2)   # PW_RENDERFULLCONTENT
    $g.Dispose()
    $bmp.Save($path)
    $rect = New-Object System.Drawing.Rectangle 0, 0, $w, $h
    $data = $bmp.LockBits($rect, [System.Drawing.Imaging.ImageLockMode]::ReadOnly,
                          [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $bytes = New-Object byte[] ($data.Stride * $data.Height)
    [System.Runtime.InteropServices.Marshal]::Copy($data.Scan0, $bytes, 0, $bytes.Length)
    $bmp.UnlockBits($data)
    return ,@($bytes, $data.Stride, $r.left, $r.top, $w, $h, $bmp)
}

function Px($pack, [int]$x, [int]$y) {
    $i = ($y - $pack[3]) * $pack[1] + ($x - $pack[2]) * 4
    return @([int]$pack[0][$i+2], [int]$pack[0][$i+1], [int]$pack[0][$i])
}
function IsBlue($pack, [int]$x, [int]$y) {
    $p = Px $pack $x $y
    return ($p[0] -ge 190 -and $p[1] -ge 130 -and $p[1] -le 190 -and $p[2] -le 90)
}
function FindFrameV($pack, [int]$y, [int]$from, [int]$to) {
    for ($x = $from; $x -lt $to; $x++) {
        if ((IsBlue $pack $x $y) -and (IsBlue $pack ($x + 1) $y)) { return $x + 1 }
    }
    return -1
}
function FindFrameH($pack, [int]$x, [int]$from, [int]$to) {
    for ($y = $from; $y -lt $to; $y++) {
        if ((IsBlue $pack $x $y) -and (IsBlue $pack $x ($y + 1))) { return $y + 1 }
    }
    return -1
}

Get-Process winshot -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 500
MoveTo 3000 1900
Start-Sleep -Milliseconds 400

Start-Process -FilePath 'D:\Project\winshot\x64\Debug\winshot.exe'
Start-Sleep -Seconds 2

$sink = New-Object System.Collections.ArrayList
$cb = [W4+EnumProc] {
    param($h, $l)
    $t = New-Object System.Text.StringBuilder 256
    [void][W4]::GetWindowText($h, $t, 256)
    if ($t.ToString() -eq 'WinShotSink') { [void]$sink.Add($h) }
    return $true
}
[void][W4]::EnumWindows($cb, [IntPtr]::Zero)
if ($sink.Count -eq 0) { 'no sink window'; exit 1 }
[void][W4]::PostMessage($sink[0], 0x8002, [IntPtr]::Zero, [IntPtr]::Zero)
Start-Sleep -Seconds 2

$ov = FindOverlay
if ($ov.Count -eq 0) { 'no overlay window'; exit 1 }
$ovh = $ov[0]
"overlay visible=$([W4]::IsWindowVisible($ovh)) foreground=$([W4]::GetForegroundWindow() -eq $ovh)"

Drag 1000 800 1900 1400
$p1 = Render $ovh 'D:\Project\winshot\obj\np2_resize.png'
"after create: window $($p1[4])x$($p1[5]) at ($($p1[2]),$($p1[3]))"
$l = FindFrameV $p1 1100 990 1010
$r = FindFrameV $p1 1100 1890 1910
$t = FindFrameH $p1 1400 790 810
$b = FindFrameH $p1 1400 1390 1410
"create frame: l=$l top=$t r=$r bot=$b  (want 1000 800 1900 1400)"
$p1[6].Dispose()

for ($i = 0; $i -lt 5; $i++) { [System.Windows.Forms.SendKeys]::SendWait('{RIGHT}'); Start-Sleep -Milliseconds 150 }
for ($i = 0; $i -lt 5; $i++) { [System.Windows.Forms.SendKeys]::SendWait('+{RIGHT}'); Start-Sleep -Milliseconds 150 }
for ($i = 0; $i -lt 3; $i++) { [System.Windows.Forms.SendKeys]::SendWait('+{DOWN}'); Start-Sleep -Milliseconds 150 }
Start-Sleep -Milliseconds 500

$p2 = Render $ovh 'D:\Project\winshot\obj\np2_nudge.png'
$l = FindFrameV $p2 1100 1040 1160
$r = FindFrameV $p2 1100 1940 2060
$t = FindFrameH $p2 1400 820 900
$b = FindFrameH $p2 1400 1420 1500
"nudge frame:  l=$l top=$t r=$r bot=$b  (want 1055 830 1955 1430)"
"nudge size:   $($r-$l) x $($b-$t)  (want 900 x 600)"
$p2[6].Dispose()

[System.Windows.Forms.SendKeys]::SendWait('{ESC}')
Start-Sleep -Milliseconds 500
Get-Process winshot -ErrorAction SilentlyContinue | Stop-Process -Force
