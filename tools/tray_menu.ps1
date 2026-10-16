# Drives the tray menu without needing the icon's screen position: WM_APP_TRAY is
# the callback Shell_NotifyIcon was installed with, and NIN_KEYSELECT carries the
# point in the same words the shell uses, so posting it opens the menu exactly as
# a right-click would. Then it checks the two items the user asked for actually do
# something — TrackPopupMenu with TPM_RETURNCMD returns the choice instead of
# sending WM_COMMAND, which is easy to get wrong and invisible until tried.
Add-Type -AssemblyName System.Drawing, System.Windows.Forms
Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class TM {
    public delegate bool EnumProc(IntPtr h, IntPtr l);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
    [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint msg, IntPtr w, IntPtr l);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint dx, uint dy, uint d, UIntPtr e);
    // EnumWindows skips menu popups, so the popup has to come from FindWindowEx.
    [DllImport("user32.dll")] public static extern IntPtr FindWindowEx(IntPtr parent, IntPtr childAfter, string cls, string title);
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int left, top, right, bottom; }
}
"@
$WM_APP_TRAY = 0x8001
$NIN_KEYSELECT = 0x401   # WM_USER + 1, NOTIFYICON_VERSION_4 numbering
$LEFTDOWN = 0x0002; $LEFTUP = 0x0004

function Find-Win([string]$title) {
    $found = New-Object System.Collections.ArrayList
    $cb = [TM+EnumProc] {
        param($h, $l)
        $t = New-Object System.Text.StringBuilder 256
        [void][TM]::GetWindowText($h, $t, 256)
        if ($t.ToString() -eq $title) { [void]$found.Add($h) }
        return $true
    }
    [void][TM]::EnumWindows($cb, [IntPtr]::Zero)
    return @($found)
}
function Menu-Wins() {
    $list = New-Object System.Collections.ArrayList
    $h = [TM]::FindWindowEx([IntPtr]::Zero, [IntPtr]::Zero, '#32768', $null)
    while ($h -ne [IntPtr]::Zero) {
        [void]$list.Add($h)
        $h = [TM]::FindWindowEx([IntPtr]::Zero, $h, '#32768', $null)
    }
    return , [array]$list
}
# The new popup, identified as the one that was not there before the post — other
# apps can have their own #32768 windows alive.
function Open-Menu([int]$x, [int]$y, [IntPtr]$sink) {
    $before = @(Menu-Wins)
    # event in the high word of lParam with the x in its low word, y in the high
    # word of wParam — the VERSION_4 packing OnTrayNotify reads.
    $lParam = [IntPtr](($NIN_KEYSELECT -shl 16) -bor ($x -band 0xFFFF))
    $wParam = [IntPtr](($y -band 0xFFFF) -shl 16)
    [void][TM]::PostMessage($sink, $WM_APP_TRAY, $wParam, $lParam)
    for ($i = 0; $i -lt 20; $i++) {
        Start-Sleep -Milliseconds 150
        $now = @(Menu-Wins)
        $new = @($now | Where-Object { $before -notcontains $_ })
        if ($new.Count) { return $new[0] }
    }
    return $null
}
function Grab-Menu([IntPtr]$m, [string]$path) {
    $r = New-Object TM+RECT
    [void][TM]::GetWindowRect($m, [ref]$r)
    $w = $r.right - $r.left; $hh = $r.bottom - $r.top
    $bmp = New-Object System.Drawing.Bitmap $w, $hh
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen([System.Drawing.Point]::new($r.left, $r.top),
                      [System.Drawing.Point]::Empty, $bmp.Size)
    $bmp.Save($path)
    $g.Dispose()
    return , @{ bmp = $bmp; rect = $r }
}
# Rows carrying label text, grouped into bands: separators and borders have no
# dark pixels, so the bands are exactly the clickable items. The threshold is
# loose because the labels are small anti-aliased glyphs on 240-gray; a strict
# one finds only the two densest items.
function Item-Bands($bmp) {
    $bands = @(); $cur = $null
    for ($y = 0; $y -lt $bmp.Height; $y++) {
        $dark = 0
        for ($x = 2; $x -lt $bmp.Width - 2; $x++) {
            $c = $bmp.GetPixel($x, $y)
            if (($c.R + $c.G + $c.B) -lt 600) { $dark++ }
        }
        if ($dark -ge 2) {
            if ($null -eq $cur) { $cur = @($y, $y) } else { $cur[1] = $y }
        } elseif ($null -ne $cur) {
            if ($cur[1] - $cur[0] -ge 4) { $bands += , $cur }
            $cur = $null
        }
    }
    if ($null -ne $cur -and $cur[1] - $cur[0] -ge 4) { $bands += , $cur }
    return , $bands
}
function Click-At([int]$x, [int]$y) {
    [void][TM]::SetCursorPos($x, $y)
    Start-Sleep -Milliseconds 200
    [void][TM]::mouse_event($LEFTDOWN, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 120
    [void][TM]::mouse_event($LEFTUP, 0, 0, 0, [UIntPtr]::Zero)
}

$fail = @()
Get-Process winshot -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 800
$p = Start-Process -FilePath 'D:\Project\winshot\x64\Debug\winshot.exe' -PassThru
Start-Sleep -Seconds 2
$sink = @(Find-Win 'WinShotSink')
if ($sink.Count -eq 0) { 'FAIL: no sink window'; exit 1 }

# --- the menu appears, and what it looks like ---------------------------------
$m = Open-Menu 1500 900 $sink[0]
if ($null -eq $m) { 'FAIL: posting NIN_KEYSELECT opened no menu'; exit 1 }
$shot = Grab-Menu $m 'D:\Project\winshot\obj\tray_menu.png'
$r = $shot.rect
"menu window: $m  rect x=$($r.left)..$($r.right) y=$($r.top)..$($r.bottom)"
"saved D:\Project\winshot\obj\tray_menu.png  ($($r.right - $r.left) x $($r.bottom - $r.top))"
$bands = Item-Bands $shot.bmp
"item bands (menu-relative y): $($bands.Count) -> $(($bands | ForEach-Object { "$($_[0])..$($_[1])" }) -join ' ')"
if ($bands.Count -ne 4) { $fail += "expected 4 text items (capture, startup, about, exit), got $($bands.Count)" }

# --- the first item: it starts a capture --------------------------------------
if ($bands.Count -ge 1) {
    $cy = $r.top + [int](($bands[0][0] + $bands[0][1]) / 2)
    $cx = $r.left + [int](($r.right - $r.left) / 2)
    "clicking the first item at ($cx,$cy)"
    Click-At $cx $cy
    Start-Sleep -Seconds 2
    $ov = @(Find-Win 'WinShotOverlay')
    "overlay windows after the first item: $($ov.Count)  (want 1)"
    if ($ov.Count -ne 1) { $fail += 'the first menu item did not start a capture' }
    if ($ov.Count -eq 1) {
        [void][TM]::SetCursorPos(1900, 1100)
        Start-Sleep -Milliseconds 300
        [void][System.Windows.Forms.SendKeys]::SendWait('{ESC}')
        Start-Sleep -Milliseconds 800
    }
}

# --- the last item: it exits the app ------------------------------------------
$m2 = Open-Menu 1500 900 $sink[0]
if ($null -eq $m2) { 'FAIL: no menu on the second open'; $fail += 'no menu the second time' }
else {
    $shot2 = Grab-Menu $m2 'D:\Project\winshot\obj\tray_menu2.png'
    $r2 = $shot2.rect
    $bands2 = Item-Bands $shot2.bmp
    if ($bands2.Count -ge 1) {
        $last = $bands2[$bands2.Count - 1]
        $cy2 = $r2.top + [int](($last[0] + $last[1]) / 2)
        $cx2 = $r2.left + [int](($r2.right - $r2.left) / 2)
        "clicking the last item at ($cx2,$cy2)"
        Click-At $cx2 $cy2
    }
    $shot2.bmp.Dispose()
}
Start-Sleep -Seconds 2
$alive = -not $p.HasExited
"winshot exited after the last item: $(-not $alive)  (want True)"
if ($alive) { $fail += 'the last menu item did not exit the app' }
$shot.bmp.Dispose()
Get-Process winshot -ErrorAction SilentlyContinue | Stop-Process -Force

if ($fail.Count) { "FAILURES: $($fail.Count)"; $fail | ForEach-Object { "  $_" } }
else { 'PASS' }
