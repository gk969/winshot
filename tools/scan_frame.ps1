# Where is the selection frame in a screenshot? Scans a row and a column for the
# two-pixel blue band and prints every run, plus the dim ratio along the way.
param([string]$Path = 'D:\Project\winshot\obj\d_nudge.png',
      [int]$RowY = 1100, [int]$ColX = 1700)

Add-Type -AssemblyName System.Drawing
$img = [System.Drawing.Bitmap]::FromFile($Path)
$rect = New-Object System.Drawing.Rectangle 0, 0, $img.Width, $img.Height
$data = $img.LockBits($rect, [System.Drawing.Imaging.ImageLockMode]::ReadOnly,
                      [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$by = New-Object byte[] ($data.Stride * $data.Height)
[System.Runtime.InteropServices.Marshal]::Copy($data.Scan0, $by, 0, $by.Length)
$img.UnlockBits($data)
$stride = $data.Stride

function IsBlue([int]$x, [int]$y) {
    $i = $y * $stride + $x * 4
    return ([int]$by[$i+2] -ge 190 -and [int]$by[$i+1] -ge 130 -and
            [int]$by[$i+1] -le 190 -and [int]$by[$i] -le 90)
}

$runs = @(); $start = -1
for ($x = 0; $x -lt $img.Width; $x++) {
    if (IsBlue $x $RowY) { if ($start -lt 0) { $start = $x } }
    elseif ($start -ge 0) { $runs += "$start..$($x-1)"; $start = -1 }
}
if ($start -ge 0) { $runs += "$start..$($img.Width-1)" }
"row y=$RowY blue runs: $($runs -join ' ')"

$runs = @(); $start = -1
for ($y = 0; $y -lt $img.Height; $y++) {
    if (IsBlue $ColX $y) { if ($start -lt 0) { $start = $y } }
    elseif ($start -ge 0) { $runs += "$start..$($y-1)"; $start = -1 }
}
if ($start -ge 0) { $runs += "$start..$($img.Height-1)" }
"col x=$ColX blue runs: $($runs -join ' ')"

# Brightness along the same row tells where the dim boundary is: the still is
# brighter than the dimmed desktop.
$samples = @()
foreach ($x in 1200, 1290, 1300, 1310, 1360, 1600, 2190, 2200, 2210, 2400) {
    $i = $RowY * $stride + $x * 4
    $samples += "x$x=$([int]$by[$i+2]),$([int]$by[$i+1]),$([int]$by[$i])"
}
"row y=$RowY brightness: $($samples -join ' ')"
$img.Dispose()
