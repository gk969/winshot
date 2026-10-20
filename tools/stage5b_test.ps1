Add-Type -AssemblyName System.Drawing, System.Windows.Forms
Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class W5B {
    public delegate bool EnumProc(IntPtr h, IntPtr l);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
    [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr p, EnumProc cb, IntPtr l);
    [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll", CharSet=CharSet.Auto)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint msg, IntPtr w, IntPtr l);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr SendMessage(IntPtr h, uint msg, IntPtr w, string l);
    [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr h, uint msg, IntPtr w, IntPtr l);
    [DllImport("user32.dll")] public static extern int GetWindowThreadProcessId(IntPtr h, out int pid);
    [DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr h, int idx);
    [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint dx, uint dy, uint d, UIntPtr e);
}
"@

$LEFTDOWN = 0x0002; $LEFTUP = 0x0004
$WM_SETTEXT = 0x000C; $BM_CLICK = 0x00F5; $GWL_STYLE = -16; $BS_DEFPUSHBUTTON = 0x1

# The display runs at 96dpi, so every logical size in the app is also its
# physical size: 字号 box 46x23 at bar x+30, dropdown rows 20px, edit box 40 wide.
$K = 1.0
function Sx([int]$v) { return [int]($v * $K) }

function Grab([string]$path) {
    $b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    $bmp = New-Object System.Drawing.Bitmap $b.Width, $b.Height
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen($b.Location, [System.Drawing.Point]::Empty, $bmp.Size)
    $bmp.Save($path)
    $g.Dispose()
    return $bmp
}
function Crop($full, [int]$x, [int]$y, [int]$w, [int]$h, [string]$path) {
    $r = New-Object System.Drawing.Rectangle $x, $y, $w, $h
    $c = $full.Clone($r, $full.PixelFormat)
    $c.Save($path)
    return $c
}
function MoveTo([int]$x, [int]$y) {
    [System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point($x, $y)
    Start-Sleep -Milliseconds 90
}
function Drag([int]$x1, [int]$y1, [int]$x2, [int]$y2) {
    MoveTo $x1 $y1
    [void][W5B]::mouse_event($LEFTDOWN, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 120
    for ($i = 1; $i -le 12; $i++) {
        MoveTo ([int]($x1 + ($x2-$x1) * $i / 12)) ([int]($y1 + ($y2-$y1) * $i / 12))
    }
    Start-Sleep -Milliseconds 150
    [void][W5B]::mouse_event($LEFTUP, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 300
}
function Click([int]$x, [int]$y) {
    MoveTo $x $y
    [void][W5B]::mouse_event($LEFTDOWN, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 120
    [void][W5B]::mouse_event($LEFTUP, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 350
}
function DblClick([int]$x, [int]$y) {
    MoveTo $x $y
    [void][W5B]::mouse_event($LEFTDOWN, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 60
    [void][W5B]::mouse_event($LEFTUP, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 60
    [void][W5B]::mouse_event($LEFTDOWN, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 60
    [void][W5B]::mouse_event($LEFTUP, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 400
}
function IsBack($c) {
    return ([Math]::Abs($c.R - 235) -le 8 -and [Math]::Abs($c.G - 239) -le 8 -and
            [Math]::Abs($c.B - 243) -le 8)
}
function Band($bmp, [int]$x, [int]$y0, [int]$y1) {
    $top = -1
    for ($y = $y0; $y -le $y1; $y++) { if (IsBack ($bmp.GetPixel($x, $y))) { $top = $y; break } }
    if ($top -lt 0) { return $null }
    $bot = $top
    while ($bot + 1 -le $y1 -and (IsBack ($bmp.GetPixel($x, ($bot + 1))))) { $bot++ }
    return @($top, $bot)
}
function Extent($bmp, [int]$row) {
    $l = -1; $r = -1
    for ($x = 0; $x -lt $bmp.Width; $x++) {
        $c = $bmp.GetPixel($x, $row)
        if ($c.R -gt 200 -and $c.G -gt 200 -and $c.B -gt 200) { if ($l -lt 0) { $l = $x }; $r = $x }
    }
    return @($l, $r)
}
function IsRed($c) { return ($c.R -gt 190 -and $c.G -lt 120 -and $c.B -lt 130) }
function RedCount($bmp, [int]$x0, [int]$y0, [int]$x1, [int]$y1) {
    if (-not $bmp) { return -1 }
    $n = 0
    for ($y = $y0; $y -le $y1; $y++) {
        for ($x = $x0; $x -le $x1; $x++) { if (IsRed ($bmp.GetPixel($x, $y))) { $n++ } }
    }
    return $n
}
# The frame is a 1px red line 2px outside the box, and the eight resize markers
# sit on that line: three per side, each a white core that interrupts it. So the
# frame is measured by how far its red reaches along a side and how much of it
# there is, not by one unbroken run. Returns the two spans and the two counts.
function FrameScan($bmp, [int]$x0, [int]$y0, [int]$x1, [int]$y1) {
    $bestRow = 0; $rowSpan = 0
    foreach ($y in ($y0 - 4)..($y0 + 4)) {
        $n = 0; $lo = -1; $hi = -1
        for ($x = $x0 - 4; $x -le $x1 + 4; $x++) {
            if (-not (IsRed ($bmp.GetPixel($x, $y)))) { continue }
            $n++
            if ($lo -lt 0) { $lo = $x }
            $hi = $x
        }
        if ($n -gt $bestRow) { $bestRow = $n; $rowSpan = $hi - $lo + 1 }
    }
    $bestCol = 0; $colSpan = 0
    foreach ($x in ($x0 - 4)..($x0 + 4)) {
        $n = 0; $lo = -1; $hi = -1
        for ($y = $y0 - 4; $y -le $y1 + 4; $y++) {
            if (-not (IsRed ($bmp.GetPixel($x, $y)))) { continue }
            $n++
            if ($lo -lt 0) { $lo = $y }
            $hi = $y
        }
        if ($n -gt $bestCol) { $bestCol = $n; $colSpan = $hi - $lo + 1 }
    }
    return @($rowSpan, $colSpan, $bestRow, $bestCol)
}
function IsAccent($c) {
    return ([Math]::Abs($c.R - 0x2E) -le 26 -and [Math]::Abs($c.G - 0x92) -le 26 -and
            [Math]::Abs($c.B - 0xE1) -le 26)
}
function AccentCount($bmp, [int]$x0, [int]$y0, [int]$x1, [int]$y1) {
    $n = 0
    for ($y = $y0; $y -le $y1; $y++) {
        for ($x = $x0; $x -le $x1; $x++) { if (IsAccent ($bmp.GetPixel($x, $y))) { $n++ } }
    }
    return $n
}
# The label's own ink. A committed label is drawn with a 1px guide box and eight
# 5px handle rings on that box's edges, and the box is only 42px tall, so every
# window wide enough for the glyphs also catches the rings — which is how this
# came to compare 291 against 368 for the same string. The band below starts
# inside the left rings and ends inside the right ones, and between the top and
# bottom rows of rings, so it counts glyphs only.
function GlyphInk($bmp) {
    return RedCount $bmp ($edit[0] + 8) ($edit[1] + 8) ($edit[0] + 44) ($edit[1] + 34)
}
# Bounding box of the near-white 字号 box inside the property bar.
function WhiteBox($bmp, [int]$x0, [int]$y0, [int]$x1, [int]$y1) {
    $l = 99999; $r = -1; $t = 99999; $b = -1
    for ($y = $y0; $y -le $y1; $y++) {
        for ($x = $x0; $x -le $x1; $x++) {
            $c = $bmp.GetPixel($x, $y)
            if ($c.R -gt 245 -and $c.G -gt 245 -and $c.B -gt 245) {
                if ($x -lt $l) { $l = $x }; if ($x -gt $r) { $r = $x }
                if ($y -lt $t) { $t = $y }; if ($y -gt $b) { $b = $y }
            }
        }
    }
    if ($r -lt 0) { return $null }
    return @($l, $t, $r, $b)
}

Get-Process winshot -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 600

$sel = @(800, 600, 1400, 1000)
$edit = @(1000, 700)     # where the text tool is pressed
Get-ChildItem 'D:\Project\winshot\obj\s5b_*.png' -ErrorAction SilentlyContinue | Remove-Item -Force

MoveTo 3000 1900
Start-Sleep -Milliseconds 400

$proc = Start-Process -FilePath 'D:\Project\winshot\x64\Debug\winshot.exe' -PassThru
Start-Sleep -Seconds 2

$sink = New-Object System.Collections.ArrayList
$cb = [W5B+EnumProc] {
    param($h, $l)
    $t = New-Object System.Text.StringBuilder 256
    [void][W5B]::GetWindowText($h, $t, 256)
    if ($t.ToString() -eq 'WinShotSink') { [void]$sink.Add($h) }
    return $true
}
[void][W5B]::EnumWindows($cb, [IntPtr]::Zero)
if ($sink.Count -eq 0) { "FAIL: no sink window"; exit 1 }

[void][W5B]::PostMessage($sink[0], 0x8002, [IntPtr]::Zero, [IntPtr]::Zero)
Start-Sleep -Seconds 2

Drag $sel[0] $sel[1] $sel[2] $sel[3]

$s0 = Grab 'D:\Project\winshot\obj\s5b_full0.png'
$b0 = Band $s0 ($sel[0] + 6) ($sel[3] + 1) ($sel[3] + 90)
if (-not $b0) { "FAIL: no toolbar under the selection"; exit 1 }
$midY = [int](($b0[0] + $b0[1]) / 2)
$e0 = Extent $s0 $midY
$cell = [int](($e0[1] - $e0[0] - 8) / 17)
$slot0 = $e0[0] + 4 + [int]($cell / 2)
"toolbar x=$($e0[0])..$($e0[1]) y=$($b0[0])..($($b0[1])) cell=$cell"
function Slot([int]$i) { return @(($slot0 + $i * $cell), $midY) }

# --- the 文字 tool: slot 5 ------------------------------------------------
$t = Slot 5
Click $t[0] $t[1]

# The property bar under the toolbar must swap its width dots for the 字号 box:
# a white box 46x23 at bar x+30.
$s1 = Grab 'D:\Project\winshot\obj\s5b_full1.png'
$barTop = $b0[1] + 4          # the bar window starts 4px under the light band
$bx = WhiteBox $s1 ($sel[0] + 20) ($barTop) ($sel[0] + 100) ($barTop + (Sx 37))
if (-not $bx) { "FAIL: no white 字号 box in the property bar"; exit 1 }
$boxW = $bx[2] - $bx[0] + 1; $boxH = $bx[3] - $bx[1] + 1
"字号 box ($($bx[0]),$($bx[1]))-($($bx[2]),$($bx[3])) = ${boxW}x${boxH}  (want ~$($sel[0]+30+2),~1043 46x23)"
if ($boxW -lt 40 -or $boxH -lt 18) { "FAIL: 字号 box wrong size"; exit 1 }
[void](Crop $s1 $sel[0] ($barTop - 2) 260 44 'D:\Project\winshot\obj\s5b_bar_text.png')

$boxCX = [int](($bx[0] + $bx[2]) / 2)
$boxCY = [int](($bx[1] + $bx[3]) / 2)
# The box is two targets now: its last 16px is the ▼ that opens the list, and the
# rest is typed into. Pressing the middle of the box brings up an input control
# that takes focus, so the list has to be opened off the strip at its right edge.
$arrowX = $bx[2] - (Sx 8)
$listTop = $bx[3] + 1 + (Sx 2)
$rowH = Sx 20
# 8..32 in steps of 2, so 13 rows; 18 is the 6th and 22 the 8th.
$rows = 13
function FontRow([int]$px) { return (($px - 8) / 2) }
function RowAccent($bmp, [int]$i) {
    $y0 = $listTop + $i * $rowH + 3
    return (AccentCount $bmp ($bx[0] + 2) $y0 ($bx[2] - 2) ($y0 + $rowH - 6))
}
function HotRow($bmp) {
    $hot = -1
    for ($i = 0; $i -lt $rows; $i++) { if ((RowAccent $bmp $i) -gt 100) { $hot = $i } }
    return $hot
}

# --- the 字号 dropdown ----------------------------------------------------
Click $arrowX $boxCY
$s2 = Grab 'D:\Project\winshot\obj\s5b_full2.png'
$card = $null
for ($y = $listTop; $y -lt $listTop + $rows * $rowH; $y += 10) {
    if ($s2.GetPixel($bx[0] + 5, $y).R -gt 245) { $card = $true; break }
}
$hot = HotRow $s2
"dropdown open=$card; highlighted row: $hot  (want $(FontRow 18) = 18)"
if (-not $card -or $hot -ne (FontRow 18)) { "FAIL: dropdown wrong"; exit 1 }
[void](Crop $s2 ($bx[0] - 20) ($barTop - 6) 200 300 'D:\Project\winshot\obj\s5b_drop1.png')

Click $boxCX ($listTop + (FontRow 22) * $rowH + [int]($rowH / 2))   # pick 22
$s3 = Grab 'D:\Project\winshot\obj\s5b_full3.png'
"rows highlighted after picking 22: $(HotRow $s3)  (want -1 - list closed)"
[void](Crop $s3 ($bx[0] - 20) ($barTop - 6) 200 300 'D:\Project\winshot\obj\s5b_drop2.png')

Click $arrowX $boxCY
$s4 = Grab 'D:\Project\winshot\obj\s5b_full4.png'
$hot2 = HotRow $s4
"highlighted row after reopening: $hot2  (want $(FontRow 22) = 22)"
if ($hot2 -ne (FontRow 22)) { "FAIL: picked size did not stick"; exit 1 }
[void](Crop $s4 ($bx[0] - 20) ($barTop - 6) 200 300 'D:\Project\winshot\obj\s5b_drop3.png')
Click $arrowX $boxCY   # close it again

# --- press on the canvas: the red edit frame ------------------------------
# The 字号 picked above is 22, so the label box is 40 wide and 22+20 tall at the
# press point, and the frame is that 2px out on every side: 45px a side.
Click $edit[0] $edit[1]
$s5 = Grab 'D:\Project\winshot\obj\s5b_full5.png'
$fx0 = $edit[0] - 2; $fy0 = $edit[1] - 2
$fx1 = $edit[0] + 40 + 2; $fy1 = $edit[1] + 22 + 20 + 2
$fr = FrameScan $s5 $fx0 $fy0 $fx1 $fy1
"frame spans $($fr[0])x$($fr[1]) px with $($fr[2])+$($fr[3]) red px (want ~45x45, ~35 a side)"
if ($fr[0] -lt 40 -or $fr[1] -lt 40 -or $fr[2] -lt 25 -or $fr[3] -lt 25) {
    "FAIL: no edit frame"; exit 1
}
[void](Crop $s5 ($edit[0] - 40) ($edit[1] - 30) 260 100 'D:\Project\winshot\obj\s5b_editing.png')

# --- type, then commit with Enter ----------------------------------------
[void][System.Windows.Forms.SendKeys]::SendWait('hua')
Start-Sleep -Milliseconds 500
$s6 = Grab 'D:\Project\winshot\obj\s5b_full6.png'
$typed = RedCount $s6 ($edit[0] + 4) ($edit[1] + 4) ($edit[0] + 48) ($edit[1] + 34)
"red ink pixels while typing: $typed  (want > 20)"
[void](Crop $s6 ($edit[0] - 40) ($edit[1] - 30) 260 100 'D:\Project\winshot\obj\s5b_typed.png')

# Built from code points: Windows PowerShell reads a BOM-less .ps1 as ANSI, so
# a literal 花 in this file arrives as mojibake at the clipboard.
Set-Clipboard -Value (([string][char]0x82B1) * 2)
[void][System.Windows.Forms.SendKeys]::SendWait('^a')
Start-Sleep -Milliseconds 200
[void][System.Windows.Forms.SendKeys]::SendWait('^v')
Start-Sleep -Milliseconds 600
# Enter belongs to the control now -- it inserts a line break. Ctrl+Enter is
# what closes the edit.
[void][System.Windows.Forms.SendKeys]::SendWait('^({ENTER})')
Start-Sleep -Milliseconds 600

$s7 = Grab 'D:\Project\winshot\obj\s5b_full7.png'
$ink = GlyphInk $s7
$corner = 0
if (IsRed ($s7.GetPixel($fx0, $fy0))) { $corner++ }
if (IsRed ($s7.GetPixel($fx1, $fy1))) { $corner++ }
"committed ink pixels: $ink  (want > 40); frame corners still red: $corner  (want 0)"
if ($ink -lt 40 -or $corner -ne 0) { "FAIL: commit wrong"; exit 1 }
[void](Crop $s7 ($edit[0] - 40) ($edit[1] - 30) 300 100 'D:\Project\winshot\obj\s5b_committed.png')

# --- double-click re-edit, then Ctrl+Z -----------------------------------
# With the 文字 tool still active a press makes a NEW label, so drop the tool
# first; that is the state the reference shows for re-editing.
Click $t[0] $t[1]
DblClick ($edit[0] + 15) ($edit[1] + 12)
$s8 = Grab 'D:\Project\winshot\obj\s5b_full8.png'
# The committed label is wider than the 40px it started at, so the window has to
# reach past the fresh frame's right edge rather than assume the old one.
$fr2 = FrameScan $s8 $fx0 $fy0 ($fx1 + 80) $fy1
"re-edit frame spans $($fr2[0])x$($fr2[1]) px (want >= 45 both ways)"
if ($fr2[0] -lt 45 -or $fr2[1] -lt 40) {
    "FAIL: double-click did not reopen the label"; exit 1
}
[void](Crop $s8 ($edit[0] - 40) ($edit[1] - 30) 300 100 'D:\Project\winshot\obj\s5b_reedit.png')

[void][System.Windows.Forms.SendKeys]::SendWait('^a')
Start-Sleep -Milliseconds 150
[void][System.Windows.Forms.SendKeys]::SendWait('XYZ')
Start-Sleep -Milliseconds 400
$s8b = Grab 'D:\Project\winshot\obj\s5b_full8b.png'
[void](Crop $s8b ($edit[0] - 40) ($edit[1] - 30) 300 100 'D:\Project\winshot\obj\s5b_reedit_typed.png')
[void][System.Windows.Forms.SendKeys]::SendWait('^({ENTER})')
Start-Sleep -Milliseconds 500
# The magnifier rides the cursor and the cursor is still on the label, so it
# would hide the very thing being measured.
MoveTo 2200 1700
Start-Sleep -Milliseconds 300
$s9 = Grab 'D:\Project\winshot\obj\s5b_full9.png'
$after = GlyphInk $s9
[void](Crop $s9 ($edit[0] - 40) ($edit[1] - 30) 300 100 'D:\Project\winshot\obj\s5b_reedit2.png')
[void][System.Windows.Forms.SendKeys]::SendWait('^z')
Start-Sleep -Milliseconds 500
$sA = Grab 'D:\Project\winshot\obj\s5b_fullA.png'
$back = GlyphInk $sA
[void](Crop $sA ($edit[0] - 40) ($edit[1] - 30) 300 100 'D:\Project\winshot\obj\s5b_reedit3.png')
"ink committed=$ink after re-edit=$after after Ctrl+Z=$back  (want back ~= committed)"
if ([Math]::Abs($back - $ink) -gt 40) { "FAIL: Ctrl+Z did not restore the old string"; exit 1 }

# --- Esc cancels a fresh edit without adding anything --------------------
Click $t[0] $t[1]
Click 1150 900
[void][System.Windows.Forms.SendKeys]::SendWait('abc')
Start-Sleep -Milliseconds 300
[void][System.Windows.Forms.SendKeys]::SendWait('{ESC}')
Start-Sleep -Milliseconds 500
$sB = Grab 'D:\Project\winshot\obj\s5b_fullB.png'
$esc = RedCount $sB 1140 890 1260 950
"ink after Esc-cancelled edit: $esc  (want 0)"
Click $t[0] $t[1]

# --- save and check the PNG carries the text -----------------------------
$OUT = 'D:\Project\winshot\obj\s5b_out.png'
Remove-Item $OUT -Force -ErrorAction SilentlyContinue
[void][System.Windows.Forms.SendKeys]::SendWait('^s')
Start-Sleep -Seconds 2

$dlg = New-Object System.Collections.ArrayList
$dcb = [W5B+EnumProc] {
    param($h, $l)
    $cls = New-Object System.Text.StringBuilder 256
    [void][W5B]::GetClassName($h, $cls, 256)
    if ($cls.ToString() -ne '#32770') { return $true }
    $pid2 = 0
    [void][W5B]::GetWindowThreadProcessId($h, [ref]$pid2)
    if ($pid2 -eq $proc.Id) { [void]$dlg.Add($h) }
    return $true
}
[void][W5B]::EnumWindows($dcb, [IntPtr]::Zero)
"save dialog windows (winshot pid): $($dlg.Count)"
if ($dlg.Count -eq 0) { "FAIL: no save dialog"; exit 1 }

$btns = New-Object System.Collections.ArrayList
$ccb = [W5B+EnumProc] {
    param($h, $l)
    $cls = New-Object System.Text.StringBuilder 256
    [void][W5B]::GetClassName($h, $cls, 256)
    if ($cls.ToString() -eq 'Button') { [void]$btns.Add($h) }
    return $true
}
[void][W5B]::EnumChildWindows($dlg[0], $ccb, [IntPtr]::Zero)
# The file-name edit. This used to be the Edit whose text looked like a .png
# path, which only worked while the default name carried an extension -- it does
# not any more, because the format dropdown has to be free to decide that. The
# commdlg id cmb1 is no use either: GetSaveFileNameW routes to IFileSaveDialog
# unless OFN_ENABLEHOOK or OFN_ENABLETEMPLATE forces the classic resource, and
# the modern dialog has no cmb1 -- measured, GetDlgItem returns zero. The name
# edit is the one Edit with control id 1001; the address bar's toolbar shares
# that id, so the class has to be part of the test. The dialog is up before it
# has finished building its children, hence the retry.
$names = @()
for ($try = 0; $try -lt 20; $try++) {
    $found = New-Object System.Collections.ArrayList
    $nccb = [W5B+EnumProc] {
        param($h, $l)
        $cls = New-Object System.Text.StringBuilder 256
        [void][W5B]::GetClassName($h, $cls, 256)
        if ($cls.ToString() -eq 'Edit' -and [W5B]::GetWindowLong($h, -12) -eq 1001) { [void]$found.Add($h) }
        return $true
    }
    [void][W5B]::EnumChildWindows($dlg[0], $nccb, [IntPtr]::Zero)
    $names = $found.ToArray()
    if ($names.Count) { break }
    Start-Sleep -Milliseconds 200
}
if ($names.Count -eq 0) { "FAIL: no file-name edit in the dialog"; exit 1 }
$name = $names[0]
[void][W5B]::SendMessage($name, $WM_SETTEXT, [IntPtr]::Zero, $OUT)
$def = $null
foreach ($b in $btns) {
    if (([W5B]::GetWindowLong($b, $GWL_STYLE) -band $BS_DEFPUSHBUTTON) -ne 0) { $def = $b }
}
if (-not $def -and $btns.Count) { $def = $btns[0] }
[void][W5B]::SendMessage($def, $BM_CLICK, [IntPtr]::Zero, [IntPtr]::Zero)
Start-Sleep -Seconds 2

if (-not (Test-Path $OUT)) { "FAIL: Ctrl+S wrote no file"; exit 1 }
$png = [System.Drawing.Bitmap]::FromFile((Resolve-Path $OUT).Path)
"in png: text ink=$([int](RedCount $png ($edit[0]+2-$sel[0]) ($edit[1]+2-$sel[1]) ($edit[0]+90-$sel[0]) ($edit[1]+30-$sel[1])))"
"saved png $($png.Width) x $($png.Height)  (want $($sel[2]-$sel[0]) x $($sel[3]-$sel[1]))"
$png.Dispose()

"winshot still running: $(-not $proc.HasExited)"
if (-not $proc.HasExited) { $proc.Kill() }
