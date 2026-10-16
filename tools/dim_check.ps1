# Spot-checks the summon-time dim: away from the frame, the size card, the
# magnifier and the cursor, every pixel must be the desktop at 40%.
Add-Type -AssemblyName System.Drawing

function Pixels($bmp) {
    $rect = New-Object System.Drawing.Rectangle 0, 0, $bmp.Width, $bmp.Height
    $data = $bmp.LockBits($rect, [System.Drawing.Imaging.ImageLockMode]::ReadOnly,
                          [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $bytes = New-Object byte[] ($data.Stride * $data.Height)
    [System.Runtime.InteropServices.Marshal]::Copy($data.Scan0, $bytes, 0, $bytes.Length)
    $bmp.UnlockBits($data)
    return ,@($bytes, $data.Stride)
}

$base = [System.Drawing.Bitmap]::FromFile('D:\Project\winshot\obj\base.png')
$shot = [System.Drawing.Bitmap]::FromFile('D:\Project\winshot\obj\overlay.png')
$ba = Pixels $base; $bb = Pixels $shot
$A = $ba[0]; $sa = $ba[1]; $B = $bb[0]; $sb = $bb[1]
$w = $base.Width; $h = $base.Height

# The card sits at the top-left, the magnifier around the cursor at (3000,1500)
# and the frame plus the handles hug the edges.
$bad = 0; $n = 0; $first = ''
for ($y = 0; $y -lt $h; $y += 7) {
    $oa = $y * $sa; $ob = $y * $sb
    for ($x = 0; $x -lt $w; $x += 7) {
        if ($x -lt 200 -and $y -lt 60) { continue }
        if ($x -gt 2900 -and $x -lt 3160 -and $y -gt 1400 -and $y -lt 1620) { continue }
        if ($x -lt 40 -or $y -lt 40 -or $x -gt $w - 40 -or $y -gt $h - 40) { continue }
        $ia = $oa + $x * 4; $ib = $ob + $x * 4
        $n++
        for ($c = 0; $c -lt 3; $c++) {
            $want = [Math]::Round($A[$ia + $c] * 0.4)
            $got = $B[$ib + $c]
            if ([Math]::Abs($want - $got) -gt 3) {
                $bad++
                if (-not $first) {
                    $first = "($x,$y) ch$c want=$want got=$got base=$($A[$ia]),$($A[$ia+1]),$($A[$ia+2]) shot=$($B[$ib]),$($B[$ib+1]),$($B[$ib])"
                }
                break
            }
        }
    }
}
"sampling $n pixels, off-model = $bad"
if ($first) { "first: $first" }
$base.Dispose(); $shot.Dispose()
