# Along a row, classify each pixel as the still (== base) or dimmed (== base*0.4)
# and print the runs. Locates the selection boundary without the frame.
param([string]$Base = 'D:\Project\winshot\obj\d_base.png',
      [string]$Shot = 'D:\Project\winshot\obj\d_nudge.png',
      [int]$RowY = 1100, [int]$Step = 4)

Add-Type -AssemblyName System.Drawing
function Pack($p) {
    $img = [System.Drawing.Bitmap]::FromFile($p)
    $rect = New-Object System.Drawing.Rectangle 0, 0, $img.Width, $img.Height
    $data = $img.LockBits($rect, [System.Drawing.Imaging.ImageLockMode]::ReadOnly,
                          [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $by = New-Object byte[] ($data.Stride * $data.Height)
    [System.Runtime.InteropServices.Marshal]::Copy($data.Scan0, $by, 0, $by.Length)
    $img.UnlockBits($data)
    $r = ,@($by, $data.Stride)
    $img.Dispose()
    return $r
}
$b = Pack $Base; $s = Pack $Shot
$A = $b[0]; $sa = $b[1]; $B = $s[0]; $sb = $s[1]

$state = ''; $runs = @(); $start = 0
for ($x = 0; $x -lt 3840; $x += $Step) {
    $o = $RowY * $sa + $x * 4; $p = $RowY * $sb + $x * 4
    $still = $true; $dim = $true
    for ($c = 0; $c -lt 3; $c++) {
        $av = [int]$A[$o + $c]; $bv = [int]$B[$p + $c]
        if ([Math]::Abs($av - $bv) -gt 6) { $still = $false }
        if ([Math]::Abs([Math]::Round($av * 0.4) - $bv) -gt 6) { $dim = $false }
    }
    $k = if ($still) { 'S' } elseif ($dim) { 'D' } else { '?' }
    if ($k -ne $state) {
        if ($state) { $runs += ($state + [string]$start + '..' + [string]($x - $Step)) }
        $state = $k; $start = $x
    }
}
$runs += ($state + [string]$start + '..3836')
"row ${RowY}: $($runs -join ' ')"
