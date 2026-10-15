Add-Type -AssemblyName System.Drawing, System.Windows.Forms
Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class W7 {
    public delegate bool EnumProc(IntPtr h, IntPtr l);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
    [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr p, EnumProc cb, IntPtr l);
    [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint msg, IntPtr w, IntPtr l);
    [DllImport("user32.dll")] public static extern bool SendMessage(IntPtr h, uint msg, IntPtr w, IntPtr l);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr h, int idx);
    [DllImport("user32.dll")] public static extern bool MoveWindow(IntPtr h, int x, int y, int w, int ht, bool repaint);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
    [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint dx, uint dy, uint d, UIntPtr e);
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int left, top, right, bottom; }
}
"@

$LEFTDOWN = 0x0002; $LEFTUP = 0x0004
$WM_KEYDOWN = 0x0100; $WM_KEYUP = 0x0101; $VK_ESCAPE = 0x1B

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
    [void][W7]::mouse_event($LEFTDOWN, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 120
    [void][W7]::mouse_event($LEFTUP, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 350
}
function Drag([int]$x0, [int]$y0, [int]$x1, [int]$y1) {
    MoveTo $x0 $y0
    [void][W7]::mouse_event($LEFTDOWN, 0, 0, 0, [UIntPtr]::Zero)
    $steps = 8
    for ($i = 1; $i -le $steps; $i++) {
        MoveTo ([int]($x0 + ($x1 - $x0) * $i / $steps)) ([int]($y0 + ($y1 - $y0) * $i / $steps))
    }
    [void][W7]::mouse_event($LEFTUP, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 400
}
function Find-Win([string]$title) {
    $found = New-Object System.Collections.ArrayList
    $cb = [W7+EnumProc] {
        param($h, $l)
        $t = New-Object System.Text.StringBuilder 512
        [void][W7]::GetWindowText($h, $t, 512)
        if ($t.ToString() -eq $title) { [void]$found.Add($h) }
        return $true
    }
    [void][W7]::EnumWindows($cb, [IntPtr]::Zero)
    return @($found)
}
function Win-Rect($h) {
    $r = New-Object W7+RECT
    if (-not [W7]::GetWindowRect($h, [ref]$r)) { return $null }
    return @{ left = $r.left; top = $r.top; right = $r.right; bottom = $r.bottom }
}
# Reading another process's control text is not on the table: WM_GETTEXT with a
# raw pointer lands the text a couple of bytes off, and with a marshaler's buffer
# it never comes back at all. The child's class and rect are enough to drive it,
# and the clipboard is what proves the text itself.
function Children($parent) {
    $list = New-Object System.Collections.ArrayList
    $cb = [W7+EnumProc] {
        param($h, $l)
        $r = New-Object W7+RECT
        [void]$list.Add(@{ h = $h; cls = (Class-Of $h); vis = [W7]::IsWindowVisible($h)
                           w = 0; rect = $(if ([W7]::GetWindowRect($h, [ref]$r)) {
                               @{ left = $r.left; top = $r.top; right = $r.right; bottom = $r.bottom }
                           } else { $null }) })
        return $true
    }
    [void][W7]::EnumChildWindows($parent, $cb, [IntPtr]::Zero)
    return @($list)
}
# A redirected PowerShell 5.1 stdout is GBK; anything Chinese in it arrives here
# as mojibake. Code points are the only readable form of a Chinese string in
# this harness.
function Hex([string]$s) { ($s.ToCharArray() | ForEach-Object { '{0:X4}' -f [int]$_ }) -join ' ' }
function Class-Of($h) {
    $c = New-Object System.Text.StringBuilder 256
    [void][W7]::GetClassName($h, $c, 256)
    return $c.ToString()
}
function VisibleBars($parent) {
    $list = New-Object System.Collections.ArrayList
    $cb = [W7+EnumProc] {
        param($h, $l)
        if ([W7]::IsWindowVisible($h)) {
            $r = New-Object W7+RECT
            if ([W7]::GetWindowRect($h, [ref]$r)) {
                if (($r.right - $r.left) -gt 40 -and ($r.bottom - $r.top) -gt 10) {
                    [void]$list.Add(@{ h = $h; left = $r.left; top = $r.top;
                                       right = $r.right; bottom = $r.bottom })
                }
            }
        }
        return $true
    }
    [void][W7]::EnumChildWindows($parent, $cb, [IntPtr]::Zero)
    return $list
}
function Toolbar($overlay) {
    $bars = @(VisibleBars $overlay)
    if ($bars.Count -eq 0) { return $null }
    return @($bars | Sort-Object { ($_.right - $_.left) } -Descending)[0]
}

$fail = @()

Get-Process winshot -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 600
Get-ChildItem 'D:\Project\winshot\obj\s7_*.png' -ErrorAction SilentlyContinue | Remove-Item -Force

# Chinese literals are built from code points: Windows PowerShell reads a
# BOM-less script as ANSI, which turns them into mojibake.
function Cps([string]$hex) { -join ($hex -split ',' | ForEach-Object { [char][Convert]::ToInt32($_, 16) }) }
$OCR_TITLE = 'OCR ' + (Cps '8BC6,5B57,7ED3,679C')   # OCR 识字结果

# A window with big, known Chinese text: the OCR half has to recognise
# something we can name in advance.
$OCR_TEXT = Cps '4E2D,6587,8BC6,522B,6D4B,8BD5'  # 中文识别测试
$FX = 2400; $FY = 1200; $FW = 1000; $FH = 500
$sample = New-Object System.Windows.Forms.Form
$sample.Text = 'WinShotOcrSample'
$sample.FormBorderStyle = 'FixedSingle'
$sample.StartPosition = 'Manual'
$sample.Location = New-Object System.Drawing.Point($FX, $FY)
$sample.Size = New-Object System.Drawing.Size($FW, $FH)
$sample.BackColor = [System.Drawing.Color]::White
$sample.TopMost = $true
$lbl = New-Object System.Windows.Forms.Label
$lbl.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 42)
$lbl.Text = $OCR_TEXT
$lbl.Dock = 'Fill'
$lbl.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
[void]$sample.Controls.Add($lbl)
$sample.Show()
[System.Windows.Forms.Application]::DoEvents()
Start-Sleep -Milliseconds 800
[System.Windows.Forms.Application]::DoEvents()

$before = Grab 'D:\Project\winshot\obj\s7_before.png'

$proc = Start-Process -FilePath 'D:\Project\winshot\x64\Debug\winshot.exe' -PassThru
Start-Sleep -Seconds 2
$sink = @(Find-Win 'WinShotSink')
if ($sink.Count -eq 0) { "FAIL: no sink window"; exit 1 }

# --- part A: 钉在桌面上 -----------------------------------------------------
[void][W7]::PostMessage($sink[0], 0x8002, [IntPtr]::Zero, [IntPtr]::Zero)
Start-Sleep -Seconds 2
$ov = @(Find-Win 'WinShotOverlay')
if ($ov.Count -eq 0) { "FAIL: no overlay window"; exit 1 }

$SX0 = 1200; $SY0 = 800; $SX1 = 1800; $SY1 = 1200
Drag $SX0 $SY0 $SX1 $SY1
$bar = Toolbar $ov[0]
if (-not $bar) { "FAIL: no toolbar after the drag"; exit 1 }
"selection $SX0,$SY0 .. $SX1,$SY1  toolbar $($bar.left),$($bar.top) .. $($bar.right),$($bar.bottom)"

$pinX = (SlotX $bar.left 10) + [int]($CELL / 2)
$pinY = [int](($bar.top + $bar.bottom) / 2)
for ($try = 0; $try -lt 3; $try++) {
    Click $pinX $pinY
    if (@(Find-Win 'WinShotPin').Count -gt 0) { break }
}
Start-Sleep -Milliseconds 600
$pins = @(Find-Win 'WinShotPin')
"pin windows: $($pins.Count)"
if ($pins.Count -eq 0) { "FAIL: no pin window"; exit 1 }
$pr = Win-Rect $pins[0]
"pin rect: $($pr.left),$($pr.top) .. $($pr.right),$($pr.bottom)  (want $SX0,$SY0 .. $SX1,$SY1)"
if ($pr.left -ne $SX0 -or $pr.top -ne $SY0 -or $pr.right -ne $SX1 -or $pr.bottom -ne $SY1) {
    $fail += 'pin window is not at the selection rect'
}
if (@(Find-Win 'WinShotOverlay').Count -gt 0) { $fail += 'overlay still open after pinning' }

# The pin shows the frozen still, so its pixels have to match the desktop as it
# looked before the hotkey. The 1px edge pen is skipped.
$after = Grab 'D:\Project\winshot\obj\s7_pin.png'
$diff = 0; $worst = 0
foreach ($p in @( @(0.25, 0.25), @(0.75, 0.25), @(0.5, 0.5), @(0.25, 0.75), @(0.75, 0.75) )) {
    $x = [int]($pr.left + ($pr.right - $pr.left) * $p[0])
    $y = [int]($pr.top + ($pr.bottom - $pr.top) * $p[1])
    $a = $before.GetPixel($x, $y); $b = $after.GetPixel($x, $y)
    $d = [Math]::Abs($a.R - $b.R) + [Math]::Abs($a.G - $b.G) + [Math]::Abs($a.B - $b.B)
    if ($d -gt $worst) { $worst = $d }
    if ($d -gt 24) { $diff++ }
}
"pin pixel mismatches: $diff/5 worst=$worst (want 0)"
if ($diff -gt 0) { $fail += 'pin image does not match the frozen still' }
$r = New-Object System.Drawing.Rectangle (($pr.left - 4), ($pr.top - 4), ($pr.right - $pr.left + 8), ($pr.bottom - $pr.top + 8))
$c = $after.Clone($r, $after.PixelFormat); $c.Save('D:\Project\winshot\obj\s7_pin_crop.png'); $c.Dispose()

[void][W7]::SetForegroundWindow($pins[0])
Start-Sleep -Milliseconds 300
[void][W7]::PostMessage($pins[0], $WM_KEYDOWN, [IntPtr]$VK_ESCAPE, [IntPtr]::Zero)
[void][W7]::PostMessage($pins[0], $WM_KEYUP, [IntPtr]$VK_ESCAPE, [IntPtr]::Zero)
Start-Sleep -Milliseconds 600
$left = @(Find-Win 'WinShotPin').Count
"pin windows after Esc: $left (want 0)"
if ($left -gt 0) { $fail += 'Esc did not close the pin' }

# --- part B: OCR 识字 -------------------------------------------------------
[void][W7]::PostMessage($sink[0], 0x8002, [IntPtr]::Zero, [IntPtr]::Zero)
Start-Sleep -Seconds 2
$ov = @(Find-Win 'WinShotOverlay')
if ($ov.Count -eq 0) { "FAIL: no overlay window for the OCR run"; exit 1 }

$OX0 = $FX + 30; $OY0 = $FY + 40; $OX1 = $FX + $FW - 20; $OY1 = $FY + $FH - 20
Drag $OX0 $OY0 $OX1 $OY1
$bar = Toolbar $ov[0]
if (-not $bar) { "FAIL: no toolbar for the OCR run"; exit 1 }
$ocrX = (SlotX $bar.left 9) + [int]($CELL / 2)
$ocrY = [int](($bar.top + $bar.bottom) / 2)
"ocr slot at $ocrX,$ocrY"
Click $ocrX $ocrY
if (@(VisibleBars $ov[0]).Count -eq 0) { $fail += 'the capture closed on OCR' }

$ocr = @()
for ($i = 0; $i -lt 30; $i++) {
    Start-Sleep -Milliseconds 500
    $ocr = @(Find-Win $OCR_TITLE)
    if ($ocr.Count -gt 0) { break }
}
"ocr result window after $(($i + 1) * 500)ms: $($ocr.Count)"
if ($ocr.Count -eq 0) {
    $fail += 'no OCR result window'
} else {
    $kids = Children $ocr[0]
    $edits = @($kids | Where-Object { $_.cls -eq 'Edit' })
    $btns = @($kids | Where-Object { $_.cls -eq 'Button' -and $_.rect })
    "ocr window visible=$([W7]::IsWindowVisible($ocr[0])) children=$($kids.Count): " +
        (($kids | ForEach-Object { "$($_.cls)$(if ($_.vis) { '' } else { '(hidden)' }) w=$($_.rect.right - $_.rect.left)" }) -join ' ')
    if ($edits.Count -ne 1 -or -not $edits[0].vis) { $fail += 'no visible edit in the OCR window' }
    if ($btns.Count -ne 2) { $fail += "expected two buttons in the OCR window, got $($btns.Count)" }

    # 复制到剪贴板 is the wider of the two buttons (132 against 72 logical px),
    # which identifies it without reading another process's control text. The
    # clipboard it fills is the only readable copy of the recognised text, so
    # that click is also what proves the engine returned something.
    $copy = $null
    if ($btns.Count -ge 2) {
        $copy = @($btns | Sort-Object { ($_.rect.right - $_.rect.left) } -Descending)[0]
    }
    if (-not $copy) {
        $fail += 'no copy button in the OCR window'
    } else {
        # Without this the assertion could ride on whatever the last test left
        # on the clipboard.
        [System.Windows.Forms.Clipboard]::SetText('EMPTY')
        Start-Sleep -Milliseconds 200
        $br = $copy.rect
        $clip = ''
        for ($try = 0; $try -lt 3; $try++) {
            Click ([int](($br.left + $br.right) / 2)) ([int](($br.top + $br.bottom) / 2))
            Start-Sleep -Milliseconds 400
            try { $clip = [System.Windows.Forms.Clipboard]::GetText() } catch { }
            if ($clip -and $clip -ne 'EMPTY') { break }
        }
        "clipboard code points: $(Hex $clip)"
        if (-not $clip -or $clip -eq 'EMPTY') {
            $fail += 'copy button did not put anything on the clipboard'
        } else {
            # Windows OCR separates every word segment it finds with a space and
            # misreads the occasional glyph (别 came back as 设+刂), so the bar is
            # "recognised this text", not "returned it character for character".
            $flat = $clip -replace '\s', ''
            $hit = 0
            foreach ($ch in $OCR_TEXT.ToCharArray()) {
                if ($flat.Contains([string]$ch)) { $hit++ }
            }
            "recognised $hit/$($OCR_TEXT.Length) sample characters"
            if ($hit -lt $OCR_TEXT.Length - 1) {
                $fail += "OCR read only $hit of $($OCR_TEXT.Length) sample characters"
            }
        }
    }

    # GWL_EXSTYLE / WS_EX_TOPMOST. The result window has to out-rank the overlay
    # while the capture is up, and step back down once it is gone.
    $GWL_EXSTYLE = -20; $WS_EX_TOPMOST = 0x8
    $ex = [W7]::GetWindowLong($ocr[0], $GWL_EXSTYLE)
    "topmost while capturing: $((($ex -band $WS_EX_TOPMOST) -ne 0)) (want True)"
    if (($ex -band $WS_EX_TOPMOST) -eq 0) { $fail += 'the OCR window sits under the overlay' }

    [void][W7]::PostMessage($ov[0], $WM_KEYDOWN, [IntPtr]$VK_ESCAPE, [IntPtr]::Zero)
    [void][W7]::PostMessage($ov[0], $WM_KEYUP, [IntPtr]$VK_ESCAPE, [IntPtr]::Zero)
    Start-Sleep -Milliseconds 800
    $ex2 = [W7]::GetWindowLong($ocr[0], $GWL_EXSTYLE)
    "topmost after the capture: $((($ex2 -band $WS_EX_TOPMOST) -ne 0)) (want False)"
    if (($ex2 -band $WS_EX_TOPMOST) -ne 0) { $fail += 'the OCR window stayed topmost' }
}

# Stopping the app before the verdict: a leftover instance holds the exe open
# and the next build fails to link.
$sample.Close()
if ($proc -and -not $proc.HasExited) { $proc.Kill() }
if ($fail.Count) { "FAIL: " + ($fail -join '; '); exit 1 }
"PASS"
