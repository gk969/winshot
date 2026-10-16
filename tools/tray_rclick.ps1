# Right-clicks the tray icon where it actually is on screen.
#
# tray_menu.ps1 posts NIN_KEYSELECT to the sink, which is the shape of the
# message but not the way the shell sends it: a real right click arrives as
# WM_CONTEXTMENU with the point in lParam, and it arrives twice (NIN_KEYSELECT
# and WM_CONTEXTMENU for the same click). Both bugs stayed invisible under a
# posted event, so this one drives the mouse.
#
# The icon is located from the pixels the shell drew, not from UIA: UIA hands
# back a point that can be the toolbar background beside the icon, and a click
# there opens the taskbar's own menu — which looks like a pass to a test that
# only asks "did a menu appear". Runs killed with Stop-Process never reach
# NIM_DELETE, so their icons stay behind as dead buttons; each candidate is
# tried in turn and only the live one answers with our four-item menu.
Add-Type -AssemblyName System.Drawing, System.Windows.Forms
Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class TR {
    public delegate bool EnumProc(IntPtr h, IntPtr l);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
    [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] public static extern IntPtr FindWindowEx(IntPtr parent, IntPtr after, string cls, string title);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")] public static extern bool GetCursorPos(out POINT p);
    [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint dx, uint dy, uint d, UIntPtr e);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int left, top, right, bottom; }
    [StructLayout(LayoutKind.Sequential)] public struct POINT { public int x, y; }
}
"@
$RIGHTDOWN = 0x0008; $RIGHTUP = 0x0010
$LEFTDOWN = 0x0002; $LEFTUP = 0x0004
# 开始截图, 开机启动, 关于, 退出 — the four rows that carry text.
$WANT_ITEMS = 4

function Find-Win([string]$title) {
    $found = New-Object System.Collections.ArrayList
    $cb = [TR+EnumProc] {
        param($h, $l)
        $t = New-Object System.Text.StringBuilder 256
        [void][TR]::GetWindowText($h, $t, 256)
        if ($t.ToString() -eq $title) { [void]$found.Add($h) }
        return $true
    }
    [void][TR]::EnumWindows($cb, [IntPtr]::Zero)
    return @($found)
}
function Menu-Wins() {
    $list = New-Object System.Collections.ArrayList
    $h = [TR]::FindWindowEx([IntPtr]::Zero, [IntPtr]::Zero, '#32768', $null)
    while ($h -ne [IntPtr]::Zero) {
        [void]$list.Add($h)
        $h = [TR]::FindWindowEx([IntPtr]::Zero, $h, '#32768', $null)
    }
    # A plain array: `,[array]` nests it, and a one-element result then coerces
    # to IntPtr by accident while a two-element one does not.
    return $list.ToArray()
}
# Centres of our icons in the tray strip, keyed on the red dot.
#
# Keying on the white field instead merges the icon with its neighbours: the
# monochrome system icons to the right are only a couple of pixels apart, so a
# run that starts on ours swallows them and its centre lands on one of them —
# which is why a right click there opened nothing. The dot is ~5 px across and
# only our icon has one, so it pins the centre exactly.
function Scan-Tray-Icons {
    $va = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    $x0 = $va.Right - 620; $x1 = $va.Right - 44      # stops short of the edge
    $y0 = $va.Bottom - 48; $y1 = $va.Bottom
    $w = $x1 - $x0; $h = $y1 - $y0
    $bmp = New-Object System.Drawing.Bitmap $w, $h
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen([System.Drawing.Point]::new($x0, $y0),
                      [System.Drawing.Point]::Empty, $bmp.Size)
    $g.Dispose()
    $bmp.Save('D:\Project\winshot\obj\tray_strip.png')

    $white = New-Object int[] $w
    $red = New-Object int[] $w
    for ($x = 0; $x -lt $w; $x++) {
        for ($y = 0; $y -lt $h; $y++) {
            $c = $bmp.GetPixel($x, $y)
            if ($c.R -gt 230 -and $c.G -gt 230 -and $c.B -gt 230) { $white[$x]++ }
            # The 0xFFFA373A dot: red with little green or blue.
            elseif ($c.R -gt 190 -and $c.G -lt 110 -and $c.B -lt 110) { $red[$x]++ }
        }
    }
    $bmp.Dispose()

    $runs = @(); $cur = $null; $gap = 0
    for ($x = 0; $x -lt $w; $x++) {
        if ($red[$x] -ge 3) {
            if ($null -eq $cur) { $cur = @($x, $x) } else { $cur[1] = $x }
            $gap = 0
        } elseif ($null -ne $cur) {
            $gap++
            if ($gap -gt 1) { $runs += , $cur; $cur = $null }
        }
    }
    if ($null -ne $cur) { $runs += , $cur }

    $out = @()
    foreach ($r in $runs) {
        # A dot is a handful of columns; a wider red stretch is something else.
        if ($r[1] - $r[0] -gt 10) { continue }
        $c = [int](($r[0] + $r[1]) / 2)
        # The dot sits in the middle of a white field, so the icon's edges are
        # a fixed distance either side. Requiring the field keeps a stray red
        # pixel on another icon from reading as ours: the neighbours with warm
        # pixels reach 8 here, ours 15.
        $field = 0
        for ($x = [Math]::Max(0, $c - 14); $x -le [Math]::Min($w - 1, $c + 14); $x++) {
            if ($white[$x] -ge 2) { $field++ }
        }
        if ($field -lt 12) { continue }
        $out += , @{ x = $x0 + $c; y = [int](($y0 + $y1) / 2)
                     span = "$($x0 + $r[0])..$($x0 + $r[1])"; dot = $field }
    }
    return $out
}
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
function Grab-Menu([IntPtr]$m, [string]$path) {
    $r = New-Object TR+RECT
    [void][TR]::GetWindowRect($m, [ref]$r)
    $w = $r.right - $r.left; $hh = $r.bottom - $r.top
    if ($w -le 0 -or $hh -le 0) { return $null }
    $bmp = New-Object System.Drawing.Bitmap $w, $hh
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen([System.Drawing.Point]::new($r.left, $r.top),
                      [System.Drawing.Point]::Empty, $bmp.Size)
    $bmp.Save($path)
    $g.Dispose()
    return , @{ bmp = $bmp; rect = $r }
}
function Click-At([int]$x, [int]$y, [uint32]$down, [uint32]$up) {
    [void][TR]::SetCursorPos($x, $y)
    Start-Sleep -Milliseconds 200
    [void][TR]::mouse_event($down, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 120
    [void][TR]::mouse_event($up, 0, 0, 0, [UIntPtr]::Zero)
}
# The menu that appeared since `before`, if any.
function Wait-New-Menu($before) {
    for ($i = 0; $i -lt 14; $i++) {
        Start-Sleep -Milliseconds 150
        $new = @( @(Menu-Wins) | Where-Object { $before -notcontains $_ })
        if ($new.Count) { return $new[0] }
    }
    return $null
}

$fail = @()
# Clear the strip before launching, so the icon found afterwards can only be the
# one this run installed. Runs killed with Stop-Process never reach NIM_DELETE
# and leave a button behind; the shell retires one per click on it.
Get-Process winshot -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 800
for ($round = 0; $round -lt 10; $round++) {
    $stale = @(Scan-Tray-Icons)
    if (-not $stale.Count) { break }
    "pruning round ${round}: $(($stale | ForEach-Object { $_.span }) -join '  ')"
    foreach ($c in $stale) {
        Click-At $c.x $c.y $LEFTDOWN $LEFTUP
        # A click that misses the button opens the taskbar's own menu, which then
        # covers the strip and makes the next scan read the strip wrong.
        [void][System.Windows.Forms.SendKeys]::SendWait('{ESC}')
    }
    Start-Sleep -Milliseconds 900
}
"tray strip after pruning: $(@(Scan-Tray-Icons).Count) icon-shaped pixels"

$p = Start-Process -FilePath 'D:\Project\winshot\x64\Debug\winshot.exe' -PassThru
Start-Sleep -Seconds 3
if (@(Find-Win 'WinShotSink').Count -eq 0) { 'FAIL: no sink window'; exit 1 }

# The shell animates the icon in and reorders the strip; an early scan comes
# back empty rather than partial.
$cands = @()
for ($i = 0; $i -lt 12; $i++) {
    # @() so one candidate stays an array; a bare hashtable would enumerate keys.
    $cands = @(Scan-Tray-Icons)
    if ($cands.Count) { break }
    Start-Sleep -Milliseconds 500
}
if (-not $cands.Count) {
    'FAIL: no icon-shaped pixel in the tray strip (see obj\tray_strip.png)'
    Get-Process winshot -ErrorAction SilentlyContinue | Stop-Process -Force
    exit 1
}
"icon candidates: $(($cands | ForEach-Object { $_.span }) -join '  ')  (strip saved to obj\tray_strip.png)"

# A menu left open by any app confines the cursor to its own rectangle, and
# SetCursorPos then silently moves the cursor to the nearest allowed point
# instead of failing. Every click would land on the wrong icon and the run would
# read as "the tray icon ignores right click", so say what it is and stop.
$ask = $cands[0].x
[void][TR]::SetCursorPos($ask, $cands[0].y)
Start-Sleep -Milliseconds 250
$gp = New-Object TR+POINT
[void][TR]::GetCursorPos([ref]$gp)
if ([Math]::Abs($gp.x - $ask) -gt 4) {
    $clipper = 'another app'
    foreach ($fm in @(Menu-Wins)) {
        $fp = [uint32]0
        [void][TR]::GetWindowThreadProcessId($fm, [ref]$fp)
        $n = (Get-Process -Id $fp -ErrorAction SilentlyContinue).ProcessName
        if ($n) { $clipper = $n; break }
    }
    "FAIL: the cursor will not reach x=$ask (it stopped at $($gp.x)) — $clipper has a"
    '      menu open that confines it. Close that menu and run this again.'
    Get-Process winshot -ErrorAction SilentlyContinue | Stop-Process -Force
    exit 1
}

# --- right-click until one answers with our menu ------------------------------
# A corpse answers nothing, and the taskbar's own menu has a different row count,
# so the four rows of ours are what single it out.
$m = $null; $shot = $null; $bands = $null; $used = $null
for ($round = 0; $round -lt 4 -and $null -eq $m; $round++) {
    if ($round) {
        Start-Sleep -Milliseconds 800
        $cands = @(Scan-Tray-Icons)
        "round ${round}: $(($cands | ForEach-Object { $_.span }) -join '  ')"
    }
    foreach ($c in $cands) {
        $before = @(Menu-Wins)
        Click-At $c.x $c.y $RIGHTDOWN $RIGHTUP
        $cand = Wait-New-Menu $before
        if ($null -eq $cand) { "  right click at x=$($c.x) opened nothing"; continue }
        $try = Grab-Menu $cand 'D:\Project\winshot\obj\tray_rclick.png'
        if ($null -eq $try) { continue }
        $b = Item-Bands $try.bmp
        "  right click at x=$($c.x) opened a menu with $($b.Count) text rows"
        if ($b.Count -eq $WANT_ITEMS) {
            $m = $cand; $shot = $try; $bands = $b; $used = $c
            break
        }
        # Not ours — the taskbar's own menu. Clear it and try the next one.
        [void][System.Windows.Forms.SendKeys]::SendWait('{ESC}')
        $try.bmp.Dispose()
        Start-Sleep -Milliseconds 300
    }
}
if ($null -eq $m) {
    'FAIL: no tray icon answered a real right click with our 4-item menu'
    Get-Process winshot -ErrorAction SilentlyContinue | Stop-Process -Force
    exit 1
}
$r = $shot.rect
"our menu: $m  rect x=$($r.left)..$($r.right) y=$($r.top)..$($r.bottom)"
"item bands (menu-relative y): $(($bands | ForEach-Object { "$($_[0])..$($_[1])" }) -join ' ')"
"saved D:\Project\winshot\obj\tray_rclick.png"

# The menu has to sit at the icon, not at a point made of handle bits.
$dx = [Math]::Abs($r.left - $used.x)
"menu left edge is $dx px from the icon (want under 120)"
if ($dx -gt 120) { $fail += "menu opened $dx px away from the icon" }

# --- dismiss it, then check nothing throws it back up -------------------------
# One right click delivers NIN_KEYSELECT and WM_CONTEXTMENU. If both open a menu
# the second queues behind the first's modal loop and reappears the moment the
# first closes, which is what a real right click did and a posted one did not.
$mine = @($m)
[void][System.Windows.Forms.SendKeys]::SendWait('{ESC}')
Start-Sleep -Milliseconds 400
$reopened = $null
for ($i = 0; $i -lt 6; $i++) {
    Start-Sleep -Milliseconds 250
    $now = @( @(Menu-Wins) | Where-Object { $mine -notcontains $_ })
    if ($now.Count) { $reopened = $now[0]; break }
}
"menu reopened after dismiss: $($null -ne $reopened)  (want False)"
if ($null -ne $reopened) { $fail += 'the menu reopened by itself after being dismissed' }

# --- the last item exits the app ----------------------------------------------
# The list has to be taken before the click: as a call argument it would be
# evaluated after it, and the menu that just opened would already be in it.
$before2 = @(Menu-Wins)
Click-At $used.x $used.y $RIGHTDOWN $RIGHTUP
$m2 = Wait-New-Menu $before2
if ($null -eq $m2) {
    'FAIL: no menu on the second right click'
    $fail += 'the tray icon stopped responding to right click'
} else {
    $shot2 = Grab-Menu $m2 'D:\Project\winshot\obj\tray_rclick2.png'
    $bands2 = Item-Bands $shot2.bmp
    if ($bands2.Count -ge 1) {
        $last = $bands2[$bands2.Count - 1]
        $cx = $shot2.rect.left + [int](($shot2.rect.right - $shot2.rect.left) / 2)
        $cy = $shot2.rect.top + [int](($last[0] + $last[1]) / 2)
        "clicking the last item at ($cx,$cy)"
        Click-At $cx $cy $LEFTDOWN $LEFTUP
    }
    $shot2.bmp.Dispose()
}
Start-Sleep -Seconds 2
$alive = -not $p.HasExited
"winshot exited after the last item: $(-not $alive)  (want True)"
if ($alive) { $fail += 'the last menu item did not exit the app' }
$shot.bmp.Dispose()
Get-Process winshot -ErrorAction SilentlyContinue | Stop-Process -Force

if ($fail.Count) { "FAILURES: $($fail.Count)"; $fail | ForEach-Object { "  $_" }; exit 1 }
'PASS'
