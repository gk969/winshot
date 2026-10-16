# Where is the selection frame in the whole image? Prints the blue runs on every
# sampled row and column, so the frame rectangle can be read off directly.
param([string]$Path = 'D:\Project\winshot\obj\d_nudge.png',
      [int]$Step = 4, [int]$Max = 24)

Add-Type -AssemblyName System.Drawing
$img = [System.Drawing.Bitmap]::FromFile($Path)
$rect = New-Object System.Drawing.Rectangle 0, 0, $img.Width, $img.Height
$data = $img.LockBits($rect, [System.Drawing.Imaging.ImageLockMode]::ReadOnly,
                      [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$by = New-Object byte[] ($data.Stride * $data.Height)
[System.Runtime.InteropServices.Marshal]::Copy($data.Scan0, $by, 0, $by.Length)
$img.UnlockBits($data)
$stride = $data.Stride
$W = $img.Width; $H = $img.Height

function IsBlue([int]$x, [int]$y) {
    $i = $y * $stride + $x * 4
    return ([int]$by[$i+2] -ge 190 -and [int]$by[$i+1] -ge 130 -and
            [int]$by[$i+1] -le 190 -and [int]$by[$i] -le 90)
}

$rows = @(); $cols = @()
for ($y = 0; $y -lt $H; $y += $Step) {
    $start = -1; $rs = @()
    for ($x = 0; $x -lt $W; $x++) {
        if (IsBlue $x $y) { if ($start -lt 0) { $start = $x } }
        elseif ($start -ge 0) { $rs += "$start..$($x-1)"; $start = -1 }
    }
    if ($start -ge 0) { $rs += "$start..$($W-1)" }
    if ($rs.Count) { $rows += "y$y" + ':' + ($rs -join ',') }
}
for ($x = 0; $x -lt $W; $x += $Step) {
    $start = -1; $rs = @()
    for ($y = 0; $y -lt $H; $y++) {
        if (IsBlue $x $y) { if ($start -lt 0) { $start = $y } }
        elseif ($start -ge 0) { $rs += "$start..$($y-1)"; $start = -1 }
    }
    if ($start -ge 0) { $rs += "$start..$($H-1)" }
    if ($rs.Count) { $cols += "x$x" + ':' + ($rs -join ',') }
}

"rows ($($rows.Count) of $($H/$Step) sampled):"
$rows | Select-Object -First $Max
"cols ($($cols.Count) of $($W/$Step) sampled):"
$cols | Select-Object -First $Max
$img.Dispose()
