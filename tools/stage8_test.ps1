Add-Type -AssemblyName System.Drawing, System.Windows.Forms
Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class W8 {
    public delegate bool EnumProc(IntPtr h, IntPtr l);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
    [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr p, EnumProc cb, IntPtr l);
    [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint msg, IntPtr w, IntPtr l);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint dx, uint dy, int d, UIntPtr e);
    [DllImport("user32.dll")] public static extern IntPtr WindowFromPoint(POINT p);
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int left, top, right, bottom; }
    [StructLayout(LayoutKind.Sequential)] public struct POINT { public int x, y; }
}
"@

$LEFTDOWN = 0x0002; $LEFTUP = 0x0004
$HOTKEY = 0x8002   # WM_APP + 2: the tray's "take a capture"

# Toolbar slot x, mirrored from CToolbarWnd::BuildLayout: 4px pad, 27px cells,
# two 14px separators (after 序号 and after 保存).
$PAD = 4; $CELL = 27; $SEP = 14
function SlotX([int]$barLeft, [int]$idx) {
    $seps = 0
    if ($idx -ge 7) { $seps = 1 }
    if ($idx -ge 13) { $seps = 2 }
    return $barLeft + $PAD + $idx * $CELL + $seps * $SEP
}

function Grab([string]$path) {
    $b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    $bmp = New-Object System.Drawing.Bitmap $b.Width, $b.Height
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen($b.Location, [System.Drawing.Point]::Empty, $bmp.Size)
    $bmp.Save($path)
    $g.Dispose()
    return $bmp
}
function MoveTo([int]$x, [int]$y) {
    [System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point($x, $y)
    Start-Sleep -Milliseconds 100
}
function Click([int]$x, [int]$y) {
    MoveTo $x $y
    [void][W8]::mouse_event($LEFTDOWN, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 120
    [void][W8]::mouse_event($LEFTUP, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 350
}
function Drag([int]$x0, [int]$y0, [int]$x1, [int]$y1) {
    MoveTo $x0 $y0
    [void][W8]::mouse_event($LEFTDOWN, 0, 0, 0, [UIntPtr]::Zero)
    $steps = 8
    for ($i = 1; $i -le $steps; $i++) {
        MoveTo ([int]($x0 + ($x1 - $x0) * $i / $steps)) ([int]($y0 + ($y1 - $y0) * $i / $steps))
    }
    [void][W8]::mouse_event($LEFTUP, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 400
}
# An injected mouse wheel is routed by focus, not by cursor position, so it
# never lands on the window under the hole. Post the same message the overlay
# forwards to that window instead: what is under test is the stitcher's polling.
function WheelTo($hwnd, [int]$delta, [int]$x, [int]$y) {
    $w = [IntPtr]($delta -shl 16)
    $l = [IntPtr]((($y -shl 16) -bor ($x -band 0xFFFF)))
    [void][W8]::PostMessage($hwnd, 0x020A, $w, $l)
    # The posted message only runs when this thread pumps; sleeping leaves it
    # sitting in the queue.
    [System.Windows.Forms.Application]::DoEvents()
    Start-Sleep -Milliseconds 500
    [System.Windows.Forms.Application]::DoEvents()
}
function Find-Win([string]$title) {
    $found = New-Object System.Collections.ArrayList
    $cb = [W8+EnumProc] {
        param($h, $l)
        $t = New-Object System.Text.StringBuilder 512
        [void][W8]::GetWindowText($h, $t, 512)
        if ($t.ToString() -eq $title) { [void]$found.Add($h) }
        return $true
    }
    [void][W8]::EnumWindows($cb, [IntPtr]::Zero)
    return @($found)
}
function Hit-Point([int]$x, [int]$y) {
    $p = New-Object W8+POINT
    $p.x = $x; $p.y = $y
    return [W8]::WindowFromPoint($p)
}
function Title($h) {
    if ($h -eq [IntPtr]::Zero) { return '(null)' }
    $t = New-Object System.Text.StringBuilder 512
    [void][W8]::GetWindowText($h, $t, 512)
    return "$($h)[$($t.ToString())]"
}
function Win-Rect($h) {
    $r = New-Object W8+RECT
    if (-not [W8]::GetWindowRect($h, [ref]$r)) { return $null }
    return @{ left = $r.left; top = $r.top; right = $r.right; bottom = $r.bottom }
}
function VisibleBars($parent) {
    $list = New-Object System.Collections.ArrayList
    $cb = [W8+EnumProc] {
        param($h, $l)
        if ([W8]::IsWindowVisible($h)) {
            $r = New-Object W8+RECT
            if ([W8]::GetWindowRect($h, [ref]$r)) {
                if (($r.right - $r.left) -gt 40 -and ($r.bottom - $r.top) -gt 10) {
                    [void]$list.Add(@{ h = $h; left = $r.left; top = $r.top;
                                       right = $r.right; bottom = $r.bottom })
                }
            }
        }
        return $true
    }
    [void][W8]::EnumChildWindows($parent, $cb, [IntPtr]::Zero)
    return $list
}
function Toolbar($overlay) {
    $bars = @(VisibleBars $overlay)
    if ($bars.Count -eq 0) { return $null }
    return @($bars | Sort-Object { ($_.right - $_.left) } -Descending)[0]
}
# Channel distance between $a[$ax,$ay] and $b[$bx,$by]. (Not "Diff": that is
# Compare-Object's built-in alias, and an unqualified call binds to it.)
function Dpx($a, $ax, $ay, $b, $bx, $by) {
    $p = $a.GetPixel($ax, $ay); $q = $b.GetPixel($bx, $by)
    return [Math]::Abs($p.R - $q.R) + [Math]::Abs($p.G - $q.G) + [Math]::Abs($p.B - $q.B)
}
# Fraction of a 5x10 grid of points in the image band at rows [$y0,$y1) that
# disagree with the desktop shot at the matching screen position.
function MismatchRate($img, $shot, [int]$iy0, [int]$iy1, [int]$sx, [int]$sy) {
    $bad = 0; $n = 0
    for ($r = 0; $r -lt 5; $r++) {
        $y = [int]($iy0 + ($iy1 - $iy0) * $r / 4)
        for ($c = 0; $c -lt 10; $c++) {
            $x = [int](30 + 40 * $c / 9)
            $n++
            if ((Dpx $img $x $y $shot ($sx + $x) ($sy + ($y - $iy0))) -gt 24) { $bad++ }
        }
    }
    return ($bad / $n)
}

$fail = @()

Get-Process winshot -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 600
Get-ChildItem 'D:\Project\winshot\obj\s8_*.png' -ErrorAction SilentlyContinue | Remove-Item -Force

# A scrollable target with known content: 60 numbered lines in a read-only edit,
# so a wheel notch moves the text a predictable ~100px and the stitched result
# can be checked against screenshots of the desktop before and after scrolling.
$FX = 2200; $FY = 300; $FW = 900; $FH = 700
$sample = New-Object System.Windows.Forms.Form
$sample.Text = 'WinShotScrollSample'
$sample.FormBorderStyle = 'FixedSingle'
$sample.StartPosition = 'Manual'
$sample.Location = New-Object System.Drawing.Point($FX, $FY)
$sample.Size = New-Object System.Drawing.Size($FW, $FH)
$sample.BackColor = [System.Drawing.Color]::White
$box = New-Object System.Windows.Forms.TextBox
$box.Multiline = $true
$box.ReadOnly = $true
$box.ScrollBars = 'Vertical'
$box.Dock = 'Fill'
$box.Font = New-Object System.Drawing.Font('Consolas', 22)
$box.Text = (1..60 | ForEach-Object { 'LINE {0:D2} ------------------------------' -f $_ }) -join "`r`n"
[void]$sample.Controls.Add($box)
$sample.Show()
[System.Windows.Forms.Application]::DoEvents()
Start-Sleep -Milliseconds 800
[void][W8]::SetForegroundWindow($sample.Handle)
[System.Windows.Forms.Application]::DoEvents()
# Focusing an edit selects all its text, and the blue highlight repaints every
# row the stitcher is comparing. Clear it so the target looks the same before and
# after the capture takes focus away.
$box.Select(0, 0)
[System.Windows.Forms.Application]::DoEvents()
# One text line in pixels, measured while the box is still at the top: the
# stitched document has to grow by exactly the distance the box scrolled.
$LINEH = $box.GetPositionFromCharIndex(40).Y - $box.GetPositionFromCharIndex(0).Y
$CHARDOT = 40   # one "LINE nn ---" row plus its CRLF

$before = Grab 'D:\Project\winshot\obj\s8_before.png'

$proc = Start-Process -FilePath 'D:\Project\winshot\x64\Debug\winshot.exe' -PassThru
Start-Sleep -Seconds 2
$sink = @(Find-Win 'WinShotSink')
if ($sink.Count -eq 0) { "FAIL: no sink window"; exit 1 }

[void][W8]::PostMessage($sink[0], $HOTKEY, [IntPtr]::Zero, [IntPtr]::Zero)
Start-Sleep -Seconds 2
$ov = @(Find-Win 'WinShotOverlay')
if ($ov.Count -eq 0) { "FAIL: no overlay window"; exit 1 }

$SX0 = 2250; $SY0 = 350; $SX1 = 3050; $SY1 = 950
$SW = $SX1 - $SX0; $SH = $SY1 - $SY0
Drag $SX0 $SY0 $SX1 $SY1
$bar = Toolbar $ov[0]
if (-not $bar) { "FAIL: no toolbar after the drag"; exit 1 }
"selection $SX0,$SY0 .. $SX1,$SY1  toolbar $($bar.left),$($bar.top) .. $($bar.right),$($bar.bottom)"

# --- enter 长截图 -----------------------------------------------------------
$lsX = (SlotX $bar.left 8) + [int]($CELL / 2)
$lsY = [int](($bar.top + $bar.bottom) / 2)
"long-shot slot at $lsX,$lsY"
Click $lsX $lsY

$lbar = @(Find-Win 'WinShotLongBar')
$ltip = @(Find-Win 'WinShotLongTip')
"long bar: $($lbar.Count)  long tip: $($ltip.Count)"
if ($lbar.Count -eq 0 -or $ltip.Count -eq 0) { "FAIL: no long-shot popups"; exit 1 }
if (@(VisibleBars $ov[0]).Count -ne 0) { $fail += 'the capture toolbar is still visible in 长截图' }

$lb = Win-Rect $lbar[0]
$lt = Win-Rect $ltip[0]
"long bar rect: $($lb.left),$($lb.top) .. $($lb.right),$($lb.bottom)  (want right=$($SX1-2) top=$($SY1+5))"
"long tip rect: $($lt.left),$($lt.top) .. $($lt.right),$($lt.bottom)"
if ($lb.right -ne ($SX1 - 2) -or $lb.top -ne ($SY1 + 5)) { $fail += 'the long-shot bar is not at hole.right-2 / hole.bottom+5' }
if ($lt.left -lt $SX0 -or $lt.right -gt $SX1 -or $lt.top -lt $SY0 -or $lt.bottom -gt $SY1) {
    $fail += 'the tip card is not inside the hole'
}

# The hole has to show the live desktop while everything around it stays dimmed:
# a pixel inside it still matches the pre-capture shot, one outside does not.
# Far left, because the stitched preview panel is drawn in the dim band next to
# the hole (it flips left when there is no room on the right).
$shot = Grab 'D:\Project\winshot\obj\s8_hole.png'
$inHole = Dpx $before ($SX0 + 40) ($SY0 + 40) $shot ($SX0 + 40) ($SY0 + 40)
$dim = [Math]::Abs($before.GetPixel(2600, 310).R - $shot.GetPixel(2600, 310).R)
"inside the hole: diff=$inHole (want ~0)   outside: alpha step=$dim (want >0)"
if ($inHole -gt 24) { $fail += 'the hole does not show the live desktop' }
if ($dim -eq 0) { $fail += 'the area outside the hole is not dimmed' }
# The hole is cut out of the overlay's window region, so hit-testing a point
# inside it lands on the target window rather than on us — that is what lets the
# wheel through to the window being scrolled.
$under = Hit-Point ($SX0 + 60) ($SY0 + 60)
"point in the hole -> " + (Title $under) + "  (want the sample edit $(Title $box.Handle))"
if ($under -ne $box.Handle) { $fail += 'the hole does not let input through to the window underneath' }

# --- scroll and stitch ------------------------------------------------------
# The wheel has to reach the window under the cursor, which the hole lets
# through. Focus goes with it, so clear the select-all highlight again.
[void][W8]::SetForegroundWindow($sample.Handle)
[System.Windows.Forms.Application]::DoEvents()
$box.Select(0, 0)
[System.Windows.Forms.Application]::DoEvents()
$topAt = { $box.GetCharIndexFromPosition((New-Object System.Drawing.Point(5, 5))) }
$topBefore = & $topAt
"top char before scrolling = $topBefore"
for ($i = 0; $i -lt 6; $i++) { WheelTo $box.Handle (-120 * 3) ($SX0 + 60) ($SY0 + 60) }
$topAfter = & $topAt
"top char after scrolling  = $topAfter"
Start-Sleep -Milliseconds 800
$after = Grab 'D:\Project\winshot\obj\s8_after.png'

# --- 编辑 back into the editor, then ✓ to the clipboard ---------------------
$editX = $lb.left + 22
$editY = [int](($lb.top + $lb.bottom) / 2)
"编辑 at $editX,$editY"
Click $editX $editY
Start-Sleep -Milliseconds 600
"long bar after 编辑: $(@(Find-Win 'WinShotLongBar').Count) (want 0)"
if (@(Find-Win 'WinShotLongBar').Count -ne 0) { $fail += '编辑 left the long-shot bar up' }
$ov2 = @(Find-Win 'WinShotOverlay')
if ($ov2.Count -eq 0) { "FAIL: 编辑 closed the capture"; exit 1 }
$bar2 = Toolbar $ov2[0]
$edit = Grab 'D:\Project\winshot\obj\s8_edit.png'
# Below the fold the selection now covers rows that were never on screen: they
# have to show the stitched document, not the dimmed live desktop from 长截图.
$stale = 0
foreach ($y in @(1100, 1300, 1450, 1600)) {
    $c = $edit.GetPixel(2600, $y); $s0 = $shot.GetPixel(2600, $y)
    $d = [Math]::Abs($c.R - $s0.R) + [Math]::Abs($c.G - $s0.G) + [Math]::Abs($c.B - $s0.B)
    "  below the fold y=$y after 编辑=$($c.R),$($c.G),$($c.B)  dimmed desktop was=$($s0.R),$($s0.G),$($s0.B)"
    if ($d -lt 40) { $stale++ }
}
if ($stale) { $fail += "the grown selection still shows the dimmed desktop at $stale of 4 rows below the fold" }
if (-not $bar2) { $fail += 'the capture toolbar did not come back after 编辑' }
if ($bar2) {
    # The stitched document runs past the bottom of the screen, so the toolbar
    # flips to the other side of the selection: bottom edge 2px above its top.
    "toolbar after 编辑: $($bar2.left),$($bar2.top) .. $($bar2.right),$($bar2.bottom) (want bottom=$($SY0-2))"
    if ($bar2.bottom -ne ($SY0 - 2) -or $bar2.top -ne ($SY0 - 34)) {
        $fail += 'the toolbar did not follow the grown selection'
    }
}

if (-not $bar2) { "FAIL: no toolbar to finish with"; exit 1 }
[System.Windows.Forms.Clipboard]::SetText('EMPTY')
Start-Sleep -Milliseconds 200
$doneX = (SlotX $bar2.left 14) + [int]($CELL / 2)
$doneY = [int](($bar2.top + $bar2.bottom) / 2)
"✓ at $doneX,$doneY"
Click $doneX $doneY
Start-Sleep -Milliseconds 800
"overlay after ✓: $(@(Find-Win 'WinShotOverlay').Count) (want 0)"
if (@(Find-Win 'WinShotOverlay').Count -gt 0) { $fail += '✓ left the capture up' }
# Clipboard::GetImage() comes back null for what winshot puts there; the format
# pair has to be read off the data object (the same way stage 4 checks it).
$do = [System.Windows.Forms.Clipboard]::GetDataObject()
$fmts = if ($do) { $do.GetFormats() -join ', ' } else { '(none)' }
"clipboard formats: $fmts"
$clip = $null
if ($do -and $do.GetDataPresent([System.Windows.Forms.DataFormats]::Bitmap)) {
    $clip = $do.GetData([System.Windows.Forms.DataFormats]::Bitmap)
}
if (-not $clip) { "FAIL: no image on the clipboard"; exit 1 }
# The box scrolled ($topAfter - $topBefore)/$CHARDOT lines, so the document has
# to be the original selection plus exactly that many text lines.
$lines = ($topAfter - $topBefore) / $CHARDOT
$wantH = [int]($SH + $lines * $LINEH)
"clipboard image: $($clip.Width) x $($clip.Height)  (want width=$SW, height~$wantH = $SH + $lines lines x $LINEH px)"
if ($clip.Width -ne $SW) { $fail += "stitched width is $($clip.Width), want $SW" }
if ($clip.Height -le $SH + 300) { $fail += "stitched height $($clip.Height) did not grow enough past $SH" }
if ([Math]::Abs($clip.Height - $wantH) -gt 2 * $LINEH) {
    $fail += "stitched height $($clip.Height) is not the $([Math]::Round($lines, 1))-line scroll of the target (want $wantH)"
}
$c = $clip.Clone([System.Drawing.Rectangle]::new(0, 0, $clip.Width, $clip.Height), $clip.PixelFormat)
$c.Save('D:\Project\winshot\obj\s8_result.png'); $c.Dispose()

# The top of the document is the view as it stood before scrolling, the bottom is
# the view after it, and the top is *not* the view after it — that is the whole
# claim of stitching, checked against two screenshots of the real desktop.
$topVsBefore = MismatchRate $clip $before 0 40 $SX0 $SY0
$botVsAfter = MismatchRate $clip $after ($clip.Height - 40) ($clip.Height - 6) $SX0 ($SY1 - 40)
$topVsAfter = MismatchRate $clip $after 0 40 $SX0 $SY0
$scrolled = MismatchRate $before $after 0 40 $SX0 $SY0
# Every line of the target reads the same but for its number, and the scroll is
# a whole number of lines, so the absolute rate is small; the claim is that the
# top of the document agrees with the pre-scroll desktop and disagrees with the
# post-scroll one by as much as those two desktops disagree with each other.
"top rows vs pre-scroll desktop: mismatch $([Math]::Round($topVsBefore * 100))% (want 0%)"
"bottom rows vs post-scroll desktop: mismatch $([Math]::Round($botVsAfter * 100))% (want 0%)"
"top rows vs post-scroll desktop: mismatch $([Math]::Round($topVsAfter * 100))% (the two desktops differ by $([Math]::Round($scrolled * 100))%)"
if ($topVsBefore -gt 0.05) { $fail += 'the top of the stitched image is not the pre-scroll view' }
if ($botVsAfter -gt 0.05) { $fail += 'the bottom of the stitched image is not the post-scroll view' }
if ($scrolled -lt 0.1) { $fail += 'the target barely changed on screen, so the stitch proves nothing' }
if ($topVsAfter - $topVsBefore -lt 0.1) { $fail += 'the top of the stitched image is the post-scroll view' }

$sample.Close()
if ($proc -and -not $proc.HasExited) { $proc.Kill() }
if ($fail.Count) { "FAIL: " + ($fail -join '; '); exit 1 }
"PASS"
