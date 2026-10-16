# Prints the same handful of pixels from several screenshots side by side.
param([string]$Paths, [string]$Xs, [string]$Ys)
$PathList = $Paths -split ';'
$Xa = $Xs -split ','
$Ya = $Ys -split ','

Add-Type -AssemblyName System.Drawing
$packs = @()
foreach ($p in $PathList) {
    $img = [System.Drawing.Bitmap]::FromFile($p)
    $rect = New-Object System.Drawing.Rectangle 0, 0, $img.Width, $img.Height
    $data = $img.LockBits($rect, [System.Drawing.Imaging.ImageLockMode]::ReadOnly,
                          [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $by = New-Object byte[] ($data.Stride * $data.Height)
    [System.Runtime.InteropServices.Marshal]::Copy($data.Scan0, $by, 0, $by.Length)
    $img.UnlockBits($data)
    $packs += ,@($by, $data.Stride, (Split-Path -Leaf $p))
    $img.Dispose()
}

for ($i = 0; $i -lt $Xa.Count; $i++) {
    $x = [int]$Xa[$i]; $y = [int]$Ya[$i]
    $line = "($x,$y)"
    foreach ($pk in $packs) {
        $o = $y * $pk[1] + $x * 4
        $line += "  $($pk[2])=$([int]$pk[0][$o+2]),$([int]$pk[0][$o+1]),$([int]$pk[0][$o])"
    }
    $line
}
