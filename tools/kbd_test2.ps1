Add-Type -AssemblyName System.Drawing, System.Windows.Forms
Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class W2 {
    public delegate bool EnumProc(IntPtr h, IntPtr l);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
    [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint msg, IntPtr w, IntPtr l);
    [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint dx, uint dy, uint d, UIntPtr e);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
}
"@

function TitleOf([IntPtr]$h) {
    $t = New-Object System.Text.StringBuilder 256
    [void][W2]::GetWindowText($h, $t, 256)
    return $t.ToString()
}
function FindWindows([string]$title) {
    $list = New-Object System.Collections.ArrayList
    $cb = [W2+EnumProc] {
        param($h, $l)
        $t = New-Object System.Text.StringBuilder 256
        [void][W2]::GetWindowText($h, $t, 256)
        if ($t.ToString() -eq $title) { [void]$list.Add($h) }
        return $true
    }
    [void][W2]::EnumWindows($cb, [IntPtr]::Zero)
    return $list
}
function MoveTo([int]$x, [int]$y) {
    [System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point($x, $y)
    Start-Sleep -Milliseconds 120
}
function Drag([int]$x1, [int]$y1, [int]$x2, [int]$y2) {
    MoveTo $x1 $y1
    [void][W2]::mouse_event(0x0002, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 120
    for ($i = 1; $i -le 12; $i++) {
        MoveTo ([int]($x1 + ($x2-$x1) * $i / 12)) ([int]($y1 + ($y2-$y1) * $i / 12))
    }
    Start-Sleep -Milliseconds 150
    [void][W2]::mouse_event(0x0004, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 300
}

# The selection interior is the frozen still undimmed; outside it the still is
# dimmed by 0x99 black. Comparing each pixel of a scan line against both
# references gives an unambiguous boundary, unlike hunting for the frame colour,
# which also occurs in ordinary desktop content.
function GrabBytes() {
    $b = New-Object System.Drawing.Bitmap 3840, 2160
    $g = [System.Drawing.Graphics]::FromImage($b)
    $g.CopyFromScreen(0, 0, 0, 0, $b.Size)
    $g.Dispose()
    $rect = New-Object System.Drawing.Rectangle 0, 0, 3840, 2160
    $data = $b.LockBits($rect, [System.Drawing.Imaging.ImageLockMode]::ReadOnly,
                        [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $bytes = New-Object byte[] ($data.Stride * $data.Height)
    [System.Runtime.InteropServices.Marshal]::Copy($data.Scan0, $bytes, 0, $bytes.Length)
    $b.UnlockBits($data)
    $b.Dispose()
    return ,@($bytes, $data.Stride)
}

function SelEdges([int]$row) {
    $cur = GrabBytes
    $cb = $cur[0]; $cs = $cur[1]
    $bb = $script:baseBytes; $bs = $script:baseStride
    $first = -1; $last = -1
    for ($x = 0; $x -lt 3840; $x++) {
        $i = $row * $cs + $x * 4; $j = $row * $bs + $x * 4
        $du = 0; $dd = 0
        for ($k = 0; $k -lt 3; $k++) {
            $c = [int]$cb[$i+$k]; $base = [int]$bb[$j+$k]
            $du += [Math]::Abs($c - $base)
            $dd += [Math]::Abs($c - [int]($base * 0.4))
        }
        if ($du -le 12 -and $du -lt $dd) { if ($first -lt 0) { $first = $x }; $last = $x }
    }
    return "x=[$first,$last]"
}

Get-Process winshot -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 500
MoveTo 3000 1900
Start-Sleep -Milliseconds 400
$b0 = GrabBytes
$script:baseBytes = $b0[0]; $script:baseStride = $b0[1]

$p = Start-Process -FilePath 'D:\Project\winshot\x64\Debug\winshot.exe' -PassThru
Start-Sleep -Seconds 2

$sink = FindWindows 'WinShotSink'
if ($sink.Count -eq 0) { "no sink window"; exit 1 }
[void][W2]::PostMessage($sink[0], 0x8002, [IntPtr]::Zero, [IntPtr]::Zero)
Start-Sleep -Seconds 2

Drag 800 600 1400 1000
"after create (expect interior x=[800,1399]): $(SelEdges 800)"
"foreground: '$(TitleOf ([W2]::GetForegroundWindow()))'"

foreach ($k in @('{RIGHT}','{RIGHT}','+{RIGHT}','{RIGHT}','+{RIGHT}')) {
    [System.Windows.Forms.SendKeys]::SendWait($k)
    Start-Sleep -Milliseconds 400
    "  after $k -> $(SelEdges 800)  fg='$(TitleOf ([W2]::GetForegroundWindow()))'"
}

[System.Windows.Forms.SendKeys]::SendWait('{ESC}')
Start-Sleep -Seconds 1
"overlay windows after ESC: $((FindWindows 'WinShotOverlay').Count)"
"winshot still running: $([bool](Get-Process winshot -ErrorAction SilentlyContinue))"
