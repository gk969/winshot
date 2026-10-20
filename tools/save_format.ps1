# The save dialog offers PNG and JPEG now, and two separate things decide which
# one a file really is: the format dropdown, and an extension the user typed.
# They have to agree with the bytes on disk, or "I picked JPEG" quietly writes a
# PNG and nobody notices until someone tries to open the thing.
#
# The trap this is built around is OPENFILENAMEW::lpstrDefExt -- it is a single
# value that does not follow the filter, so with L"png" there Windows appends
# .png whichever filter is selected, and the dropdown does nothing at all. The
# code leaves it null and appends the extension off nFilterIndex itself, which
# means the dropdown's effect has to be measured rather than assumed.
#
# Every round therefore asserts the magic bytes of the file that landed, so
# nothing here can pass by writing nothing. It has to be a real click on the
# dropdown too: CB_SETCURSEL plus a hand-posted WM_COMMAND/CBN_SELCHANGE moves
# the combo and reports the new row, but measured it still wrote a PNG, because
# the modern dialog only re-reads nFilterIndex off the notification its own
# combo posts. The name has to be typed for the same reason: once the filter
# changes the dialog holds its own copy of it, and WM_SETTEXT on the edit leaves
# that copy alone -- measured, it saved the default name with the new extension.
Add-Type -AssemblyName System.Drawing, System.Windows.Forms
Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class SF {
    public delegate bool EnumProc(IntPtr h, IntPtr l);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
    [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr p, EnumProc cb, IntPtr l);
    [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll", CharSet=CharSet.Auto)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint msg, IntPtr w, IntPtr l);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr SendMessage(IntPtr h, uint msg, IntPtr w, string l);
    [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr h, uint msg, IntPtr w, IntPtr l);
    // CB_GETLBTEXT wants a buffer. A third SendMessage overload would be
    // ambiguous against the two above, so it carries its own name.
    [DllImport("user32.dll", EntryPoint="SendMessageW", CharSet=CharSet.Unicode)] public static extern IntPtr SendMessageBuf(IntPtr h, uint msg, IntPtr w, StringBuilder l);
    [DllImport("user32.dll")] public static extern IntPtr GetParent(IntPtr h);
    [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern int GetWindowThreadProcessId(IntPtr h, out int pid);
    [DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr h, int idx);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint dx, uint dy, uint d, UIntPtr e);
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int left, top, right, bottom; }
}
"@
$LEFTDOWN = 0x0002; $LEFTUP = 0x0004
$WM_GETTEXT = 0x000D
$GWL_STYLE = -16; $BS_DEFPUSHBUTTON = 0x1
$CB_GETCOUNT = 0x0146; $CB_GETLBTEXT = 0x0148
$CB_GETCURSEL = 0x0147
$GWL_ID = -12
# GetSaveFileNameW routes to IFileSaveDialog unless OFN_ENABLEHOOK or
# OFN_ENABLETEMPLATE forces the classic resource, so this dialog is the modern
# one and the commdlg ids cmb1 (0x47) and cmb3 (0x4B) are not in it -- measured,
# GetDlgItem returns zero for both. What is in it: the file-name edit is the one
# Edit with control id 1001, and the "save as type" combo is a ComboBox with id
# 0, which is no use as a locator. Both are found by shape instead, below.
$ID_NAME_EDIT = 1001

function MoveTo([int]$x, [int]$y) {
    [void][SF]::mouse_event(0x8001, [uint32][int][Math]::Round(65535 * $x / 3839),
                            [uint32][int][Math]::Round(65535 * $y / 2159), 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 90
}
function Down { [void][SF]::mouse_event($LEFTDOWN, 0, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 150 }
function Up   { [void][SF]::mouse_event($LEFTUP,   0, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 350 }
function Walk([int]$x1, [int]$y1, [int]$x2, [int]$y2, [int]$steps) {
    for ($i = 1; $i -le $steps; $i++) {
        MoveTo ([int]($x1 + ($x2-$x1) * $i / $steps)) ([int]($y1 + ($y2-$y1) * $i / $steps))
    }
}
function Find-Wins([string]$title) {
    $found = New-Object System.Collections.ArrayList
    $cb = [SF+EnumProc] {
        param($h, $l)
        $t = New-Object System.Text.StringBuilder 256
        [void][SF]::GetWindowText($h, $t, 256)
        if ($t.ToString() -eq $title) { [void]$found.Add($h) }
        return $true
    }
    [void][SF]::EnumWindows($cb, [IntPtr]::Zero)
    return $found.ToArray()
}
# Our own save dialog. Another app can have a #32770 up, and driving that one
# would be typing into a dialog we cannot see.
# $wantPid, not $pid: PowerShell variable names are case-insensitive and $PID is
# an automatic variable.
function Find-Dialog([int]$wantPid) {
    for ($try = 0; $try -lt 14; $try++) {
        $found = New-Object System.Collections.ArrayList
        $cb = [SF+EnumProc] {
            param($h, $l)
            $cls = New-Object System.Text.StringBuilder 256
            [void][SF]::GetClassName($h, $cls, 256)
            if ($cls.ToString() -ne '#32770') { return $true }
            $owner = 0
            [void][SF]::GetWindowThreadProcessId($h, [ref]$owner)
            if ($owner -eq $wantPid) { [void]$found.Add($h) }
            return $true
        }
        [void][SF]::EnumWindows($cb, [IntPtr]::Zero)
        if ($found.Count) { return , $found[0] }
        Start-Sleep -Milliseconds 150
    }
    return $null
}
function Default-Button([IntPtr]$dlg) {
    $btns = New-Object System.Collections.ArrayList
    $cb = [SF+EnumProc] {
        param($h, $l)
        $cls = New-Object System.Text.StringBuilder 256
        [void][SF]::GetClassName($h, $cls, 256)
        if ($cls.ToString() -eq 'Button') { [void]$btns.Add($h) }
        return $true
    }
    [void][SF]::EnumChildWindows($dlg, $cb, [IntPtr]::Zero)
    foreach ($b in $btns) {
        if (([SF]::GetWindowLong($b, $GWL_STYLE) -band $BS_DEFPUSHBUTTON) -ne 0) { return $b }
    }
    if ($btns.Count) { return $btns[0] }
    return $null
}
function Has-Ancestor([IntPtr]$h, [string]$want) {
    $p = [SF]::GetParent($h)
    for ($i = 0; $i -lt 12 -and $p -ne [IntPtr]::Zero; $i++) {
        $c = New-Object System.Text.StringBuilder 256
        [void][SF]::GetClassName($p, $c, 256)
        if ($c.ToString() -eq $want) { return $true }
        $p = [SF]::GetParent($p)
    }
    return $false
}
function Combos([IntPtr]$root) {
    $out = New-Object System.Collections.ArrayList
    $cb = [SF+EnumProc] {
        param($k, $l)
        $c = New-Object System.Text.StringBuilder 256
        [void][SF]::GetClassName($k, $c, 256)
        if ($c.ToString() -eq 'ComboBox') { [void]$out.Add($k) }
        return $true
    }
    [void][SF]::EnumChildWindows($root, $cb, [IntPtr]::Zero)
    return $out.ToArray()
}
# The two controls this script has to drive, located by shape:
#   the file-name edit  -- the only Edit carrying control id 1001 (the address
#     bar's toolbar shares that id, so the class has to be part of the test);
#   the file-type combo -- the lowest ComboBox that is neither the name combo's
#     nor the address bar's, which is the one ComboBoxEx32 hosts.
# Both are cross-checked against the layout the dialog actually has, so a
# misidentification fails here instead of typing a path into the address bar.
# Returns (name edit, type combo).
function Find-Fields([IntPtr]$dlg) {
    $edits = New-Object System.Collections.ArrayList
    $eb = [SF+EnumProc] {
        param($k, $l)
        $c = New-Object System.Text.StringBuilder 256
        [void][SF]::GetClassName($k, $c, 256)
        if ($c.ToString() -eq 'Edit' -and [SF]::GetWindowLong($k, $GWL_ID) -eq $ID_NAME_EDIT) {
            [void]$edits.Add($k)
        }
        return $true
    }
    [void][SF]::EnumChildWindows($dlg, $eb, [IntPtr]::Zero)
    if ($edits.Count -ne 1) { return , @([IntPtr]::Zero, [IntPtr]::Zero) }
    $name = $edits[0]

    $nameCombo = [SF]::GetParent($name)
    $type = [IntPtr]::Zero; $lowest = -1
    foreach ($c in @(Combos $dlg)) {
        if ($c -eq $nameCombo) { continue }
        if (Has-Ancestor $c 'ComboBoxEx32') { continue }
        $r = New-Object SF+RECT
        [void][SF]::GetWindowRect($c, [ref]$r)
        $nr = New-Object SF+RECT
        [void][SF]::GetWindowRect($nameCombo, [ref]$nr)
        if ($r.top -le $nr.top -or $r.left -ne $nr.left) { continue }
        if ($r.top -gt $lowest) { $lowest = $r.top; $type = $c }
    }
    if ($type -eq [IntPtr]::Zero) { return , @([IntPtr]::Zero, [IntPtr]::Zero) }
    return , @($name, $type)
}
function Read-Head([string]$path, [int]$n) {
    if (-not (Test-Path $path)) { return $null }
    $fs = [System.IO.File]::OpenRead($path)
    $b = New-Object byte[] $n
    try { [void]$fs.Read($b, 0, $n) } finally { $fs.Dispose() }
    # , so the caller gets the array and not its first byte.
    return , $b
}
function Is-Png([string]$path) {
    $b = Read-Head $path 8
    if (-not $b) { return $false }
    return ($b[0] -eq 0x89 -and $b[1] -eq 0x50 -and $b[2] -eq 0x4E -and $b[3] -eq 0x47)
}
function Is-Jpeg([string]$path) {
    $b = Read-Head $path 8
    if (-not $b) { return $false }
    return ($b[0] -eq 0xFF -and $b[1] -eq 0xD8 -and $b[2] -eq 0xFF)
}
function Hex-Head([string]$path) {
    $b = Read-Head $path 4
    if (-not $b) { return 'no file' }
    return (($b | ForEach-Object { $_.ToString('X2') }) -join ' ')
}
# Ctrl+S, drive the dialog, press Save. $typeIndex is the dropdown row to select,
# or -1 to leave the dropdown where the dialog put it.
#
# Returns a hashtable (with , so it is not unrolled into its own keys) rather
# than a row number, because the row alone cannot tell a wrong format from a
# dialog that never had the right controls in it.
function Do-Save([string]$fullPath, [int]$typeIndex) {
    $r = @{ row = -1; field = ''; labels = @(); ok = $false }
    # A save ends the capture, so every round needs a capture of its own. Summoned
    # here rather than at the call sites so the three rounds stay one line each.
    # The region has to be dragged first: Ctrl+S with no region has nothing to write.
    [void][SF]::PostMessage($sink[0], 0x8002, [IntPtr]::Zero, [IntPtr]::Zero)
    Start-Sleep -Seconds 2
    if (-not @(Find-Wins 'WinShotOverlay').Count) {
        $script:fail += 'the hotkey opened no overlay'
        return , $r
    }
    MoveTo 400 400; Down; Walk 400 400 1400 1000 16; Up
    Start-Sleep -Milliseconds 400
    [void][System.Windows.Forms.SendKeys]::SendWait('^s')
    $dlg = Find-Dialog $proc.Id
    if (-not $dlg) { $script:fail += 'Ctrl+S opened no save dialog'; return , $r }

    # The #32770 is up before the modern dialog has finished building its child
    # controls -- measured, the first round found the window and no Edit in it.
    # So the fields are waited for on their own, not just the window.
    $name = [IntPtr]::Zero; $type = [IntPtr]::Zero
    for ($try = 0; $try -lt 20; $try++) {
        $fields = Find-Fields $dlg
        $name = $fields[0]; $type = $fields[1]
        if ($name -ne [IntPtr]::Zero) { break }
        Start-Sleep -Milliseconds 200
    }
    $def = Default-Button $dlg
    if ($name -eq [IntPtr]::Zero -or $type -eq [IntPtr]::Zero) {
        $script:fail += 'the save dialog is not the shape this script expects (no Edit id 1001, or no file-type combo below it)'
        return , $r
    }
    if (-not $def) { $script:fail += 'the dialog has no default button'; return , $r }

    $count = [int][SF]::SendMessage($type, $CB_GETCOUNT, [IntPtr]::Zero, [IntPtr]::Zero)
    for ($i = 0; $i -lt $count; $i++) {
        $sb = New-Object System.Text.StringBuilder 256
        [void][SF]::SendMessageBuf($type, $CB_GETLBTEXT, $i, $sb)
        $r.labels += $sb.ToString()
    }

    $cur = [int][SF]::SendMessage($type, $CB_GETCURSEL, [IntPtr]::Zero, [IntPtr]::Zero)
    if ($typeIndex -ge 0 -and $typeIndex -ne $cur) {
        # Real input, because the dialog only re-reads nFilterIndex off the
        # notification its own combo posts. A click opens the list and puts the
        # focus on the combo, the arrow keys walk to the wanted row and Enter
        # commits it -- the same three gestures a person makes.
        $tr = New-Object SF+RECT
        [void][SF]::GetWindowRect($type, [ref]$tr)
        MoveTo ([int](($tr.left + $tr.right) / 2)) ([int](($tr.top + $tr.bottom) / 2))
        Down; Up
        $step = if ($typeIndex -gt $cur) { '{DOWN}' } else { '{UP}' }
        [void][System.Windows.Forms.SendKeys]::SendWait($step * [Math]::Abs($typeIndex - $cur))
        Start-Sleep -Milliseconds 250
        # TAB, not Enter: Enter is the dialog's default button, so it saves right
        # here -- measured, it wrote the default name -- and the file name has not
        # been typed yet. TAB commits the highlighted row and leaves the dialog up.
        [void][System.Windows.Forms.SendKeys]::SendWait('{TAB}')
        Start-Sleep -Milliseconds 300
    }
    # A set/get pair on a handle the dialog has already destroyed round-trips
    # through whatever window the handle was recycled to, so the name check below
    # cannot tell a live dialog from a dead one on its own.
    if (-not [SF]::IsWindow($dlg)) {
        $script:fail += 'changing the format closed the save dialog'
        return , $r
    }
    $r.row = [int][SF]::SendMessage($type, $CB_GETCURSEL, [IntPtr]::Zero, [IntPtr]::Zero)

    # The name goes in as real keystrokes. Once the filter has been changed the
    # dialog rewrites the extension itself and holds its own copy of the name,
    # and a programmatic WM_SETTEXT changes the edit without telling the dialog:
    # measured, that saved under the default name with the new extension tacked
    # on. Typing is what the dialog is watching.
    $nr = New-Object SF+RECT
    [void][SF]::GetWindowRect($name, [ref]$nr)
    MoveTo ([int](($nr.left + $nr.right) / 2)) ([int](($nr.top + $nr.bottom) / 2))
    Down; Up
    Start-Sleep -Milliseconds 250
    [void][System.Windows.Forms.SendKeys]::SendWait('^a')
    [void][System.Windows.Forms.SendKeys]::SendWait($fullPath)
    Start-Sleep -Milliseconds 300

    # A click that missed the edit would leave the default name in place and the
    # file would land under that name in the folder the dialog opened on, which
    # reads as "saving did nothing". Say what is in the box instead.
    $sb = New-Object System.Text.StringBuilder 600
    [void][SF]::SendMessageBuf($name, $WM_GETTEXT, 600, $sb)
    $r.field = $sb.ToString()
    if ($r.field -notlike ('*' + (Split-Path -Leaf $fullPath))) {
        $script:fail += "the file-name edit did not take the path (it reads '$($r.field)')"
        return , $r
    }

    # Enter is the default button found above. It commits the typed name and
    # closes the dialog together, which is how the save is reached by hand.
    [void][System.Windows.Forms.SendKeys]::SendWait('{ENTER}')
    Start-Sleep -Seconds 2
    $r.ok = $true
    # The save is what ends the capture, and the next round's summon relies on that.
    if (@(Find-Wins 'WinShotOverlay').Count) {
        $script:fail += "saving $(Split-Path -Leaf $fullPath) left the overlay up"
    }
    return , $r
}

$fail = @()
$obj = 'D:\Project\winshot\obj'
foreach ($f in @('sf_a.png', 'sf_a.jpg', 'sf_b.png', 'sf_b.jpg', 'sf_c.png', 'sf_c.jpg')) {
    Remove-Item "$obj\$f" -Force -ErrorAction SilentlyContinue
}

MoveTo 3000 1900
Start-Sleep -Milliseconds 400
Get-Process winshot -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 600
$proc = Start-Process -FilePath 'D:\Project\winshot\x64\Debug\winshot.exe' -PassThru
Start-Sleep -Seconds 2

$sink = @(Find-Wins 'WinShotSink')
if ($sink.Count -eq 0) { 'FAIL: no sink window'; exit 1 }
# Each round summons and drags its own region inside Do-Save: the save at the end of
# a round ends the capture, so there is nothing to carry into the next one.
# --- 1: no extension typed, dropdown left where the dialog put it -------------
$r = Do-Save "$obj\sf_a" -1
"dropdown rows: $($r.labels -join ' | ')"
if ($r.labels.Count -ne 2) { $fail += "the format dropdown lists $($r.labels.Count) formats, want 2" }
if (-not (($r.labels -join ' ').ToLower().Contains('png'))) { $fail += 'no PNG row in the format dropdown' }
if (-not (($r.labels -join ' ').ToLower().Contains('jpg'))) { $fail += 'no JPG row in the format dropdown' }
"sf_a: dropdown row $($r.row), $(Hex-Head "$obj\sf_a.png")  (want 89 50 4E 47)"
if (-not (Is-Png "$obj\sf_a.png")) { $fail += 'no extension + the PNG filter did not write a PNG' }
if (Test-Path "$obj\sf_a.jpg") { $fail += 'the PNG filter also produced a .jpg' }

# --- 2: no extension typed, dropdown moved to JPEG ----------------------------
$r = Do-Save "$obj\sf_b" 1
"sf_b: dropdown row $($r.row), $(Hex-Head "$obj\sf_b.jpg")  (want FF D8 FF)"
if ($r.row -ne 1) { $fail += "the dropdown would not move to the JPEG row (it reports $($r.row))" }
if (-not (Is-Jpeg "$obj\sf_b.jpg")) { $fail += 'the JPEG filter did not write a JPEG' }
if (Test-Path "$obj\sf_b.png") { $fail += 'the JPEG filter still appended .png' }

# --- 3: an extension the user typed wins over the dropdown --------------------
$r = Do-Save "$obj\sf_c.png" 1
"sf_c: dropdown row $($r.row), name typed as .png, $(Hex-Head "$obj\sf_c.png")"
if (-not (Is-Png "$obj\sf_c.png")) { $fail += 'a typed .png against the JPEG filter did not write a PNG' }
if (Test-Path "$obj\sf_c.jpg") { $fail += 'a typed .png against the JPEG filter wrote a .jpg anyway' }

if (-not $proc.HasExited) { $proc.Kill() }
if ($fail.Count) { "FAILURES: $($fail.Count)"; $fail | ForEach-Object { "  $_" }; exit 1 }
'PASS'
