Add-Type -AssemblyName System.Drawing, System.Windows.Forms
Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class W2 {
    public delegate bool EnumProc(IntPtr h, IntPtr l);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
    [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint msg, IntPtr w, IntPtr l);
    [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint dx, uint dy, uint d, UIntPtr e);
}
"@

$LEFTDOWN = 0x0002; $LEFTUP = 0x0004

function Grab([string]$path) {
    $b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    $bmp = New-Object System.Drawing.Bitmap $b.Width, $b.Height
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen($b.Location, [System.Drawing.Point]::Empty, $bmp.Size)
    $bmp.Save($path)
    $g.Dispose()
    return $bmp
}

function Pixels($bmp) {
    $rect = New-Object System.Drawing.Rectangle 0, 0, $bmp.Width, $bmp.Height
    $data = $bmp.LockBits($rect, [System.Drawing.Imaging.ImageLockMode]::ReadOnly,
                          [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $bytes = New-Object byte[] ($data.Stride * $data.Height)
    [System.Runtime.InteropServices.Marshal]::Copy($data.Scan0, $bytes, 0, $bytes.Length)
    $bmp.UnlockBits($data)
    return ,@($bytes, $data.Stride)
}

function Px($pack, [int]$x, [int]$y) {
    $b = $pack[0]; $s = $pack[1]; $i = $y * $s + $x * 4
    return @([int]$b[$i+2], [int]$b[$i+1], [int]$b[$i])
}

function Near($a, $b, [int]$tol) {
    return ([Math]::Abs($a[0]-$b[0]) + [Math]::Abs($a[1]-$b[1]) + [Math]::Abs($a[2]-$b[2])) -le $tol
}

function MoveTo([int]$x, [int]$y) {
    [System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point($x, $y)
    Start-Sleep -Milliseconds 120
}
function Drag([int]$x1, [int]$y1, [int]$x2, [int]$y2) {
    MoveTo $x1 $y1
    [void][W2]::mouse_event($LEFTDOWN, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 120
    for ($i = 1; $i -le 12; $i++) {
        MoveTo ([int]($x1 + ($x2-$x1) * $i / 12)) ([int]($y1 + ($y2-$y1) * $i / 12))
    }
    Start-Sleep -Milliseconds 150
    [void][W2]::mouse_event($LEFTUP, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 300
}

# Inside the selection the still is drawn unmodified; outside it is dimmed with
# 0x99 black, i.e. base * (1 - 153/255) = base * 0.4. Probing a point a few pixels
# inside and a few outside each expected edge pins the boundary to within a pixel
# without classifying the whole frame (dimmed black is indistinguishable from
# black, so a full-frame classifier would be unreliable).
$script:basePx = @{}; $script:dimPx = @{}
$script:failures = 0

function Seed([int]$x, [int]$y) {
    $c = Px $script:bp $x $y
    $key = "$x,$y"
    $script:basePx[$key] = $c
    $script:dimPx[$key] = @([int]($c[0]*0.4), [int]($c[1]*0.4), [int]($c[2]*0.4))
}

# The absolute probes compare against a desktop grab taken before winshot starts,
# so they only mean anything while the desktop itself is not changing. On a live
# desktop — a playing video, a clock, a window the user moved — they are advisory
# and only the frame probes, which read pixels we drew, stay hard assertions.
function Probe([string]$tag, $pack, [int]$x, [int]$y, [bool]$inside) {
    Seed $x $y
    $key = "$x,$y"
    $p = Px $pack $x $y
    $ref = if ($inside) { $script:basePx[$key] } else { $script:dimPx[$key] }
    $ok = Near $p $ref 12
    if (-not $ok -and $script:staticDesk) { $script:failures++ }
    "{0,-24} ({1},{2}) {3} got={4},{5},{6} want={7},{8},{9} {10}" -f `
        $tag, $x, $y, $(if ($inside) {'inside '} else {'outside'}), `
        $p[0],$p[1],$p[2], $ref[0],$ref[1],$ref[2], `
        $(if ($ok) {'OK'} elseif ($script:staticDesk) {'FAIL'} else {'warn'})
}

# The dimmed band ends at edge-1 and the still starts at edge, so a 2px frame
# centred on the selection edge must cover exactly pixels edge-1 and edge. Probe
# points must stay clear of the handles, which are the same colour.
function ProbeFrameV([string]$tag, $pack, [int]$x, [int]$y) {
    $want = @(30, 159, 212)
    $hits = @()
    for ($d = -3; $d -le 2; $d++) {
        if (Near (Px $pack ($x + $d) $y) $want 30) { $hits += ($x + $d) }
    }
    $ok = ($hits.Count -eq 2 -and $hits[0] -eq ($x - 1) -and $hits[1] -eq $x)
    if (-not $ok) { $script:failures++ }
    "{0,-24} v-frame at x={1} y={2} got={3} want={4},{5} {6}" -f `
        $tag, $x, $y, ($(if ($hits.Count) { $hits -join ',' } else { 'none' })), `
        ($x - 1), $x, $(if ($ok) {'OK'} else {'FAIL'})
}

function ProbeFrameH([string]$tag, $pack, [int]$x, [int]$y) {
    $want = @(30, 159, 212)
    $hits = @()
    for ($d = -3; $d -le 2; $d++) {
        if (Near (Px $pack $x ($y + $d)) $want 30) { $hits += ($y + $d) }
    }
    $ok = ($hits.Count -eq 2 -and $hits[0] -eq ($y - 1) -and $hits[1] -eq $y)
    if (-not $ok) { $script:failures++ }
    "{0,-24} h-frame at x={1} y={2} got={3} want={4},{5} {6}" -f `
        $tag, $x, $y, ($(if ($hits.Count) { $hits -join ',' } else { 'none' })), `
        ($y - 1), $y, $(if ($ok) {'OK'} else {'FAIL'})
}

Get-Process winshot -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 500

MoveTo 3000 1900
Start-Sleep -Milliseconds 400

$t1 = Grab 'D:\Project\winshot\obj\d_pre1.png'
Start-Sleep -Seconds 1
$t2 = Grab 'D:\Project\winshot\obj\d_pre2.png'
$u1 = Pixels $t1; $u2 = Pixels $t2
$changed = 0; $sampled = 0
for ($y = 0; $y -lt $t1.Height; $y += 11) {
    $o1 = $y * $u1[1]; $o2 = $y * $u2[1]
    for ($x = 0; $x -lt $t1.Width; $x += 11) {
        $i1 = $o1 + $x * 4; $i2 = $o2 + $x * 4
        $sampled++
        if ($u1[0][$i1] -ne $u2[0][$i2] -or $u1[0][$i1+1] -ne $u2[0][$i2+1] -or
            $u1[0][$i1+2] -ne $u2[0][$i2+2]) { $changed++ }
    }
}
$t1.Dispose(); $t2.Dispose()
$script:staticDesk = ($changed -eq 0)
"desktop stability: $changed of $sampled sampled pixels changed in 1s -> " +
    $(if ($script:staticDesk) { 'pixel probes are hard assertions' }
      else { 'pixel probes are advisory'})

$base = Grab 'D:\Project\winshot\obj\d_base.png'
$bp = Pixels $base

$p = Start-Process -FilePath 'D:\Project\winshot\x64\Debug\winshot.exe' -PassThru
Start-Sleep -Seconds 2

$sink = New-Object System.Collections.ArrayList
$cb = [W2+EnumProc] {
    param($h, $l)
    $t = New-Object System.Text.StringBuilder 256
    [void][W2]::GetWindowText($h, $t, 256)
    if ($t.ToString() -eq 'WinShotSink') { [void]$sink.Add($h) }
    return $true
}
[void][W2]::EnumWindows($cb, [IntPtr]::Zero)
if ($sink.Count -eq 0) { "no sink window"; exit 1 }

# WM_APP + 2 = WM_APP_STARTCAPTURE
[void][W2]::PostMessage($sink[0], 0x8002, [IntPtr]::Zero, [IntPtr]::Zero)
Start-Sleep -Seconds 2

# --- 1. drag-create: (800,600) -> (1400,1000)
Drag 800 600 1400 1000
$s1 = Grab 'D:\Project\winshot\obj\d_create.png'
$q1 = Pixels $s1
"--- create: expected selection [800,600,1400,1000]"
Probe 'create deep inside'  $q1 1200 800 $true
Probe 'create inside TL'    $q1 805 605 $true
Probe 'create inside BR'    $q1 1395 995 $true
Probe 'create outside TL'   $q1 793 593 $false
Probe 'create outside BR'   $q1 1407 1007 $false
ProbeFrameV 'create frame L'  $q1 800 700
ProbeFrameV 'create frame R'  $q1 1400 700
ProbeFrameH 'create frame T'  $q1 900 600
ProbeFrameH 'create frame B'  $q1 900 1000
$s1.Dispose()

# --- 2. move: drag the interior of the created selection by (+500,+400)
Drag 1100 800 1600 1200
$s2 = Grab 'D:\Project\winshot\obj\d_move.png'
$q2 = Pixels $s2
"--- move: expected selection [1300,1000,1900,1400]"
Probe 'move deep inside'  $q2 1600 1200 $true
Probe 'move inside TL'    $q2 1305 1005 $true
Probe 'move inside BR'    $q2 1895 1395 $true
Probe 'move outside TL'   $q2 1293 993 $false
Probe 'move outside BR'   $q2 1907 1407 $false
ProbeFrameV 'move frame L'  $q2 1300 1100
ProbeFrameH 'move frame B'  $q2 1400 1400
$s2.Dispose()

# --- 3. resize: grab the bottom-right handle at (1900,1400), drag +300,+200
Drag 1900 1400 2200 1600
$s3 = Grab 'D:\Project\winshot\obj\d_resize.png'
$q3 = Pixels $s3
"--- resize: expected selection [1300,1000,2200,1600]"
Probe 'resize deep inside' $q3 1700 1300 $true
Probe 'resize inside BR'   $q3 2193 1593 $true
Probe 'resize outside BR'  $q3 2207 1607 $false
Probe 'resize outside TL'  $q3 1293 993 $false
ProbeFrameV 'resize frame R' $q3 2200 1100
ProbeFrameH 'resize frame B' $q3 1400 1600
$s3.Dispose()

# --- 4. arrow-key nudge. SendKeys drops keystrokes even with delays, so the
# check is the invariant rather than an exact offset: nudging translates the
# selection and leaves its size untouched.
for ($i = 0; $i -lt 5; $i++) {
    [System.Windows.Forms.SendKeys]::SendWait('{RIGHT}'); Start-Sleep -Milliseconds 150
}
for ($i = 0; $i -lt 5; $i++) {
    [System.Windows.Forms.SendKeys]::SendWait('+{RIGHT}'); Start-Sleep -Milliseconds 150
}
for ($i = 0; $i -lt 3; $i++) {
    [System.Windows.Forms.SendKeys]::SendWait('+{DOWN}'); Start-Sleep -Milliseconds 150
}
Start-Sleep -Milliseconds 500
$s4 = Grab 'D:\Project\winshot\obj\d_nudge.png'
$q4 = Pixels $s4

function FindFrameV([int]$y, [int]$from, [int]$to) {
    $want = @(30, 159, 212)
    for ($x = $from; $x -lt $to; $x++) {
        if ((Near (Px $q4 $x $y) $want 30) -and (Near (Px $q4 ($x + 1) $y) $want 30)) { return $x + 1 }
    }
    return -1
}
function FindFrameH([int]$x, [int]$from, [int]$to) {
    $want = @(30, 159, 212)
    for ($y = $from; $y -lt $to; $y++) {
        if ((Near (Px $q4 $x $y) $want 30) -and (Near (Px $q4 $x ($y + 1)) $want 30)) { return $y + 1 }
    }
    return -1
}

$l = FindFrameV 1100 1340 1520
$top = if ($l -gt 0) { FindFrameH ($l + 100) 990 1170 } else { -1 }
$r = if ($l -gt 0) { FindFrameV 1100 ($l + 860) ($l + 960) } else { -1 }
$bot = if ($l -gt 0 -and $top -gt 0) { FindFrameH ($l + 100) ($top + 560) ($top + 660) } else { -1 }
$wOk = ($r - $l -eq 900); $hOk = ($bot - $top -eq 600); $moved = ($l -gt 1300 -and $top -gt 1000)
if ($l -lt 0) {
    # SendKeys also drops keystrokes, so the offsets vary between runs; a frame
    # that is missing altogether means the overlay was not what the grab saw.
    "nudge: no selection frame in the grab — the overlay was not on screen"
}
if (-not ($wOk -and $hOk -and $moved)) { $script:failures++ }
"nudge: left=$l top=$top right=$r bottom=$bot  w=$($r-$l) (want 900) $wOk  h=$($bot-$top) (want 600) $hOk  moved=$moved"
$s4.Dispose()

# --- 5. Esc cancels
[System.Windows.Forms.SendKeys]::SendWait('{ESC}')
Start-Sleep -Seconds 1
function CountWindows([string]$title) {
    $list = New-Object System.Collections.ArrayList
    $cb = [W2+EnumProc] {
        param($h, $l)
        $t = New-Object System.Text.StringBuilder 256
        [void][W2]::GetWindowText($h, $t, 256)
        if ($t.ToString() -eq $title) { [void]$list.Add($h) }
        return $true
    }
    [void][W2]::EnumWindows($cb, [IntPtr]::Zero)
    return $list.Count
}
"overlay windows after ESC: $(CountWindows 'WinShotOverlay')"
"winshot still running: $([bool](Get-Process winshot -ErrorAction SilentlyContinue))"
"failures: $script:failures"

$base.Dispose()
