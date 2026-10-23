# A pinned image is HTCAPTION everywhere except its close badge, so a right click
# on the image is a non-client message: the menu has to come from
# WM_NCRBUTTONDOWN, and it has to be the down, because for a caption hit the
# default handler runs its own modal system-menu tracking loop from the down and
# the up never reaches the window at all. Wired to the client WM_RBUTTONDOWN only,
# the menu shows in that 22px badge and nowhere else -- which is what this pins.
#
# Also pinned: an outside click dismisses the menu (TrackPopupMenu leaves it up for
# a window that is not foreground, and a pin sits on the desktop while some other
# app holds the focus), and the two rows that need no dialog do their work. The
# save row is not clicked here -- it opens the save dialog, which save_format
# already drives, and the pin calls the same SaveWithDialog.
#
# The menu is read from its pixels, not from GetMenu: a #32768 window returns 0
# from GetMenu, so there is no item handle to query. Three text row bands is our
# menu (three items, and a separator is too thin to be a row); the system menu the
# default handler could have shown instead has six.
Add-Type -AssemblyName System.Drawing, System.Windows.Forms
Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class PR {
    public delegate bool EnumProc(IntPtr h, IntPtr l);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
    [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr p, EnumProc cb, IntPtr l);
    [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint msg, IntPtr w, IntPtr l);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern IntPtr FindWindowEx(IntPtr parent, IntPtr after, string cls, string title);
    [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint dx, uint dy, uint d, UIntPtr e);
    [DllImport("user32.dll")] public static extern bool OpenClipboard(IntPtr h);
    [DllImport("user32.dll")] public static extern bool EmptyClipboard();
    [DllImport("user32.dll")] public static extern bool CloseClipboard();
    [DllImport("user32.dll")] public static extern bool IsClipboardFormatAvailable(uint fmt);
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int left, top, right, bottom; }
}
"@

$LEFTDOWN = 0x0002; $LEFTUP = 0x0004
$RIGHTDOWN = 0x0008; $RIGHTUP = 0x0010
$CF_BITMAP = 2; $CF_DIB = 8
$WANT_ROWS = 3

function MoveTo([int]$x, [int]$y) {
    [System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point($x, $y)
    Start-Sleep -Milliseconds 90
}
function Drag([int]$x1, [int]$y1, [int]$x2, [int]$y2) {
    MoveTo $x1 $y1
    [void][PR]::mouse_event($LEFTDOWN, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 120
    for ($i = 1; $i -le 12; $i++) {
        MoveTo ([int]($x1 + ($x2-$x1) * $i / 12)) ([int]($y1 + ($y2-$y1) * $i / 12))
    }
    Start-Sleep -Milliseconds 150
    [void][PR]::mouse_event($LEFTUP, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 350
}
function Click([int]$x, [int]$y) {
    MoveTo $x $y
    [void][PR]::mouse_event($LEFTDOWN, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 120
    [void][PR]::mouse_event($LEFTUP, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 350
}
function RightClick([int]$x, [int]$y) {
    MoveTo $x $y
    [void][PR]::mouse_event($RIGHTDOWN, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 120
    [void][PR]::mouse_event($RIGHTUP, 0, 0, 0, [UIntPtr]::Zero)
}
function Find-Wins([string]$title) {
    $found = New-Object System.Collections.ArrayList
    $cb = [PR+EnumProc] {
        param($h, $l)
        $t = New-Object System.Text.StringBuilder 256
        [void][PR]::GetWindowText($h, $t, 256)
        if ($t.ToString() -eq $title) { [void]$found.Add($h) }
        return $true
    }
    [void][PR]::EnumWindows($cb, [IntPtr]::Zero)
    return $found.ToArray()
}
function Rect-Of([IntPtr]$h) {
    $r = New-Object PR+RECT
    [void][PR]::GetWindowRect($h, [ref]$r)
    return $r
}
# Popup menus are #32768 top-level windows. Another app can have one of its own
# up, so the owning process is part of the match.
function Menu-Wins([int]$ownerPid) {
    $found = @()
    $h = [PR]::FindWindowEx([IntPtr]::Zero, [IntPtr]::Zero, '#32768', $null)
    while ($h -ne [IntPtr]::Zero) {
        $op = [uint32]0
        [void][PR]::GetWindowThreadProcessId($h, [ref]$op)
        if ([int]$op -eq $ownerPid) { $found += $h }
        $h = [PR]::FindWindowEx([IntPtr]::Zero, $h, '#32768', $null)
    }
    return $found
}
function Wait-Menu([int]$ownerPid) {
    for ($i = 0; $i -lt 20; $i++) {
        $m = @(Menu-Wins $ownerPid)
        if ($m.Count -gt 0) { return $m[0] }
        Start-Sleep -Milliseconds 100
    }
    return [IntPtr]::Zero
}
function Wait-No-Menu([int]$ownerPid) {
    for ($i = 0; $i -lt 20; $i++) {
        if (@(Menu-Wins $ownerPid).Count -eq 0) { return $true }
        Start-Sleep -Milliseconds 100
    }
    return $false
}
# Rows of the menu that carry text, in menu-relative y. A row counts when it has
# two dark pixels, a band when it runs four rows or more, so the separator and the
# menu's own 1px border do not become rows of their own.
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
# The open menu's rect and its text rows. Saves what it looks like for the log.
function Menu-Read([IntPtr]$m, [string]$shot) {
    $r = Rect-Of $m
    $w = $r.right - $r.left; $hh = $r.bottom - $r.top
    if ($w -le 0 -or $hh -le 0) { return $null }
    $bmp = New-Object System.Drawing.Bitmap $w, $hh
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen([System.Drawing.Point]::new($r.left, $r.top),
                      [System.Drawing.Point]::Empty, $bmp.Size)
    if ($shot) { $bmp.Save($shot) }
    $g.Dispose()
    $bands = Item-Bands $bmp
    $bmp.Dispose()
    return [pscustomobject]@{ rect = $r; bands = $bands }
}
function Clear-Clipboard {
    if (-not [PR]::OpenClipboard([IntPtr]::Zero)) { return $false }
    [void][PR]::EmptyClipboard()
    [void][PR]::CloseClipboard()
    return $true
}

$sel = @(800, 600, 1500, 1050)
$fail = @()

MoveTo 3000 1900
Start-Sleep -Milliseconds 400
Get-Process winshot -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 600
$proc = Start-Process -FilePath 'D:\Project\winshot\x64\Debug\winshot.exe' -PassThru
Start-Sleep -Seconds 2

$sink = @(Find-Wins 'WinShotSink')
if ($sink.Count -eq 0) { 'FAIL: no sink window'; exit 1 }
[void][PR]::PostMessage($sink[0], 0x8002, [IntPtr]::Zero, [IntPtr]::Zero)
Start-Sleep -Seconds 2

Drag $sel[0] $sel[1] $sel[2] $sel[3]

$ov = @(Find-Wins 'WinShotOverlay')
if ($ov.Count -eq 0) { 'FAIL: no overlay window'; exit 1 }
$kids = New-Object System.Collections.ArrayList
$cb2 = [PR+EnumProc] {
    param($h, $l)
    $t = New-Object System.Text.StringBuilder 256
    [void][PR]::GetWindowText($h, $t, 256)
    if ($t.ToString() -eq 'WinShotToolbar') { [void]$kids.Add($h) }
    return $true
}
[void][PR]::EnumChildWindows($ov[0], $cb2, [IntPtr]::Zero)
if ($kids.Count -eq 0) { 'FAIL: no toolbar window under the overlay'; exit 1 }
$tr = Rect-Of $kids[0]
$scale = ($tr.bottom - $tr.top) / 32.0
"toolbar ($($tr.left),$($tr.top))..($($tr.right),$($tr.bottom)) scale=$scale"
if ($scale -lt 0.5 -or $scale -gt 4) { 'FAIL: implausible toolbar height'; exit 1 }
$cell = [int][Math]::Round(27 * $scale)
$sep = [int][Math]::Round(14 * $scale)
$pad = [int][Math]::Round(4 * $scale)
Click ($tr.left + $pad + 10 * $cell + $sep + [int]($cell / 2)) ([int](($tr.top + $tr.bottom) / 2))
Start-Sleep -Milliseconds 800

$pins = @(Find-Wins 'WinShotPin')
"pin windows: $($pins.Count)"
if ($pins.Count -ne 1) { 'FAIL: the pin did not appear'; exit 1 }
$pin = $pins[0]
$r = Rect-Of $pin
$cx = [int](($r.left + $r.right) / 2); $cy = [int](($r.top + $r.bottom) / 2)
"pin ($($r.left),$($r.top))..($($r.right),$($r.bottom)) centre ($cx,$cy)"
# A point on the image, clear below the menu (which grows downward from the press,
# some 80px of it), used to dismiss it without leaving the pin. Clamped to the pin
# because the point has to stay on the image for the click to be an outside click
# on the menu rather than a click on the desktop.
$dx = $cx; $dy = [Math]::Min($cy + 260, $r.bottom - 12)

# --- round 1: a right click on the image itself ------------------------------
RightClick $cx $cy
$menu = Wait-Menu $proc.Id
if ($menu -eq [IntPtr]::Zero) {
    'FAIL: right-clicking the middle of the pin brought up no menu at all'
    if (-not $proc.HasExited) { $proc.Kill() }
    'FAILURES: 1'; exit 1
}
$m1 = Menu-Read $menu 'D:\Project\winshot\obj\pr_menu.png'
if (-not $m1) {
    'FAIL: the menu window has no area to read'
    if (-not $proc.HasExited) { $proc.Kill() }
    'FAILURES: 1'; exit 1
}
$mr = $m1.rect
"menu ($($mr.left),$($mr.top))..($($mr.right),$($mr.bottom)) rows=$($m1.bands.Count) bands=$(($m1.bands | ForEach-Object { "$($_[0])..$($_[1])" }) -join ' ')"
if ($m1.bands.Count -ne $WANT_ROWS) {
    $fail += "the menu over the pin has $($m1.bands.Count) text rows, want $WANT_ROWS"
}
# TPM_TOPALIGN | TPM_LEFTALIGN | TPM_RIGHTBUTTON anchors the menu's left edge and
# top edge to the press, so it grows down-right and leaves the patch of screen the
# right click was aiming at. The top edge is the one that says which way it opens:
# bottom-aligned it would sit a whole menu height above the press.
if ([Math]::Abs($mr.left - $cx) -gt 40 -or [Math]::Abs($mr.top - $cy) -gt 40) {
    $fail += "the menu is not anchored at the press (menu ($($mr.left),$($mr.top)), press ($cx,$cy))"
}

# --- round 2: an outside click dismisses it, pin survives --------------------
Click $dx $dy
if (-not (Wait-No-Menu $proc.Id)) {
    $fail += 'a left click outside the menu left it up (the pin is not foreground when the user clicks it)'
}
if (@(Find-Wins 'WinShotPin').Count -ne 1) { $fail += 'the outside click closed the pin' }
"after the outside click: menus=$(@(Menu-Wins $proc.Id).Count) pins=$(@(Find-Wins 'WinShotPin').Count)"

# --- round 3: the close badge, the one HTCLIENT spot, gives the same menu ----
$ux = [int]($r.right - 5 - 11); $uy = [int]($r.top + 5 + 11)
RightClick $ux $uy
$menu = Wait-Menu $proc.Id
if ($menu -eq [IntPtr]::Zero) {
    $fail += 'right-clicking the close badge brought up no menu'
} else {
    $m3 = Menu-Read $menu ''
    if (-not $m3) {
        $fail += 'the close badge menu has no area to read'
    } else {
        $r3 = $m3.rect
        "the close badge at ($ux,$uy): ($($r3.left),$($r3.top))..($($r3.right),$($r3.bottom)) rows=$($m3.bands.Count)"
        if ($m3.bands.Count -ne $WANT_ROWS) {
            $fail += "the menu over the close badge has $($m3.bands.Count) text rows, want $WANT_ROWS"
        }
        # Same menu, so same size -- only the anchor moves.
        if (($r3.right - $r3.left) -ne ($mr.right - $mr.left) -or
            ($r3.bottom - $r3.top) -ne ($mr.bottom - $mr.top)) {
            $fail += "the two menus differ in size ($($mr.right - $mr.left)x$($mr.bottom - $mr.top) vs $($r3.right - $r3.left)x$($r3.bottom - $r3.top))"
        }
    }
    Click $dx $dy
    [void](Wait-No-Menu $proc.Id)
}

# --- round 4: the copy row puts the pin's bitmap on the clipboard ------------
if (-not (Clear-Clipboard)) { $fail += 'could not empty the clipboard to test the copy row' }
RightClick $cx $cy
$menu = Wait-Menu $proc.Id
if ($menu -eq [IntPtr]::Zero) {
    $fail += 'round 4: no menu over the pin'
} else {
    $m4 = Menu-Read $menu ''
    if ($m4.bands.Count -lt 1) {
        $fail += 'round 4: the menu has no row to click'
    } else {
        $rx = [int](($m4.rect.left + $m4.rect.right) / 2)
        $ry = $m4.rect.top + [int](($m4.bands[0][0] + $m4.bands[0][1]) / 2)
        "clicking the copy row at ($rx,$ry)"
        Click $rx $ry
        [void](Wait-No-Menu $proc.Id)
        $dib = [PR]::IsClipboardFormatAvailable($CF_DIB)
        $bmp2 = [PR]::IsClipboardFormatAvailable($CF_BITMAP)
        "clipboard after the copy row: CF_DIB=$dib CF_BITMAP=$bmp2"
        if (-not $dib) { $fail += 'the copy row put no CF_DIB on the clipboard' }
        if (-not $bmp2) { $fail += 'the copy row put no CF_BITMAP on the clipboard' }
        if (@(Find-Wins 'WinShotPin').Count -ne 1) { $fail += 'the copy row closed the pin' }
    }
}

# --- round 5: the last row closes the pin ------------------------------------
RightClick $cx $cy
$menu = Wait-Menu $proc.Id
if ($menu -eq [IntPtr]::Zero) {
    $fail += 'round 5: no menu over the pin'
} else {
    $m5 = Menu-Read $menu ''
    $last = $m5.bands.Count - 1
    if ($last -lt 0) {
        $fail += 'round 5: the menu has no row to click'
    } else {
        $rx = [int](($m5.rect.left + $m5.rect.right) / 2)
        $ry = $m5.rect.top + [int](($m5.bands[$last][0] + $m5.bands[$last][1]) / 2)
        "clicking the close row at ($rx,$ry)"
        Click $rx $ry
        Start-Sleep -Milliseconds 600
        $left = @(Find-Wins 'WinShotPin').Count
        "pin windows after the close row: $left (want 0)"
        if ($left -ne 0) { $fail += 'the close row did not close the pin' }
    }
}

if (-not $proc.HasExited) { $proc.Kill() }
if ($fail.Count) { "FAILURES: $($fail.Count)"; $fail | ForEach-Object { "  $_" }; exit 1 }
'PASS'
