# A saved file ends the capture: the overlay goes away the same way the bar's done
# button takes it away, and so does the long-shot editor, because both are the same
# capture session. A pin stays, because a pin is a floating reference image rather
# than a capture in progress.
#
# The half that is easy to get wrong is the other one: Cancel in the file dialog
# wrote nothing, so the capture still has to be there to save from. A teardown hung
# off the dialog closing rather than off the dialog accepting breaks that, and it
# breaks it silently -- the file is simply never written and the user is back at the
# desktop with no idea the save was lost. Stage A is that half.
#
#   A  Ctrl+S, ESC            -> no file, overlay still up, region toolbar still up
#   B  Ctrl+S, path, ENTER    -> the file is on disk AND the overlay is gone
#   C  long-shot save, ENTER  -> the file is on disk AND the overlay and the
#                               long-shot bar are both gone
#
# The winshot process itself stays in the tray through all three: ending a capture is
# not quitting the program, and the hotkey has to work again afterwards.
Add-Type -AssemblyName System.Drawing, System.Windows.Forms
Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class SE {
    public delegate bool EnumProc(IntPtr h, IntPtr l);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
    [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr p, EnumProc cb, IntPtr l);
    [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll", CharSet=CharSet.Auto)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint msg, IntPtr w, IntPtr l);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern int GetWindowThreadProcessId(IntPtr h, out int pid);
    [DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr h, int idx);
    [DllImport("user32.dll", EntryPoint="SendMessageW", CharSet=CharSet.Unicode)] public static extern IntPtr SendMessageBuf(IntPtr h, uint msg, IntPtr w, StringBuilder l);
    [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint dx, uint dy, uint d, UIntPtr e);
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int left, top, right, bottom; }
}
"@

$LEFTDOWN = 0x0002; $LEFTUP = 0x0004
$HOTKEY = 0x8002
$WM_GETTEXT = 0x000D; $GWL_ID = -12; $ID_NAME_EDIT = 1001

function MoveTo([int]$x, [int]$y) {
    [void][SE]::mouse_event(0x8001, [uint32][int][Math]::Round(65535 * $x / 3839),
                            [uint32][int][Math]::Round(65535 * $y / 2159), 0,
                            [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 90
}
function Down { [void][SE]::mouse_event($LEFTDOWN, 0, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 150 }
function Up { [void][SE]::mouse_event($LEFTUP, 0, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 350 }
function Drag([int]$x1, [int]$y1, [int]$x2, [int]$y2) {
    MoveTo $x1 $y1; Down
    for ($i = 1; $i -le 20; $i++) {
        MoveTo ([int]($x1 + ($x2-$x1) * $i / 20)) ([int]($y1 + ($y2-$y1) * $i / 20))
    }
    Up
    Start-Sleep -Milliseconds 400
}
function Click([int]$x, [int]$y) { MoveTo $x $y; Down; Up }
function Keys([string]$s) { [void][System.Windows.Forms.SendKeys]::SendWait($s) }

function Find-Wins([string]$title) {
    $found = New-Object System.Collections.ArrayList
    $cb = [SE+EnumProc] {
        param($h, $l)
        $t = New-Object System.Text.StringBuilder 256
        [void][SE]::GetWindowText($h, $t, 256)
        if ($t.ToString() -eq $title) { [void]$found.Add($h) }
        return $true
    }
    [void][SE]::EnumWindows($cb, [IntPtr]::Zero)
    return $found.ToArray()
}
function Find-Kids([IntPtr]$parent, [string]$title) {
    $found = New-Object System.Collections.ArrayList
    $cb = [SE+EnumProc] {
        param($h, $l)
        $t = New-Object System.Text.StringBuilder 256
        [void][SE]::GetWindowText($h, $t, 256)
        if ($t.ToString() -eq $title -and [SE]::IsWindowVisible($h)) { [void]$found.Add($h) }
        return $true
    }
    [void][SE]::EnumChildWindows($parent, $cb, [IntPtr]::Zero)
    return $found.ToArray()
}
function Rect-Of([IntPtr]$h) {
    $r = New-Object SE+RECT
    [void][SE]::GetWindowRect($h, [ref]$r)
    return $r
}
# Our own save dialog. Another app can have a #32770 up, and driving that one would
# be typing into a dialog nobody can see -- so it is matched on the owning process.
# $wantPid, not $pid: PowerShell variable names are case-insensitive and $PID is an
# automatic variable.
function Find-Dialog([int]$wantPid) {
    for ($try = 0; $try -lt 14; $try++) {
        $found = New-Object System.Collections.ArrayList
        $cb = [SE+EnumProc] {
            param($h, $l)
            $cls = New-Object System.Text.StringBuilder 256
            [void][SE]::GetClassName($h, $cls, 256)
            if ($cls.ToString() -ne '#32770') { return $true }
            $owner = 0
            [void][SE]::GetWindowThreadProcessId($h, [ref]$owner)
            if ($owner -eq $wantPid) { [void]$found.Add($h) }
            return $true
        }
        [void][SE]::EnumWindows($cb, [IntPtr]::Zero)
        if ($found.Count) { return , $found[0] }
        Start-Sleep -Milliseconds 250
    }
    return $null
}
# The #32770 is up before the modern dialog has finished building its child
# controls, so the name edit is waited for on its own and not assumed from the
# window. It is the only Edit carrying control id 1001 -- the address bar's toolbar
# shares that id, which is why the class has to be part of the test.
#
# Even then the dialog is not ready: measured, clicking and typing as soon as the
# edit exists leaves the box holding the default name the dialog fills in when it
# finishes initializing, so the keystrokes went somewhere else and the save wrote
# that default name. The default name appearing is the signal that it is done, so
# wait for that and let it settle before driving it.
function Name-Edit([IntPtr]$dlg) {
    for ($try = 0; $try -lt 25; $try++) {
        $edits = New-Object System.Collections.ArrayList
        $cb = [SE+EnumProc] {
            param($h, $l)
            $c = New-Object System.Text.StringBuilder 64
            [void][SE]::GetClassName($h, $c, 64)
            if ($c.ToString() -eq 'Edit' -and [SE]::GetWindowLong($h, $GWL_ID) -eq $ID_NAME_EDIT) {
                [void]$edits.Add($h)
            }
            return $true
        }
        [void][SE]::EnumChildWindows($dlg, $cb, [IntPtr]::Zero)
        if ($edits.Count -eq 1) {
            $sb = New-Object System.Text.StringBuilder 600
            [void][SE]::SendMessageBuf($edits[0], $WM_GETTEXT, 600, $sb)
            if ($sb.ToString().Length) {
                Start-Sleep -Milliseconds 700
                return , $edits[0]
            }
        }
        Start-Sleep -Milliseconds 200
    }
    return $null
}
# What the bytes on disk say the file is, which is the only proof that a save
# happened: the dialog can close with nothing written and every window in the app
# looking none the wiser.
function Magic([string]$path) {
    if (-not (Test-Path $path)) { return 'missing' }
    $b = [System.IO.File]::ReadAllBytes($path)
    if ($b.Length -lt 4) { return 'short' }
    if ($b[0] -eq 0x89 -and $b[1] -eq 0x50 -and $b[2] -eq 0x4E -and $b[3] -eq 0x47) { return 'png' }
    if ($b[0] -eq 0xFF -and $b[1] -eq 0xD8 -and $b[2] -eq 0xFF) { return 'jpg' }
    return 'other'
}
# The toolbar's cells: 0..6 are plain cells, then a separator, then 7 up. The
# long-shot slot is 8, which is why the separator has to be counted here rather than
# in the caller.
function Cell-X([IntPtr]$bar, [int]$i) {
    $r = Rect-Of $bar
    $s = ($r.bottom - $r.top) / 32.0
    $cell = [int][Math]::Round(27 * $s); $pad = [int][Math]::Round(4 * $s)
    $sep = 0
    if ($i -ge 7) { $sep = 1 }
    if ($i -ge 13) { $sep = 2 }
    return [int]($r.left + $pad + $i * $cell + $sep * [int][Math]::Round(14 * $s) + $cell / 2)
}
function Bar-Y([IntPtr]$bar) { $r = Rect-Of $bar; return [int](($r.top + $r.bottom) / 2) }

# Types a path into the dialog and commits it the way a person does: a click in the
# name box, select-all, the path, Enter. Enter is the dialog's default button, so it
# takes the typed name and closes the dialog in one gesture. Real keystrokes, not
# WM_SETTEXT: measured in save_format.ps1, setting the edit programmatically leaves
# the dialog holding its own copy of the old name and the default name is saved.
function Save-To([int]$wantPid, [string]$path) {
    $dlg = Find-Dialog $wantPid
    if (-not $dlg) { return 'no dialog' }
    $name = Name-Edit $dlg
    if (-not $name) { Keys '{ESC}'; return 'no name edit' }
    $r = Rect-Of $name
    Click ([int](($r.left + $r.right) / 2)) ([int](($r.top + $r.bottom) / 2))
    Start-Sleep -Milliseconds 250
    Keys '^a'
    Keys $path
    Start-Sleep -Milliseconds 300
    $sb = New-Object System.Text.StringBuilder 600
    [void][SE]::SendMessageBuf($name, $WM_GETTEXT, 600, $sb)
    if ($sb.ToString() -notlike ('*' + (Split-Path -Leaf $path))) {
        Keys '{ESC}'
        return "the name box reads '$($sb.ToString())'"
    }
    Keys '{ENTER}'
    Start-Sleep -Seconds 1
    return 'ok'
}

$fail = @()
function Bail([string]$m) {
    if ($proc -and -not $proc.HasExited) { Stop-Process -Id $proc.Id -Force }
    "FAIL: $m"
    exit 1
}

$pngA = 'D:\Project\winshot\obj\se_cancel.png'
$pngB = 'D:\Project\winshot\obj\se_shot.png'
$pngC = 'D:\Project\winshot\obj\se_long.png'
foreach ($f in @($pngA, $pngB, $pngC)) { Remove-Item $f -Force -ErrorAction SilentlyContinue }

MoveTo 3000 1900
Start-Sleep -Milliseconds 400
Get-Process winshot -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 600
$proc = Start-Process -FilePath 'D:\Project\winshot\x64\Debug\winshot.exe' -PassThru
Start-Sleep -Seconds 2
$sink = @(Find-Wins 'WinShotSink')
if ($sink.Count -eq 0) { Bail 'no sink window, winshot did not start' }

function Summon() {
    [void][SE]::PostMessage($sink[0], $HOTKEY, [IntPtr]::Zero, [IntPtr]::Zero)
    Start-Sleep -Seconds 2
    $o = @(Find-Wins 'WinShotOverlay')
    if ($o.Count -eq 0) { Bail 'the hotkey opened no overlay' }
    return , $o[0]
}
function Wait-Gone([string]$title, [int]$tries) {
    for ($i = 0; $i -lt $tries; $i++) {
        if (@(Find-Wins $title).Count -eq 0) { return $true }
        Start-Sleep -Milliseconds 400
    }
    return $false
}

# --- A. Cancel in the dialog leaves the capture alone -------------------------------
$ov = Summon
Drag 800 600 1600 1000
if (@(Find-Kids $ov 'WinShotToolbar').Count -eq 0) { Bail 'the drag picked no region' }
Keys '^s'
$dlgA = Find-Dialog $proc.Id
if (-not $dlgA) { Bail 'Ctrl+S opened no save dialog' }
Keys '{ESC}'
Start-Sleep -Milliseconds 900
if ([SE]::IsWindow($dlgA)) { $fail += 'ESC left the save dialog up' }
$stillUp = @(Find-Wins 'WinShotOverlay').Count
$stillBar = @(Find-Kids $ov 'WinShotToolbar').Count
"after cancel: overlay $stillUp, toolbar $stillBar, file $(Magic $pngA)"
if ($stillUp -ne 1) { $fail += 'cancelling the save dialog ended the capture' }
if ($stillBar -eq 0) { $fail += 'cancelling the save dialog dropped the region toolbar' }
if ((Magic $pngA) -ne 'missing') { $fail += 'cancelling the save dialog wrote a file anyway' }
Keys '{ESC}'
if (-not (Wait-Gone 'WinShotOverlay' 8)) { Bail 'ESC after a cancelled save did not exit' }

# --- B. a save writes the file and ends the capture ---------------------------------
$ov = Summon
Drag 800 600 1600 1000
Keys '^s'
$r = Save-To $proc.Id $pngB
"save to se_shot.png : $r"
if ($r -ne 'ok') { $fail += "the save dialog could not be driven: $r" }
$gone = Wait-Gone 'WinShotOverlay' 12
$magic = Magic $pngB
$size = 0
if (Test-Path $pngB) { $size = (Get-Item $pngB).Length }
"after save: overlay $(@(Find-Wins 'WinShotOverlay').Count), sink $(@(Find-Wins 'WinShotSink').Count), file $magic $size bytes"
if ($magic -ne 'png') { $fail += "the saved file reads as '$magic', want png" }
if ($size -lt 1000) { $fail += "the saved file is $size bytes, too small to be a screenshot" }
if (-not $gone) { $fail += 'a successful save left the overlay on screen' }
if (@(Find-Wins 'WinShotSink').Count -eq 0) { $fail += 'the save took the tray window down with it' }
if ($proc.HasExited) { $fail += 'the save quit winshot, which should stay in the tray' }

# --- C. the long-shot editor ends the same way --------------------------------------
# If B failed it can have left a capture up; close it so C drives a fresh session
# rather than a stale one, and the failure it reports is its own.
if (@(Find-Wins 'WinShotOverlay').Count) { Keys '{ESC}'; [void](Wait-Gone 'WinShotOverlay' 8) }
# Ctrl+S belongs to the overlay and long-shot owns the keyboard, so this one goes
# through the long-shot bar's own save slot. The bar is a borderless popup, so its
# window rect is its client rect and the slot centres are the x offsets in its own
# table: save is x=41 w=28, i.e. left + 55.
$ov = Summon
Drag 700 500 1500 1400
$bar = @(Find-Kids $ov 'WinShotToolbar')
if ($bar.Count -eq 0) { Bail 'no toolbar to start long-shot from' }
Click (Cell-X $bar[0] 8) (Bar-Y $bar[0])
Start-Sleep -Milliseconds 900
$lb = @(Find-Wins 'WinShotLongBar')
if ($lb.Count -eq 0) { Bail 'long-shot did not start' }
$lr = Rect-Of $lb[0]
Click ($lr.left + 55) ([int](($lr.top + $lr.bottom) / 2))
$r = Save-To $proc.Id $pngC
"long-shot save to se_long.png : $r"
if ($r -ne 'ok') { $fail += "the long-shot save dialog could not be driven: $r" }
$goneOv = Wait-Gone 'WinShotOverlay' 12
$goneBar = @(Find-Wins 'WinShotLongBar').Count
$magic = Magic $pngC
"after long-shot save: overlay $(@(Find-Wins 'WinShotOverlay').Count), long bar $goneBar, file $magic"
if ($magic -ne 'png') { $fail += "the long-shot file reads as '$magic', want png" }
if (-not $goneOv) { $fail += 'a successful long-shot save left the overlay on screen' }
if ($goneBar -ne 0) { $fail += 'a successful long-shot save left the long-shot bar up' }

if ($proc -and -not $proc.HasExited) { Stop-Process -Id $proc.Id -Force }
foreach ($f in @($pngA, $pngB, $pngC)) { Remove-Item $f -Force -ErrorAction SilentlyContinue }

if ($fail.Count) {
    "FAILURES: $($fail.Count)"
    foreach ($f in $fail) { "  $f" }
    exit 1
}
'PASS'
