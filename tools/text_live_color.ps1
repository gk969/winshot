# Picking a colour for a text label used to wait for the edit to end. The input
# control captured label->Ink() once, in Create, and OnCtlColor read only that
# copy, so ApplyStyleToSelected moved the shape's ink and nothing on screen
# followed: the box kept drawing the old colour until it lost focus, which reads
# as a click that did nothing.
#
#   selected   click the label, pick a swatch, grab -> the glyphs are the new colour
#   editing    double-click, pick a swatch, grab -> the new colour with the edit
#              still open, and still the new colour after committing
#
# The label's own box is the measurement window. While editing it is the input
# window inflated by the 4px inset it keeps from the box so the eight markers
# stay outside it; the ink starts 5px in from the top and left, so 4 in and 5
# back keeps every glyph and leaves out the red frame and the markers, which stay
# red whatever the ink becomes.
Add-Type -AssemblyName System.Drawing, System.Windows.Forms
Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class TLC {
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
# The palette grid in the property bar: 8 columns of 13px chips at a 15px pitch,
# two rows at a 16px pitch, the grid 119px in from the bar's left edge.
$GRID_X = 119; $SW = 13; $PITCH = 15; $ROW_Y = 5; $ROW_PITCH = 16

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
    [void][TLC]::mouse_event(0x8001, [uint32][int][Math]::Round(65535 * $x / 3839),
                             [uint32][int][Math]::Round(65535 * $y / 2159), 0,
                             [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 90
}
function Down { [void][TLC]::mouse_event($LEFTDOWN, 0, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 150 }
function Up { [void][TLC]::mouse_event($LEFTUP, 0, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 350 }
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
    [void][TLC]::mouse_event($LEFTDOWN, 0, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 60
    [void][TLC]::mouse_event($LEFTUP, 0, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 60
    [void][TLC]::mouse_event($LEFTDOWN, 0, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 60
    [void][TLC]::mouse_event($LEFTUP, 0, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 450
}
function Keys([string]$s) { [void][System.Windows.Forms.SendKeys]::SendWait($s) }
function Find-Wins([string]$title) {
    $found = New-Object System.Collections.ArrayList
    $cb = [TLC+EnumProc] {
        param($h, $l)
        $t = New-Object System.Text.StringBuilder 256
        [void][TLC]::GetWindowText($h, $t, 256)
        if ($t.ToString() -eq $title) { [void]$found.Add($h) }
        return $true
    }
    [void][TLC]::EnumWindows($cb, [IntPtr]::Zero)
    return $found.ToArray()
}
function Find-Kids([IntPtr]$parent, [string]$title) {
    $found = New-Object System.Collections.ArrayList
    $cb = [TLC+EnumProc] {
        param($h, $l)
        $t = New-Object System.Text.StringBuilder 256
        [void][TLC]::GetWindowText($h, $t, 256)
        if ($t.ToString() -eq $title -and [TLC]::IsWindowVisible($h)) { [void]$found.Add($h) }
        return $true
    }
    [void][TLC]::EnumChildWindows($parent, $cb, [IntPtr]::Zero)
    return $found.ToArray()
}
function Rect-Of([IntPtr]$h) {
    $r = New-Object TLC+RECT
    [void][TLC]::GetWindowRect($h, [ref]$r)
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
# Screen point at the centre of palette entry i. The row is a floor, not a cast:
# [int] rounds, so entry 5 would land on the second row and 14 below the bar.
function Swatch-Point([int]$i) {
    $b = @(Find-Kids $ov[0] 'WinShotPropBar')
    if ($b.Count -eq 0) { return $null }
    $r = Rect-Of $b[0]
    return @(($r.left + $GRID_X + ($i % 8) * $PITCH + [int]($SW / 2)),
             ($r.top + $ROW_Y + [int][Math]::Floor($i / 8) * $ROW_PITCH +
              [int]($SW / 2)))
}
function Edit-Box([IntPtr]$h) {
    $r = Rect-Of $h
    $r.left -= 4; $r.top -= 4; $r.right += 4; $r.bottom += 4
    return $r
}
# tb::kPalette[10] is the red the tool starts on, [14] 0xFFFF00FF magenta and
# [5] 0xFF365CD1 blue. The glyph cores are opaque, so the dimmed desktop under
# them does not shift these; only the anti-aliased edge does, and the counts
# below leave room for that.
function IsMagenta($c) { return ($c.R -gt 190 -and $c.G -lt 110 -and $c.B -gt 190) }
function IsBlue($c) { return ($c.B -gt 150 -and ($c.B - $c.R) -gt 60 -and ($c.B - $c.G) -gt 45) }
# "The old colour is gone" needs the colour itself, not a reddish/magenta-ish
# test. A loose test fails on its own: an anti-aliased glyph edge blends the new
# ink with what it crosses, and 274 such edge pixels out of ~900 read as red to
# the loose test even with no old ink left. The old ink was drawn opaque at the
# palette colour, so only that colour, unblended, is evidence it survived.
function IsOld($c, [int]$r, [int]$g, [int]$b) {
    return ([Math]::Abs($c.R - $r) -le 12 -and [Math]::Abs($c.G - $g) -le 12 -and
            [Math]::Abs($c.B - $b) -le 12)
}
function Count-In($bmp, [int]$l, [int]$t, [int]$r, [int]$b, [scriptblock]$test) {
    $n = 0
    for ($y = $t; $y -le $b; $y++) {
        for ($x = $l; $x -le $r; $x++) { if (& $test ($bmp.GetPixel($x, $y))) { $n++ } }
    }
    return $n
}
# Ink inside a label's box, with the frame and the markers left out.
function Ink-Count($bmp, $box, [scriptblock]$test) {
    return Count-In $bmp ($box.left + 4) ($box.top + 4) ($box.right - 5) ($box.bottom - 5) $test
}
# The large current-colour chip at the head of the palette (kCurrentX 85,
# kCurrentSwatch 26, rowY 5). Reading it separates a swatch press that never
# landed from one that set the style but left the label behind.
function Chip($bmp) {
    $b = @(Find-Kids $ov[0] 'WinShotPropBar')
    if ($b.Count -eq 0) { return 'no bar' }
    $r = Rect-Of $b[0]
    $c = $bmp.GetPixel($r.left + 98, $r.top + 18)
    return "$($c.R),$($c.G),$($c.B)"
}
$fail = @()

MoveTo 3000 1900
Start-Sleep -Milliseconds 400
Get-Process winshot -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 600
$proc = Start-Process -FilePath 'D:\Project\winshot\x64\Debug\winshot.exe' -PassThru
Start-Sleep -Seconds 2

$sink = @(Find-Wins 'WinShotSink')
if ($sink.Count -eq 0) { 'FAIL: no sink window'; exit 1 }
[void][TLC]::PostMessage($sink[0], 0x8002, [IntPtr]::Zero, [IntPtr]::Zero)
Start-Sleep -Seconds 2
$ov = @(Find-Wins 'WinShotOverlay')
if ($ov.Count -eq 0) { 'FAIL: no overlay window'; exit 1 }

Drag 700 500 2200 1500
$p = Slot 5
if (-not $p) { 'FAIL: no toolbar'; exit 1 }
Click $p[0] $p[1]              # the text tool, which brings up the palette
Start-Sleep -Milliseconds 400
$sw14 = Swatch-Point 14        # magenta
$sw5 = Swatch-Point 5          # blue
if (-not $sw14 -or -not $sw5) { 'FAIL: the text tool did not bring up the property bar'; exit 1 }
"magenta swatch at $($sw14[0]),$($sw14[1]); blue at $($sw5[0]),$($sw5[1])"
# The bar's rect is the only geometry these points come from, and the chips have
# known colours: entry 14 is 0xFFFF00FF and entry 5 is 0xFF365CD1. A point that
# is not those colours is not on that chip, and the press is going somewhere else.
$tb = @(Find-Kids $ov[0] 'WinShotToolbar')
if ($tb.Count) { $tbr = Rect-Of $tb[0]; "toolbar $($tbr.left),$($tbr.top) .. $($tbr.right),$($tbr.bottom)" }
$bb = @(Find-Kids $ov[0] 'WinShotPropBar')
if ($bb.Count) { $bbr = Rect-Of $bb[0]; "bar rect $($bbr.left),$($bbr.top) .. $($bbr.right),$($bbr.bottom)" }
$g = Grab ''
$c14 = $g.GetPixel($sw14[0], $sw14[1]); $c5 = $g.GetPixel($sw5[0], $sw5[1])
"chip colours: 14 -> $($c14.R),$($c14.G),$($c14.B)  5 -> $($c5.R),$($c5.G),$($c5.B)"
$g.Dispose()

Click 900 700
$ed = Editor
if (-not $ed) { 'FAIL: clicking with the text tool opened no editor'; exit 1 }
Keys ('W' * 12)
Start-Sleep -Milliseconds 800
# Read the box while the window is still there: committing destroys it, and
# GetWindowRect on a dead HWND answers zero without failing, which would put the
# next press at 0,0 in the corner of the screen.
$box0 = Edit-Box $ed
Keys '^({ENTER})'
Start-Sleep -Milliseconds 700

# --- selected, no editor open --------------------------------------------------
if (Editor) { 'FAIL: Ctrl+Enter left the edit open'; exit 1 }
$cx = [int](($box0.left + $box0.right) / 2); $cy = [int](($box0.top + $box0.bottom) / 2)
Click $cx $cy
if (Editor) { 'FAIL: clicking the committed label opened an editor instead of selecting it'; exit 1 }
MoveTo 2300 1800; Start-Sleep -Milliseconds 400
$g = Grab 'D:\Project\winshot\obj\tlc_sel_before.png'
$red0 = Ink-Count $g $box0 { param($c) IsOld $c 247 56 64 }
$chip0 = Chip $g
$g.Dispose()
"selected label box $($box0.left),$($box0.top) .. $($box0.right),$($box0.bottom); red px=$red0  chip $chip0"
if ($red0 -lt 150) { 'FAIL: the label has no red ink to recolour'; exit 1 }

Click $sw14[0] $sw14[1]
MoveTo 2300 1800; Start-Sleep -Milliseconds 400
$g = Grab 'D:\Project\winshot\obj\tlc_sel_after.png'
$mag0 = Ink-Count $g $box0 { param($c) IsMagenta $c }
$red1 = Ink-Count $g $box0 { param($c) IsOld $c 247 56 64 }
$chip1 = Chip $g
$g.Dispose()
"selected label after the swatch: magenta px=$mag0  red px=$red1  chip $chip1"
if ($mag0 -lt 150) {
    $fail += "a selected label kept its old colour: only $mag0 magenta pixels where there were $red0 red"
}
if ($red1 -gt 40) {
    $fail += "$red1 red pixels of the old colour still inside a selected label after recolouring"
}

# --- while the edit is open ----------------------------------------------------
DblClick $cx $cy
$ed2 = Editor
if (-not $ed2) { 'FAIL: double-clicking the label did not re-open it'; exit 1 }
$box1 = Edit-Box $ed2
MoveTo 2300 1800; Start-Sleep -Milliseconds 400
$g = Grab 'D:\Project\winshot\obj\tlc_edit_before.png'
$mag1 = Ink-Count $g $box1 { param($c) IsMagenta $c }
$g.Dispose()
"editing before: magenta px=$mag1"
if ($mag1 -lt 150) { 'FAIL: the re-opened edit did not carry the recoloured ink'; exit 1 }

Click $sw5[0] $sw5[1]
Start-Sleep -Milliseconds 500
$ed3 = Editor
if (-not $ed3) {
    'FAIL: clicking a colour swatch closed the text edit: the bar must not take focus'
    exit 1
}
MoveTo 2300 1800; Start-Sleep -Milliseconds 400
$g = Grab 'D:\Project\winshot\obj\tlc_edit_after.png'
$blue0 = Ink-Count $g $box1 { param($c) IsBlue $c }
$mag2 = Ink-Count $g $box1 { param($c) IsOld $c 255 0 255 }
$chip2 = Chip $g
$g.Dispose()
"editing after the swatch: blue px=$blue0  magenta px=$mag2  chip $chip2 (edit still open)"
if ($blue0 -lt 150) {
    $fail += "the label being typed into kept its old colour: only $blue0 blue pixels while the edit was open"
}
if ($mag2 -gt 40) {
    $fail += "$mag2 magenta pixels of the old colour still inside the box being typed into"
}

# --- and it survives the commit ------------------------------------------------
Keys '^({ENTER})'
Start-Sleep -Milliseconds 700
Click $p[0] $p[1]              # disarm
MoveTo 2300 1800; Start-Sleep -Milliseconds 400
$g = Grab 'D:\Project\winshot\obj\tlc_committed.png'
$blue1 = Ink-Count $g $box1 { param($c) IsBlue $c }
$g.Dispose()
"after commit: blue px=$blue1"
if ($blue1 -lt 150) {
    $fail += "the committed label is not blue: only $blue1 blue pixels"
}

if (-not $proc.HasExited) { $proc.Kill() }
if ($fail.Count) { "FAILURES: $($fail.Count)"; $fail | ForEach-Object { "  $_" }; exit 1 }
'PASS'
