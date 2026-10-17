# What the pointer looks like is the whole of this request: an arrow wherever a
# press would do nothing, a plain crosshair with a square centre where a press
# starts a shape, and the four-way cross wherever a press moves something that
# is already there. A screenshot cannot show the pointer — CopyFromScreen leaves
# the cursor out — so this reads the cursor handle Windows has installed and
# compares it with the system cursors, then renders the one custom cursor the app
# makes and looks at its pixels.
Add-Type -AssemblyName System.Drawing, System.Windows.Forms
Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class CS {
    public delegate bool EnumProc(IntPtr h, IntPtr l);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
    [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr p, EnumProc cb, IntPtr l);
    [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint msg, IntPtr w, IntPtr l);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint dx, uint dy, uint d, UIntPtr e);
    [DllImport("user32.dll")] public static extern bool GetCursorInfo(out CURSORINFO ci);
    [DllImport("user32.dll", CharSet=CharSet.Unicode, EntryPoint="LoadCursorW")]
    public static extern IntPtr LoadCursorRes(IntPtr h, ushort id);
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int left, top, right, bottom; }
    [StructLayout(LayoutKind.Sequential)] public struct PT { public int x, y; }
    [StructLayout(LayoutKind.Sequential)] public struct CURSORINFO {
        public int cbSize; public int flags; public IntPtr hCursor; public PT pt;
    }
}
"@

$LEFTDOWN = 0x0002; $LEFTUP = 0x0004
$IDC = @{ ARROW = 32512; IBEAM = 32513; CROSS = 32515; SIZENWSE = 32642;
          SIZENESW = 32643; SIZEWE = 32644; SIZENS = 32645; SIZEALL = 32646 }

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
    Start-Sleep -Milliseconds 160
}
function Drag([int]$x1, [int]$y1, [int]$x2, [int]$y2) {
    MoveTo $x1 $y1
    [void][CS]::mouse_event($LEFTDOWN, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 120
    for ($i = 1; $i -le 12; $i++) {
        MoveTo ([int]($x1 + ($x2-$x1) * $i / 12)) ([int]($y1 + ($y2-$y1) * $i / 12))
    }
    Start-Sleep -Milliseconds 150
    [void][CS]::mouse_event($LEFTUP, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 350
}
function Click([int]$x, [int]$y) {
    MoveTo $x $y
    [void][CS]::mouse_event($LEFTDOWN, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 120
    [void][CS]::mouse_event($LEFTUP, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 350
}
function Find-Wins([string]$title) {
    $found = New-Object System.Collections.ArrayList
    $cb = [CS+EnumProc] {
        param($h, $l)
        $t = New-Object System.Text.StringBuilder 256
        [void][CS]::GetWindowText($h, $t, 256)
        if ($t.ToString() -eq $title) { [void]$found.Add($h) }
        return $true
    }
    [void][CS]::EnumWindows($cb, [IntPtr]::Zero)
    return $found.ToArray()
}
function Find-Kids([IntPtr]$parent, [string]$title) {
    $found = New-Object System.Collections.ArrayList
    $cb = [CS+EnumProc] {
        param($h, $l)
        $t = New-Object System.Text.StringBuilder 256
        [void][CS]::GetWindowText($h, $t, 256)
        if ($t.ToString() -eq $title -and [CS]::IsWindowVisible($h)) { [void]$found.Add($h) }
        return $true
    }
    [void][CS]::EnumChildWindows($parent, $cb, [IntPtr]::Zero)
    return $found.ToArray()
}
function Rect-Of([IntPtr]$h) {
    $r = New-Object CS+RECT
    [void][CS]::GetWindowRect($h, [ref]$r)
    return $r
}
# The cursor Windows has put up right now, as a name when it is one of the stock
# ones and as 'custom' when the app made it itself.
function Cursor-Name {
    $ci = New-Object CS+CURSORINFO
    $ci.cbSize = [System.Runtime.InteropServices.Marshal]::SizeOf([type][CS+CURSORINFO])
    if (-not [CS]::GetCursorInfo([ref]$ci)) { return '<GetCursorInfo failed>' }
    foreach ($k in $IDC.Keys) {
        if ($ci.hCursor -eq [CS]::LoadCursorRes([IntPtr]::Zero, $IDC[$k])) { return $k }
    }
    return 'custom'
}
function Cursor-Handle {
    $ci = New-Object CS+CURSORINFO
    $ci.cbSize = [System.Runtime.InteropServices.Marshal]::SizeOf([type][CS+CURSORINFO])
    [void][CS]::GetCursorInfo([ref]$ci)
    return $ci.hCursor
}
function Expect([string]$where, [int]$x, [int]$y, [string]$want) {
    MoveTo $x $y
    $got = Cursor-Name
    "  ($x,$y) $where -> $got (want $want)"
    if ($got -ne $want) { $script:fail += "$where shows $got, want $want" }
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
[void][CS]::PostMessage($sink[0], 0x8002, [IntPtr]::Zero, [IntPtr]::Zero)
Start-Sleep -Seconds 2

Drag $sel[0] $sel[1] $sel[2] $sel[3]
$ov = @(Find-Wins 'WinShotOverlay')
if ($ov.Count -eq 0) { 'FAIL: no overlay window'; exit 1 }

# The bar re-lays itself out when a tool opens the property bar under it, so its
# rect is read again every time rather than once.
function Toolbar-Rect {
    $t = @(Find-Kids $ov[0] 'WinShotToolbar')
    if ($t.Count -eq 0) { return $null }
    return Rect-Of $t[0]
}
function Click-Slot([int]$i) {
    $t = Toolbar-Rect
    if (-not $t) { return }
    $s = ($t.bottom - $t.top) / 32.0
    $cell = [int][Math]::Round(27 * $s); $pad = [int][Math]::Round(4 * $s)
    Click ($t.left + $pad + $i * $cell + [int]($cell / 2)) ([int](($t.top + $t.bottom) / 2))
}

"--- the arrow, wherever a press would do nothing ---"
Expect 'outside the region' 1900 1500 'ARROW'
$tb = Toolbar-Rect
if (-not $tb) { 'FAIL: no toolbar'; exit 1 }
Expect 'over the toolbar' ([int](($tb.left + $tb.right) / 2)) ([int](($tb.top + $tb.bottom) / 2)) 'ARROW'

# Slot 0 is the rectangle tool; arming it opens the 粗细/颜色 bar.
Click-Slot 0
$pb = @(Find-Kids $ov[0] 'WinShotPropBar')
if ($pb.Count -eq 0) { 'FAIL: arming the rectangle tool did not open the property bar'; exit 1 }
$pr = Rect-Of $pb[0]
Expect 'over the colour and width bar' ([int](($pr.left + $pr.right) / 2)) ([int](($pr.top + $pr.bottom) / 2)) 'ARROW'

"--- the crosshair, where a press starts a shape ---"
Expect 'inside the region, tool armed' 1150 800 'custom'

"--- the four-way cross, where a press moves something ---"
# A rectangle to move, drawn with the tool still armed.
Drag 900 700 1000 800
Click-Slot 0   # disarm, so a press on the ink moves rather than draws
Expect 'over drawn ink' 950 700 'SIZEALL'
Expect 'on the top-left corner' $sel[0] $sel[1] 'SIZENWSE'
Expect 'on the top edge midpoint' ([int](($sel[0] + $sel[2]) / 2)) $sel[1] 'SIZENS'
Expect '5px above the frame, away from a grip' 975 ($sel[1] - 5) 'SIZEALL'
Expect '5px below the frame, away from a grip' 975 ($sel[3] + 5) 'SIZEALL'
Expect 'far outside the frame' 1900 1500 'ARROW'

# With no tool armed, a press inside the region moves the selection or an
# element on it, so the whole interior is the four-way move cursor.
Expect 'inside, away from everything' 1300 900 'SIZEALL'

"--- the custom crosshair's own pixels ---"
# Re-armed and parked inside the region: the handle read below has to be the
# drawing crosshair's, so nothing may move the cursor after this.
Click-Slot 0
Expect 'inside the region, tool armed' 1150 800 'custom'
# White figure, dark rim, transparent elsewhere: a cross running the full canvas
# with a hollow square at its centre and no arrowheads.
$h = Cursor-Handle
$ico = [System.Drawing.Icon]::FromHandle($h)
$cb = $ico.ToBitmap()
"rendered cursor: $($cb.Width) x $($cb.Height)"
if ($cb.Width -ne 32 -or $cb.Height -ne 32) {
    $fail += "the drawing cursor renders as $($cb.Width)x$($cb.Height), want 32x32"
}
$art = ''
for ($y = 0; $y -lt $cb.Height; $y++) {
    $row = ''
    for ($x = 0; $x -lt $cb.Width; $x++) {
        $c = $cb.GetPixel($x, $y)
        if ($c.A -lt 40) { $row += '.' }
        elseif ($c.R -gt 128 -and $c.G -gt 128 -and $c.B -gt 128) { $row += '#' }
        else { $row += '+' }
    }
    $art += "$row`n"
}
$art
function Px([int]$x, [int]$y) { return $cb.GetPixel($x, $y) }
function IsWhite([int]$x, [int]$y) {
    $c = Px $x $y
    return ($c.A -gt 200 -and $c.R -gt 128 -and $c.G -gt 128 -and $c.B -gt 128)
}
function IsDark([int]$x, [int]$y) { $c = Px $x $y; return ($c.A -gt 200 -and $c.R -le 128) }
function IsClear([int]$x, [int]$y) { return ((Px $x $y).A -lt 40) }

foreach ($p in @(@(16,16), @(0,15), @(0,16), @(31,15), @(15,0), @(16,0), @(15,31))) {
    if (-not (IsWhite $p[0] $p[1])) {
        $fail += "the cross does not reach ($($p[0]),$($p[1]))"
    }
}
foreach ($p in @(@(12,12), @(19,12), @(12,19), @(19,19))) {
    if (-not (IsWhite $p[0] $p[1])) { $fail += "the centre square is missing ($($p[0]),$($p[1]))" }
}
if (-not (IsDark 14 14)) { $fail += 'the centre square is not hollow at (14,14)' }
foreach ($p in @(@(5,5), @(26,26), @(5,26), @(26,5))) {
    if (-not (IsClear $p[0] $p[1])) { $fail += "($($p[0]),$($p[1])) should be transparent, not a filled box" }
}
# Arrowheads would put ink in the corners of the canvas; a plain cross leaves the
# off-axis corners clear, which is the difference the request asks for.
$sym = $true
for ($y = 0; $y -lt 32; $y++) {
    for ($x = 0; $x -lt 32; $x++) {
        if ((Px $x $y).ToString() -ne (Px (31 - $x) (31 - $y)).ToString()) { $sym = $false }
    }
}
"figure symmetric about the hotspot: $sym"
if (-not $sym) { $fail += 'the drawing cursor is not centred on its hotspot' }

$cb.Dispose(); $ico.Dispose()

if (-not $proc.HasExited) { $proc.Kill() }
if ($fail.Count) { "FAILURES: $($fail.Count)"; $fail | ForEach-Object { "  $_" }; exit 1 }
'PASS'
