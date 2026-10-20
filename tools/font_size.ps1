# The 字号 picker used to be six sizes, and picking one changed only the next
# label: ShapeText carried its font from the constructor with no setter, and
# ResolvePopup wrote Style().fontSize and closed the list without looking back.
# The list is now 8..32 in thirteen rows, and a row picked while a label is
# selected or being typed into resizes that label on the spot.
#
# Both paths are measured off the screen rather than from the shape, because the
# whole point is what the user sees without doing anything else:
#
#   selected   click the label, pick a row, grab -> the glyphs are bigger
#   editing    double-click, pick a row, grab -> bigger, with the edit still open
#
# The glyph height comes from the rows that carry ink in the label's box. The
# text is one line of Ws, so it is one band, and its height tracks the font's cap
# height: about 13px at 18, 23 at 32, 6 at 8. Ratios, not absolutes - the exact
# figure belongs to the face, and the claim is only that the size followed the
# picker.
#
# The dropdown is the overlay's, not a window: it hangs 2px under the 字号 box,
# is as wide as it, and is 13 rows of 20px. Its geometry is therefore arithmetic
# off the property bar's rect, which is a real window (WinShotPropBar).
Add-Type -AssemblyName System.Drawing, System.Windows.Forms
Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class FSZ {
    public delegate bool EnumProc(IntPtr h, IntPtr l);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
    [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr p, EnumProc cb, IntPtr l);
    [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint msg, IntPtr w, IntPtr l);
    [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint dx, uint dy, uint d, UIntPtr e);
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int left, top, right, bottom; }
}
"@

$LEFTDOWN = 0x0002; $LEFTUP = 0x0004
# tb::kFontBoxX/W/H, kFontRow, kGap, kFontArrow and the 13-row count, at 100%.
$FONT_L = 30; $FONT_R = 76; $FONT_T = 7; $FONT_B = 30
$ROW = 20; $GAP = 2

function Grab([string]$path) {
    $b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    $bmp = New-Object System.Drawing.Bitmap $b.Width, $b.Height
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen($b.Location, [System.Drawing.Point]::Empty, $bmp.Size)
    if ($path) { $bmp.Save($path) }
    $g.Dispose()
    return $bmp
}
# Absolute mouse_event, and divide by 3839/2159 rather than the pixel count: the
# pointer's 0..65535 range maps onto 0..3839, so this is the exact inverse.
function MoveTo([int]$x, [int]$y) {
    [void][FSZ]::mouse_event(0x8001, [uint32][int][Math]::Round(65535 * $x / 3839),
                             [uint32][int][Math]::Round(65535 * $y / 2159), 0,
                             [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 90
}
function Down { [void][FSZ]::mouse_event($LEFTDOWN, 0, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 150 }
function Up { [void][FSZ]::mouse_event($LEFTUP, 0, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 350 }
function Walk([int]$x1, [int]$y1, [int]$x2, [int]$y2, [int]$steps) {
    for ($i = 1; $i -le $steps; $i++) {
        MoveTo ([int]($x1 + ($x2-$x1) * $i / $steps)) ([int]($y1 + ($y2-$y1) * $i / $steps))
    }
}
function Drag([int]$x1, [int]$y1, [int]$x2, [int]$y2) {
    MoveTo $x1 $y1; Down; Walk $x1 $y1 $x2 $y2 20; Up
}
function Click([int]$x, [int]$y) { MoveTo $x $y; Down; Up }
function DblClick([int]$x, [int]$y) {
    MoveTo $x $y
    [void][FSZ]::mouse_event($LEFTDOWN, 0, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 60
    [void][FSZ]::mouse_event($LEFTUP, 0, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 60
    [void][FSZ]::mouse_event($LEFTDOWN, 0, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 60
    [void][FSZ]::mouse_event($LEFTUP, 0, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 450
}
# Not `Type`: an alias for Get-Content beats a function of the same name.
function Keys([string]$s) { [void][System.Windows.Forms.SendKeys]::SendWait($s) }
function Find-Wins([string]$title) {
    $found = New-Object System.Collections.ArrayList
    $cb = [FSZ+EnumProc] {
        param($h, $l)
        $t = New-Object System.Text.StringBuilder 256
        [void][FSZ]::GetWindowText($h, $t, 256)
        if ($t.ToString() -eq $title) { [void]$found.Add($h) }
        return $true
    }
    [void][FSZ]::EnumWindows($cb, [IntPtr]::Zero)
    return $found.ToArray()
}
function Find-Kids([IntPtr]$parent, [string]$title) {
    $found = New-Object System.Collections.ArrayList
    $cb = [FSZ+EnumProc] {
        param($h, $l)
        $t = New-Object System.Text.StringBuilder 256
        [void][FSZ]::GetWindowText($h, $t, 256)
        if ($t.ToString() -eq $title -and [FSZ]::IsWindowVisible($h)) { [void]$found.Add($h) }
        return $true
    }
    [void][FSZ]::EnumChildWindows($parent, $cb, [IntPtr]::Zero)
    return $found.ToArray()
}
function Rect-Of([IntPtr]$h) {
    $r = New-Object FSZ+RECT
    [void][FSZ]::GetWindowRect($h, [ref]$r)
    return $r
}
$ov = $null
function Editor() {
    $e = @(Find-Kids $ov[0] 'WinShotTextEditor')
    if ($e.Count -eq 0) { return $null }
    return $e[0]
}
function Slot([int]$i) {
    $t = @(Find-Kids $ov[0] 'WinShotToolbar')
    if ($t.Count -eq 0) { return $null }
    $tr = Rect-Of $t[0]
    $s = ($tr.bottom - $tr.top) / 32.0
    $cell = [int][Math]::Round(27 * $s); $pad = [int][Math]::Round(4 * $s)
    return @(($tr.left + $pad + [int]($cell / 2) + $i * $cell),
             [int](($tr.top + $tr.bottom) / 2))
}
# The 字号 box's down-arrow strip, in screen coords. The box is 46px wide and the
# arrow owns the last 16; the rest becomes the typed number, so a script that
# means the list has to press on the arrow. A hashtable rather than a point plus
# the bar's rect: a function's output is collected, and a two-element array whose
# first element is itself an array is exactly the shape that goes wrong.
function Font-Bar() {
    $b = @(Find-Kids $ov[0] 'WinShotPropBar')
    if ($b.Count -eq 0) { return $null }
    $r = Rect-Of $b[0]
    return @{ x = ($r.left + $FONT_R - 8); y = [int](($r.top + $r.bottom) / 2);
              bar = $r }
}
# The list hangs 2px under the 字号 box, not under the bar: the box stops 7px
# short of the bar's bottom edge, so measuring off the bar puts every row 7px low.
function List-Top($f) { return ($f.bar.top + $FONT_B + $GAP) }
# Row i of the list, which is as wide as the box and 13 rows of 20px tall.
function Row-Point([int]$i) {
    $f = Font-Bar
    return @($f.x, ((List-Top $f) + $i * $ROW + [int]($ROW / 2)))
}
# The list is the overlay's, not a window, and it starts closed: a row has to be
# opened before it can be pressed, and it closes again once one is picked, so
# every pick opens it afresh. Without proof it came up, a press that lands on the
# bare canvas outside the 选区 silently deselects the label and the next
# measurement reads a size change that was never asked for.
#
# The proof is the card's white, counted over all thirteen rows rather than read
# at one point: the row for the current size is filled accent blue, so a single
# sample can land on the highlight and report a list that is open as closed. The
# list hangs below the 选区, where the overlay has already put its 0.4 dim, and
# dimmed pixels top out near 153 — so thirteen samples that read near-white can
# only be the card.
function Open-FontList() {
    $f = Font-Bar
    Click $f.x $f.y
    Start-Sleep -Milliseconds 350
    $top = List-Top $f
    $g = Grab ''
    $white = 0
    for ($i = 0; $i -lt 13; $i++) {
        $c = $g.GetPixel($f.x, ($top + $i * $ROW + [int]($ROW / 2)))
        if ($c.R -gt 235 -and $c.G -gt 235 -and $c.B -gt 235) { $white++ }
    }
    $g.Dispose()
    return ($white -ge 12)
}
# Two presses: open, then the row. False when the list never appeared, which is
# the difference between a size that did not take effect and one never asked for.
function Pick-Row([int]$i) {
    if (-not (Open-FontList)) { return $false }
    $r = Row-Point $i
    Click $r[0] $r[1]
    return $true
}
# The selected label's box height, from the red frame around it, plus its ink rows
# and centre. A hashtable: a function's output is collected, and returning several
# values is how a one-element array gets silently unrolled.
function Frame-Height([int]$x, [int]$y) {
    MoveTo 2300 1800; Start-Sleep -Milliseconds 400
    $g = Grab ''
    $f = Frame-Box $g $x $y
    if (-not $f) { $g.Dispose(); return $null }
    $n = (Ink-Rows $g ($f.l + 4) ($f.t + 4) ($f.r - 5) ($f.b - 5)).n
    $g.Dispose()
    return @{ h = ($f.b - $f.t + 1); n = $n; cx = [int](($f.l + $f.r) / 2);
              cy = [int](($f.t + $f.b) / 2) }
}
# Press the digits half of the 字号 box, type, and press Enter. The box is 46px
# wide and the ▼ owns the last 16, so the digits half is bar-local 30..60; the
# input box selects its contents as it opens, so the first digit replaces the old
# size rather than appending to it.
function Type-Size([string]$v) {
    $f = Font-Bar
    Click ($f.bar.left + $FONT_L + 15) $f.y
    Start-Sleep -Milliseconds 300
    Keys $v
    Start-Sleep -Milliseconds 200
    Keys '{ENTER}'
    Start-Sleep -Milliseconds 500
}
# The label's own box. While editing that is the input window inflated by the
# 4px inset it keeps from the box so the eight markers stay outside it; a selected
# label has no window, so the red frame 2px outside the box is the outline.
function Edit-Box([IntPtr]$h) {
    $r = Rect-Of $h
    $r.left -= 4; $r.top -= 4; $r.right += 4; $r.bottom += 4
    return $r
}
function Frame-Box($bmp, [int]$x, [int]$y) {
    # The frame is stroked 1px at the box inflated by 2, so the outermost red
    # pixel run around (x,y) is box.left-2 .. box.right+1.
    $l = -1; $t = -1; $r = -1; $b = -1
    # Wide enough for the frame after 18 -> 32, which is a third taller and whose
    # left edge sits further left than the scan would otherwise reach.
    for ($yy = $y - 90; $yy -le $y + 170; $yy++) {
        for ($xx = $x - 170; $xx -le $x + 300; $xx++) {
            if (IsInk ($bmp.GetPixel($xx, $yy))) {
                if ($l -lt 0 -or $xx -lt $l) { $l = $xx }
                if ($xx -gt $r) { $r = $xx }
                if ($t -lt 0 -or $yy -lt $t) { $t = $yy }
                if ($yy -gt $b) { $b = $yy }
            }
        }
    }
    if ($l -lt 0) { return $null }
    return @{ l = $l; t = $t; r = $r; b = $b }
}
# The default ink is tb::kPalette[10] = 0xFFF73840.
function IsInk($c) { return ($c.R -gt 190 -and $c.G -lt 120 -and $c.B -lt 130) }
# Rows carrying ink inside [l,t..r,b]: the height of one line of glyphs.
function Ink-Rows($bmp, [int]$l, [int]$t, [int]$r, [int]$b) {
    $rows = 0; $first = -1; $last = -1
    for ($y = $t; $y -le $b; $y++) {
        $hit = $false
        for ($x = $l; $x -le $r; $x++) { if (IsInk ($bmp.GetPixel($x, $y))) { $hit = $true; break } }
        if ($hit) { $rows++; if ($first -lt 0) { $first = $y }; $last = $y }
    }
    return @{ n = $rows; t = $first; b = $last }
}
$fail = @()
# Stopping early has to still report what went wrong: several of these bail out
# after a measured step already failed, and a bare exit hides that reason.
function Bail([string]$msg) {
    if ($proc -and -not $proc.HasExited) { $proc.Kill() }
    $all = @($msg) + $fail
    "FAILURES: $($all.Count)"
    $all | ForEach-Object { "  $_" }
    exit 1
}

MoveTo 3000 1900
Start-Sleep -Milliseconds 400
Get-Process winshot -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 600
$proc = Start-Process -FilePath 'D:\Project\winshot\x64\Debug\winshot.exe' -PassThru
Start-Sleep -Seconds 2

$sink = @(Find-Wins 'WinShotSink')
if ($sink.Count -eq 0) { Bail 'no sink window' }
[void][FSZ]::PostMessage($sink[0], 0x8002, [IntPtr]::Zero, [IntPtr]::Zero)
Start-Sleep -Seconds 2
$ov = @(Find-Wins 'WinShotOverlay')
if ($ov.Count -eq 0) { Bail 'no overlay window' }

Drag 700 500 2200 1500
$p = Slot 5
if (-not $p) { Bail 'no toolbar' }
Click $p[0] $p[1]              # the text tool: the bar with the 字号 box
Start-Sleep -Milliseconds 400
$fb = Font-Bar
if (-not $fb) { Bail 'the text tool did not bring up the property bar' }
"font box arrow at $($fb.x),$($fb.y); bar $($fb.bar.left),$($fb.bar.top) .. $($fb.bar.right),$($fb.bar.bottom)"

Click 900 700
$ed = Editor
if (-not $ed) { 'FAIL: clicking with the text tool opened no editor'; exit 1 }
Keys ('W' * 12)
Start-Sleep -Milliseconds 800
# Read the box while the window is still there: committing destroys it, and
# GetWindowRect on a dead HWND answers zero without failing, which would put the
# next press at 0,0 in the corner of the screen.
$box0 = Edit-Box $ed
Keys '^({ENTER})'              # Ctrl+Enter commits; plain Enter belongs to the control
Start-Sleep -Milliseconds 700

# --- the selected label, no editor open ---------------------------------------
# With the text tool still armed a press on existing ink grabs that label rather
# than starting a new one, and a press that never moves leaves it selected.
if (Editor) { Bail 'Ctrl+Enter left the edit open' }
$cx = [int](($box0.left + $box0.right) / 2); $cy = [int](($box0.top + $box0.bottom) / 2)
Click $cx $cy
if (Editor) { Bail 'clicking the committed label opened an editor instead of selecting it' }
MoveTo 2300 1800; Start-Sleep -Milliseconds 400
$g = Grab 'D:\Project\winshot\obj\fs_selected.png'
$sel = Frame-Box $g $cx $cy
if (-not $sel) { $g.Dispose(); Bail 'the click did not leave the label on screen' }
$h18 = Ink-Rows $g ($sel.l + 4) ($sel.t + 4) ($sel.r - 5) ($sel.b - 5)
$g.Dispose()
"selected label at 18: ink rows $($h18.n) ($($h18.t)..$($h18.b))"
if ($h18.n -lt 8) { Bail "only $($h18.n) rows of ink at the default size; nothing to scale" }

# Row 12 is 32, the bottom of the list; row 0 is 8, the top.
if (-not (Pick-Row 12)) { $fail += 'the list did not open when the 字号 box was pressed' }
MoveTo 2300 1800; Start-Sleep -Milliseconds 400
$g = Grab 'D:\Project\winshot\obj\fs_32.png'
$sel32 = Frame-Box $g $cx $cy
$h32 = if ($sel32) { Ink-Rows $g ($sel32.l + 4) ($sel32.t + 4) ($sel32.r - 5) ($sel32.b - 5) }
       else { @{ n = 0; t = -1; b = -1 } }
$g.Dispose()
"after row 12 (32): ink rows $($h32.n) ($($h32.t)..$($h32.b))"
if (-not $sel32) {
    $fail += 'picking the last row of the list left no ink at all'
} elseif ($h32.n -lt [int]($h18.n * 1.4)) {
    $fail += "row 12 of the list left the glyphs $($h32.n) rows tall against $($h18.n) at 18; the selected label did not take the size"
}

if (-not (Pick-Row 0)) { $fail += 'the list did not open for the first row' }
MoveTo 2300 1800; Start-Sleep -Milliseconds 400
$g = Grab 'D:\Project\winshot\obj\fs_08.png'
$sel08 = Frame-Box $g $cx $cy
$h08 = if ($sel08) { Ink-Rows $g ($sel08.l + 4) ($sel08.t + 4) ($sel08.r - 5) ($sel08.b - 5) }
       else { @{ n = 0; t = -1; b = -1 } }
$g.Dispose()
"after row 0 (8): ink rows $($h08.n) ($($h08.t)..$($h08.b))"
if (-not $sel08) {
    $fail += 'picking the first row of the list left no ink at all'
} elseif ($h08.n -gt [int]($h18.n * 0.7)) {
    $fail += "row 0 of the list left the glyphs $($h08.n) rows tall against $($h18.n) at 18; the size did not shrink"
}

# --- the label being typed into -----------------------------------------------
# Back to a mid size so the growth below is measured from something.
if (-not (Pick-Row 6)) { $fail += 'the list did not open for the middle row' }
Start-Sleep -Milliseconds 300
DblClick $cx $cy
$ed2 = Editor
if (-not $ed2) { Bail 'double-clicking the label did not re-open it' }
$box1 = Edit-Box $ed2
MoveTo 2300 1800; Start-Sleep -Milliseconds 400
$g = Grab 'D:\Project\winshot\obj\fs_edit_before.png'
$e20 = Ink-Rows $g ($box1.left + 4) ($box1.top + 4) ($box1.right - 5) ($box1.bottom - 5)
$g.Dispose()
"editing at 20: box $($box1.left),$($box1.top) .. $($box1.right),$($box1.bottom), ink rows $($e20.n)"
if ($e20.n -lt 6) { Bail 'no ink to scale while editing' }

if (-not (Pick-Row 12)) { $fail += 'the list did not open while the edit was already open' }
Start-Sleep -Milliseconds 500
$ed3 = Editor
if (-not $ed3) {
    $fail += 'picking a font size closed the text edit: the row press has to leave the edit open'
} else {
    $box2 = Edit-Box $ed3
    MoveTo 2300 1800; Start-Sleep -Milliseconds 400
    $g = Grab 'D:\Project\winshot\obj\fs_edit_after.png'
    $e32 = Ink-Rows $g ($box2.left + 4) ($box2.top + 4) ($box2.right - 5) ($box2.bottom - 5)
    $g.Dispose()
    "editing at 32: box $($box2.left),$($box2.top) .. $($box2.right),$($box2.bottom), ink rows $($e32.n)"
    if ($e32.n -lt [int]($e20.n * 1.35)) {
        $fail += "with the edit open, row 12 left the glyphs $($e32.n) rows tall against $($e20.n): the input control kept its old font"
    }
    $grew = ($box2.bottom - $box2.top) - ($box1.bottom - $box1.top)
    "the box grew by $grew px"
    if ($grew -lt 8) {
        $fail += "the box of the label being typed into grew by only $grew px for 20 -> 32; the box did not follow the font"
    }
    Keys '^({ENTER})'
    Start-Sleep -Milliseconds 600
}

# --- typing a size into the box -------------------------------------------------
# The list only offers the even sizes, so reaching an odd one means typing into the
# box itself. That is also the path with the focus hazard: the input box takes
# keyboard focus, and taking it commits a text edit that is running, which ends by
# deselecting its label. The size therefore has to be aimed at the label found
# before focus moved.
#
# The measurement is the box's own height off the red selection frame, not the ink
# rows. A label that was typed rather than dragged gets a height of exactly the
# font size plus the 20px the box keeps for the caret, so the frame pins a size to
# the pixel where a row count only brackets it.
MoveTo 2300 1800; Start-Sleep -Milliseconds 400
$g = Grab ''
$cur = Frame-Box $g $cx $cy
$g.Dispose()
if (-not $cur) { Bail 'no label left on screen to type a size into' }
$cx = [int](($cur.l + $cur.r) / 2); $cy = [int](($cur.t + $cur.b) / 2)
Click $cx $cy
if (Editor) { Bail 're-selecting the label opened an editor instead' }

if (-not (Pick-Row 9))  { $fail += 'the list did not open for row 9 (26)' }
$m26 = Frame-Height $cx $cy
if (-not (Pick-Row 10)) { $fail += 'the list did not open for row 10 (28)' }
$m28 = Frame-Height $cx $cy
Type-Size '27'
$m27 = Frame-Height $cx $cy
"list 26 -> box height $($m26.h), list 28 -> $($m28.h), typed 27 -> $($m27.h)"
if (-not $m26 -or -not $m28 -or -not $m27) {
    $fail += 'the label vanished partway through the typed-size steps'
} elseif ($m27.h -le $m26.h -or $m27.h -ge $m28.h) {
    $fail += "typing 27 gave a box $($m27.h) px tall, outside the $($m26.h)..$($m28.h) px the list rows 26 and 28 give: the typed size was snapped to the list or ignored"
}

# Clamping: the box takes any digits, and a number past the ends has to land on
# them rather than on a glyph too small to read or too big to fit.
Type-Size '99'
$m99 = Frame-Height $cx $cy
Type-Size '1'
$m1 = Frame-Height $cx $cy
if (-not (Pick-Row 12)) { $fail += 'the list did not open for row 12 (32)' }
$mR32 = Frame-Height $cx $cy
if (-not (Pick-Row 0)) { $fail += 'the list did not open for row 0 (8)' }
$mR8 = Frame-Height $cx $cy
"typed 99 -> $($m99.h), row 32 -> $($mR32.h); typed 1 -> $($m1.h), row 8 -> $($mR8.h)"
if ($m99 -and $mR32 -and [Math]::Abs($m99.h - $mR32.h) -gt 1) {
    $fail += "typing 99 gave a box $($m99.h) px tall where the 32 row gives $($mR32.h): the typed size was not clamped to the top of the range"
}
if ($m1 -and $mR8 -and [Math]::Abs($m1.h - $mR8.h) -gt 1) {
    $fail += "typing 1 gave a box $($m1.h) px tall where the 8 row gives $($mR8.h): the typed size was not clamped to the bottom of the range"
}

Click $p[0] $p[1]              # disarm
if (-not $proc.HasExited) { $proc.Kill() }
if ($fail.Count) { "FAILURES: $($fail.Count)"; $fail | ForEach-Object { "  $_" }; exit 1 }
'PASS'
