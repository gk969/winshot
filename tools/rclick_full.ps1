# 右键 with nothing selected yet is the shortcut for "copy the whole screen and
# get out". The catch is the click itself: the capture used to end on the button
# down, so the button up landed on whatever sat under the overlay, and the
# desktop answered it with its own context menu on top of the result. The action
# now runs on the up and the overlay swallows both, so nothing below ever sees
# the click.
Add-Type -AssemblyName System.Drawing, System.Windows.Forms
Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class RC {
    public delegate bool EnumProc(IntPtr h, IntPtr l);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
    [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint msg, IntPtr w, IntPtr l);
    [DllImport("user32.dll")] public static extern IntPtr WindowFromPoint(POINT p);
    [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint dx, uint dy, uint d, UIntPtr e);
    [StructLayout(LayoutKind.Sequential)] public struct POINT { public int x, y; }
}
"@

$RBUTTONDOWN = 0x0008; $RBUTTONUP = 0x0010

function Grab([string]$path) {
    $b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    $bmp = New-Object System.Drawing.Bitmap $b.Width, $b.Height
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen($b.Location, [System.Drawing.Point]::Empty, $bmp.Size)
    if ($path) { $bmp.Save($path) }
    $g.Dispose()
    return $bmp
}
function MoveTo([int]$x, [int]$y) {
    [System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point($x, $y)
    Start-Sleep -Milliseconds 200
}
function Find-Wins([string]$title) {
    $found = New-Object System.Collections.ArrayList
    $cb = [RC+EnumProc] {
        param($h, $l)
        $t = New-Object System.Text.StringBuilder 256
        [void][RC]::GetWindowText($h, $t, 256)
        if ($t.ToString() -eq $title) { [void]$found.Add($h) }
        return $true
    }
    [void][RC]::EnumWindows($cb, [IntPtr]::Zero)
    return $found.ToArray()
}
# Every visible top-level window, as title + class. A context menu is one of
# these, of class #32768, and it is the thing that must not appear.
function Top-Wins {
    $found = New-Object System.Collections.ArrayList
    $cb = [RC+EnumProc] {
        param($h, $l)
        if ([RC]::IsWindowVisible($h)) {
            $t = New-Object System.Text.StringBuilder 256
            $c = New-Object System.Text.StringBuilder 256
            [void][RC]::GetWindowText($h, $t, 256)
            [void][RC]::GetClassName($h, $c, 256)
            [void]$found.Add(@{ h = $h; title = $t.ToString(); cls = $c.ToString() })
        }
        return $true
    }
    [void][RC]::EnumWindows($cb, [IntPtr]::Zero)
    return $found.ToArray()
}
function Class-Name([IntPtr]$h) {
    $c = New-Object System.Text.StringBuilder 256
    [void][RC]::GetClassName($h, $c, 256)
    return $c.ToString()
}

$b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
$SW = $b.Width; $SH = $b.Height
$fail = @()

$at = @(1900, 1400)   # middle of the desktop, well clear of the taskbar
MoveTo $at[0] $at[1]
Start-Sleep -Milliseconds 400
$before = Grab 'D:\Project\winshot\obj\rc_before.png'

Get-Process winshot -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 600
$proc = Start-Process -FilePath 'D:\Project\winshot\x64\Debug\winshot.exe' -PassThru
Start-Sleep -Seconds 2
$sink = @(Find-Wins 'WinShotSink')
if ($sink.Count -eq 0) { 'FAIL: no sink window'; exit 1 }
[void][RC]::PostMessage($sink[0], 0x8002, [IntPtr]::Zero, [IntPtr]::Zero)
Start-Sleep -Seconds 2
if (@(Find-Wins 'WinShotOverlay').Count -eq 0) { 'FAIL: the summon left no overlay'; exit 1 }

# Nothing has been selected: the default region is the whole screen, which is
# exactly when a right click means "copy it all and close".
MoveTo $at[0] $at[1]
[void][RC]::mouse_event($RBUTTONDOWN, 0, 0, 0, [UIntPtr]::Zero)
Start-Sleep -Milliseconds 150
[void][RC]::mouse_event($RBUTTONUP, 0, 0, 0, [UIntPtr]::Zero)
Start-Sleep -Milliseconds 1200

"overlay after the right click: $(@(Find-Wins 'WinShotOverlay').Count) (want 0)"
if (@(Find-Wins 'WinShotOverlay').Count -gt 0) {
    $fail += 'the right click left the capture up'
}

# The menu, if the desktop saw the click. Checked twice: by class among the
# top-level windows, and at the point the click landed.
$menus = @(Top-Wins | Where-Object { $_.cls -eq '#32768' })
"visible #32768 menu windows: $($menus.Count)"
foreach ($m in $menus) { "  menu: '$($m.title)' class=$($m.cls)" }
if ($menus.Count -gt 0) {
    $fail += "the right click reached the window under the overlay and opened a menu: $(($menus | ForEach-Object { "'$($_.title)'" }) -join ' ')"
}
$pt = New-Object RC+POINT; $pt.x = $at[0]; $pt.y = $at[1]
$under = [RC]::WindowFromPoint($pt)
$cls = if ($under -ne [IntPtr]::Zero) { Class-Name $under } else { '(none)' }
"window under $at is class '$cls'"
if ($cls -eq '#32768') { $fail += "a context menu is open over $at after the right click" }

# And what it copied: the whole screen, pixel for pixel.
$do = [System.Windows.Forms.Clipboard]::GetDataObject()
$fmts = if ($do) { $do.GetFormats() -join ', ' } else { '(none)' }
"clipboard formats: $fmts"
$clip = $null
if ($do -and $do.GetDataPresent([System.Windows.Forms.DataFormats]::Bitmap)) {
    $clip = $do.GetData([System.Windows.Forms.DataFormats]::Bitmap)
}
if (-not $clip) {
    'FAIL: the right click put no image on the clipboard'
    exit 1
}
"clipboard image: $($clip.Width) x $($clip.Height)  (want $SW x $SH)"
if ($clip.Width -ne $SW -or $clip.Height -ne $SH) {
    $fail += "the clipboard holds $($clip.Width)x$($clip.Height), want the whole screen $SW x $SH"
}
$diff = 0; $seen = 0; $where = ''
foreach ($fy in @(0.1, 0.3, 0.5, 0.7, 0.9)) {
    foreach ($fx in @(0.1, 0.3, 0.5, 0.7, 0.9)) {
        $x = [int]($SW * $fx); $y = [int]($SH * $fy)
        if ($x -ge $clip.Width -or $y -ge $clip.Height) { continue }
        $c1 = $clip.GetPixel($x, $y); $c2 = $before.GetPixel($x, $y)
        $seen++
        if (([Math]::Abs($c1.R - $c2.R) + [Math]::Abs($c1.G - $c2.G) +
             [Math]::Abs($c1.B - $c2.B)) -gt 24) {
            $diff++
            $where += " $x,$y"
        }
    }
}
"clipboard vs the screen before the summon: $diff of $seen samples differ$where"
# One sample is allowed to disagree. The nine points are fixed on a live desktop,
# and a caret sitting on one of them moves: measured on 2026-10-21 with winshot not
# even running, 2688,1944 read 21,21,21 and then 61,61,59 three seconds later. What
# this is looking for is the copy carrying the dimmed overlay or the selection
# frame, and that differs at every point, not one.
if ($seen -gt 0 -and $diff -gt 1) {
    $fail += "$diff of $seen clipboard pixels are not what was on the screen, so it did not copy the screen"
}
$clip.Dispose(); $before.Dispose()

if (-not $proc.HasExited) { $proc.Kill() }
if ($fail.Count) { "FAILURES: $($fail.Count)"; $fail | ForEach-Object { "  $_" }; exit 1 }
'PASS'
