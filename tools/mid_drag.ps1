# Every bug in this family is visible only while the button is still down. A
# shape being drawn or dragged is painted into the chrome buffer and blended onto
# the window, and the blend only carries the ground the repaint was told about.
# If that ground is smaller than the shape's ink, part of the shape never reaches
# the screen (an arrow with no head, a curve cut off) and part of where the shape
# used to be never goes away (a smear where the ellipse was dragged from).
#
# So each case drags to a point, grabs with the button down, releases without
# moving the cursor, and grabs again. The cursor has not moved between the two
# grabs, so the shape is the same shape: the grabs must agree pixel for pixel.
# Anything red in one and not the other is a bug, and its bounding box says
# which part went missing.
#
# Shapes from earlier cases stay on screen. They are static, so they are
# identical in both grabs and cancel out of the difference.
Add-Type -AssemblyName System.Drawing, System.Windows.Forms
$src = @"
using System;
using System.Text;
using System.Runtime.InteropServices;
using System.Drawing;
public static class MD {
    public delegate bool EnumProc(IntPtr h, IntPtr l);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
    [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr p, EnumProc cb, IntPtr l);
    [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint msg, IntPtr w, IntPtr l);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint dx, uint dy, uint d, UIntPtr e);
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int left, top, right, bottom; }

    public static bool IsRed(Color c) { return c.R > 190 && c.G < 120 && c.B < 130; }

    // {redInEither, redOnlyInA, redOnlyInB, minx, miny, maxx, maxy} over a box.
    public static int[] Diff(Bitmap a, Bitmap b, int l, int t, int r, int btm) {
        int n = 0, onlyA = 0, onlyB = 0;
        int minx = int.MaxValue, miny = int.MaxValue, maxx = -1, maxy = -1;
        for (int y = t; y <= btm; y++) {
            for (int x = l; x <= r; x++) {
                bool ra = IsRed(a.GetPixel(x, y)), rb = IsRed(b.GetPixel(x, y));
                if (ra || rb) n++;
                if (ra == rb) continue;
                if (ra) onlyA++; else onlyB++;
                if (x < minx) minx = x;
                if (y < miny) miny = y;
                if (x > maxx) maxx = x;
                if (y > maxy) maxy = y;
            }
        }
        if (maxx < 0) { minx = 0; miny = 0; }
        return new int[] { n, onlyA, onlyB, minx, miny, maxx, maxy };
    }
}
"@
# The diff takes Bitmaps, and the inline form of Add-Type does not reference
# System.Drawing on its own.
Add-Type -Language CSharp -ReferencedAssemblies @(
    'System', 'System.Core', 'System.Drawing', 'Microsoft.CSharp'
) -TypeDefinition $src

$LEFTDOWN = 0x0002; $LEFTUP = 0x0004
$sel = @(700, 550, 1700, 1250)
$fail = @()

function MoveTo([int]$x, [int]$y) {
    [System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point($x, $y)
    Start-Sleep -Milliseconds 90
}
function Down { [void][MD]::mouse_event($LEFTDOWN, 0, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 150 }
function Up { [void][MD]::mouse_event($LEFTUP, 0, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 350 }
function Click([int]$x, [int]$y) { MoveTo $x $y; Down; Up }
function Find-Wins([string]$title) {
    $found = New-Object System.Collections.ArrayList
    $cb = [MD+EnumProc] {
        param($h, $l)
        $t = New-Object System.Text.StringBuilder 256
        [void][MD]::GetWindowText($h, $t, 256)
        if ($t.ToString() -eq $title) { [void]$found.Add($h) }
        return $true
    }
    [void][MD]::EnumWindows($cb, [IntPtr]::Zero)
    return $found.ToArray()
}
function Rect-Of([IntPtr]$h) {
    $r = New-Object MD+RECT
    [void][MD]::GetWindowRect($h, [ref]$r)
    return $r
}
function Grab([string]$tag) {
    $b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    $bmp = New-Object System.Drawing.Bitmap $b.Width, $b.Height
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen($b.Location, [System.Drawing.Point]::Empty, $bmp.Size)
    $g.Dispose()
    $bmp.Save("D:\Project\winshot\obj\md_$tag.png")
    return $bmp
}
# A path the pointer walks with the button down. PowerShell flattens a nested
# array literal, so the points go in as a flat list of pairs.
function Pts([int[]]$flat) {
    $l = New-Object System.Collections.ArrayList
    for ($i = 0; $i -lt $flat.Count; $i += 2) { [void]$l.Add(@($flat[$i], $flat[$i + 1])) }
    return ,$l
}
# A straight drag walked in steps. One jump paints one intermediate frame and
# there is nothing to accumulate; a real drag crosses a dozen, and each one is
# ground the next repaint has to cover.
function Line([int]$x1, [int]$y1, [int]$x2, [int]$y2, [int]$steps) {
    $flat = @($x1, $y1)
    for ($i = 1; $i -le $steps; $i++) {
        $flat += [int]($x1 + ($x2 - $x1) * $i / $steps)
        $flat += [int]($y1 + ($y2 - $y1) * $i / $steps)
    }
    return ,(Pts $flat)
}
# Press and walk the path, stopping with the button down on the last point. The
# caller grabs there, then releases without moving the cursor.
function Press-Path($path) {
    MoveTo $path[0][0] $path[0][1]
    Down
    for ($i = 1; $i -lt $path.Count; $i++) { MoveTo $path[$i][0] $path[$i][1] }
    Start-Sleep -Milliseconds 300
}

function Case([string]$name, $mid, $after, $box) {
    $d = [MD]::Diff($mid, $after, $box[0], $box[1], $box[2], $box[3])
    $line = "{0,-14} ink={1,6}  mid-only={2,5}  after-only={3,5}" -f $name, $d[0], $d[1], $d[2]
    if ($d[1] -eq 0 -and $d[2] -eq 0) { Write-Output ($line + '  OK'); return }
    Write-Output ($line + ("  diff box=({0},{1})..({2},{3})" -f $d[3], $d[4], $d[5], $d[6]))
    # Ink only in the mid grab is the shape left behind where it was; ink only in
    # the after grab is shape that never made it to the screen while dragging.
    # Both are wrong by more than an antialiasing edge can explain.
    if ($d[1] -gt 400) { $script:fail += "$name : $(($d[1])) px of ink mid-drag that is gone after release, around ($($d[3]),$($d[4]))..($($d[5]),$($d[6]))" }
    if ($d[2] -gt 400) { $script:fail += "$name : $(($d[2])) px of ink missing mid-drag that appears on release, around ($($d[3]),$($d[4]))..($($d[5]),$($d[6]))" }
}

Get-Process winshot -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 600
$proc = Start-Process -FilePath 'D:\Project\winshot\x64\Debug\winshot.exe' -PassThru
Start-Sleep -Seconds 2
$sink = @(Find-Wins 'WinShotSink')
if ($sink.Count -eq 0) { 'FAIL: no sink window'; exit 1 }
[void][MD]::PostMessage($sink[0], 0x8002, [IntPtr]::Zero, [IntPtr]::Zero)
Start-Sleep -Seconds 2

MoveTo $sel[0] $sel[1]
Down
MoveTo $sel[2] $sel[3]
Up

$ov = @(Find-Wins 'WinShotOverlay')
if ($ov.Count -eq 0) { 'FAIL: no overlay window'; exit 1 }
$kids = New-Object System.Collections.ArrayList
$cb2 = [MD+EnumProc] {
    param($h, $l)
    $t = New-Object System.Text.StringBuilder 256
    [void][MD]::GetWindowText($h, $t, 256)
    if ($t.ToString() -eq 'WinShotToolbar') { [void]$kids.Add($h) }
    return $true
}
[void][MD]::EnumChildWindows($ov[0], $cb2, [IntPtr]::Zero)
if ($kids.Count -eq 0) { 'FAIL: no toolbar window under the overlay'; exit 1 }
$tr = Rect-Of $kids[0]
$scale = ($tr.bottom - $tr.top) / 32.0
$cell = [int][Math]::Round(27 * $scale)
$pad = [int][Math]::Round(4 * $scale)
$cy = [int](($tr.top + $tr.bottom) / 2)
# Slots 0..6 are the drawing tools and sit before the bar's first separator, so
# the pitch is exact there.
function ToolX([int]$slot) { return $tr.left + $pad + $slot * $cell + [int]($cell / 2) }

$script:armed = -1
function Tool([int]$slot) {
    if ($script:armed -eq $slot) { return }
    if ($script:armed -ge 0) { Click (ToolX $script:armed) $cy }
    Click (ToolX $slot) $cy
    $script:armed = $slot
}
function Disarm { if ($script:armed -ge 0) { Click (ToolX $script:armed) $cy; $script:armed = -1 } }

function Run-Case([string]$name, [int]$slot, $path, $box) {
    Tool $slot
    Press-Path $path
    $tag = $name -replace '\s', '_'
    $mid = Grab "${tag}_mid"
    Up
    $after = Grab "${tag}_after"
    Case $name $mid $after $box
    $mid.Dispose(); $after.Dispose()
}

# --- drawing a shape, with the button still down -----------------------------
Run-Case 'draw rect'    0 (Line 820 640 1050 800 6) @(780, 600, 1100, 850)
Run-Case 'draw ellipse' 1 (Line 1150 640 1450 880 6) @(1110, 600, 1500, 930)
Run-Case 'draw arrow'   2 (Line 820 900 1050 1050 6) @(780, 860, 1100, 1100)
Run-Case 'draw pen'     3 (Pts @(1200, 950, 1300, 900, 1400, 950, 1420, 1050,
                                 1320, 1090, 1220, 1050, 1210, 960)) @(1160, 860, 1470, 1140)
Disarm

# --- moving and resizing a shape that is already committed -------------------
# The ellipse above spans (1150,640)..(1450,880). Its upper-left arc at 135
# degrees is well clear of the eight handles on the box's corners and edge
# midpoints, so a press there moves the shape rather than resizing it.
$arc = @(1194, 675)
Click $arc[0] $arc[1]
Press-Path (Line $arc[0] $arc[1] ($arc[0] + 200) $arc[1] 6)
$m = Grab 'move_ellipse_mid'; Up; $a = Grab 'move_ellipse_after'
Case 'move ellipse' $m $a @(1110, 600, 1700, 930)
$m.Dispose(); $a.Dispose()

# Its top-left corner handle, now at (1350,640).
Press-Path (Line 1350 640 1290 590 6)
$m = Grab 'size_ellipse_mid'; Up; $a = Grab 'size_ellipse_after'
Case 'size ellipse' $m $a @(1240, 550, 1700, 930)
$m.Dispose(); $a.Dispose()

# The arrow, spanning (820,900)..(1050,1050): its shaft's midpoint moves it.
$shaft = @(935, 975)
Click $shaft[0] $shaft[1]
Press-Path (Line $shaft[0] $shaft[1] $shaft[0] ($shaft[1] + 120) 6)
$m = Grab 'move_arrow_mid'; Up; $a = Grab 'move_arrow_after'
Case 'move arrow' $m $a @(780, 860, 1100, 1230)
$m.Dispose(); $a.Dispose()

# Its head, now at (1050,1170): dragging that changes direction and length.
Press-Path (Line 1050 1170 1200 1100 6)
$m = Grab 'head_arrow_mid'; Up; $a = Grab 'head_arrow_after'
Case 'arrow head' $m $a @(780, 1000, 1260, 1230)
$m.Dispose(); $a.Dispose()

if (-not $proc.HasExited) { $proc.Kill() }
if ($fail.Count) { "FAILURES: $($fail.Count)"; $fail | ForEach-Object { "  $_" }; exit 1 }
'PASS'
