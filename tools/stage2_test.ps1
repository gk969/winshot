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
    [DllImport("user32.dll")] public static extern bool PostMessageW(IntPtr h, uint msg, IntPtr w, IntPtr l);
}
"@

function Grab([string]$path) {
    $b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    $bmp = New-Object System.Drawing.Bitmap $b.Width, $b.Height
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen($b.Location, [System.Drawing.Point]::Empty, $bmp.Size)
    $bmp.Save($path)
    $g.Dispose()
    return $bmp
}

Get-Process winshot -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 400

[System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point(3000, 1500)
Start-Sleep -Milliseconds 300
$base = Grab 'D:\Project\winshot\obj\base.png'

$p = Start-Process -FilePath 'D:\Project\winshot\x64\Debug\winshot.exe' -PassThru
Start-Sleep -Seconds 2

$sink = New-Object System.Collections.ArrayList
$cb = [W2+EnumProc] {
    param($h, $l)
    $t = New-Object System.Text.StringBuilder 256
    [void][W2]::GetWindowText($h, $t, 256)
    if ($t.ToString() -eq 'WinShotSink') { [void]$sink.Add($h) }
    return $true
}
[void][W2]::EnumWindows($cb, [IntPtr]::Zero)
if ($sink.Count -eq 0) { "no sink window"; exit 1 }

# WM_APP + 2 = WM_APP_STARTCAPTURE
[void][W2]::PostMessage($sink[0], 0x8002, [IntPtr]::Zero, [IntPtr]::Zero)
Start-Sleep -Seconds 2

[System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point(3000, 1500)
Start-Sleep -Milliseconds 300
$shot = Grab 'D:\Project\winshot\obj\overlay.png'

$w = $base.Width; $h = $base.Height
"image ${w}x${h}"

# Summoning dims the whole screen — the default selection is the full screen and
# the dim covers it too, so the desktop goes dark the moment the hotkey lands.
# Every sampled pixel should therefore be base * (1 - 153/255) = base * 0.4,
# except the frame, the handles, the size label, the magnifier card and whatever
# the desktop itself did in the two seconds between the grabs.
function Pixels($bmp) {
    $rect = New-Object System.Drawing.Rectangle 0, 0, $bmp.Width, $bmp.Height
    $data = $bmp.LockBits($rect, [System.Drawing.Imaging.ImageLockMode]::ReadOnly,
                          [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $bytes = New-Object byte[] ($data.Stride * $data.Height)
    [System.Runtime.InteropServices.Marshal]::Copy($data.Scan0, $bytes, 0, $bytes.Length)
    $bmp.UnlockBits($data)
    return ,@($bytes, $data.Stride)
}

$ba = Pixels $base
$bb = Pixels $shot
$bytesA = $ba[0]; $strideA = $ba[1]
$bytesB = $bb[0]; $strideB = $bb[1]

# The magnifier card shows the un-dimmed still, so it is excluded rather than
# treated as a mismatch. Per-pixel equality against a grab taken two seconds
# earlier is not a usable assertion on a desktop that is animating — a playing
# video moves a quarter of the pixels — so the hard check is the mean: dimming
# every pixel by the same factor scales the mean by that factor no matter what
# individual pixels did.
$cardL = 2942; $cardR = 3059; $cardT = 1458; $cardB = 1604
$off = 0; $n = 0; $first = $null
$sumA = [double]0; $sumB = [double]0
for ($y = 6; $y -lt $h - 6; $y += 3) {
    $oa = $y * $strideA; $ob = $y * $strideB
    for ($x = 6; $x -lt $w - 6; $x += 3) {
        if ($x -ge $cardL -and $x -le $cardR -and $y -ge $cardT -and $y -le $cardB) {
            continue
        }
        $ia = $oa + $x * 4; $ib = $ob + $x * 4
        $n++
        $bad = $false
        for ($c = 0; $c -lt 3; $c++) {
            $av = [int]$bytesA[$ia + $c]; $bv = [int]$bytesB[$ib + $c]
            $sumA += $av; $sumB += $bv
            if ([Math]::Abs([Math]::Round($av * 0.4) - $bv) -gt 4) { $bad = $true }
        }
        if ($bad) {
            $off++
            if (-not $first) {
                $first = "($x,$y) base=$($bytesA[$ia+2]),$($bytesA[$ia+1]),$($bytesA[$ia]) shot=$($bytesB[$ib+2]),$($bytesB[$ib+1]),$($bytesB[$ib])"
            }
        }
    }
}
$ratio = if ($sumA -gt 0) { [Math]::Round($sumB / $sumA, 3) } else { 0 }
$pct = if ($n) { [Math]::Round(100.0 * $off / $n, 2) } else { 0 }
"mean brightness ratio = $ratio (want 0.4)"
"off the 0.4x dim model: $off of $n sampled pixels ($pct%)"
if ($first) { "first off-model: $first" }
"dim at summon: $(if ($ratio -ge 0.36 -and $ratio -le 0.44) {'OK'} else {'FAIL'})"

function CountWindows([string]$title) {
    $list = New-Object System.Collections.ArrayList
    $cb = [W2+EnumProc] {
        param($h, $l)
        $t = New-Object System.Text.StringBuilder 256
        [void][W2]::GetWindowText($h, $t, 256)
        if ($t.ToString() -eq $title) { [void]$list.Add($h) }
        return $true
    }
    [void][W2]::EnumWindows($cb, [IntPtr]::Zero)
    return $list.Count
}

# WM_APP + 4 = WM_APP_ENDCAPTURE (accepted)
[void][W2]::PostMessage($sink[0], 0x8004, [IntPtr]::Zero, [IntPtr]::Zero)
Start-Sleep -Seconds 1
"overlay windows after END: $(CountWindows 'WinShotOverlay')"
"winshot still running: $([bool](Get-Process winshot -ErrorAction SilentlyContinue))"

$base.Dispose(); $shot.Dispose()
