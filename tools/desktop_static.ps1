# Is the desktop static enough for the pixel-diff regressions to mean anything?
Add-Type -AssemblyName System.Drawing, System.Windows.Forms

function Grab([string]$path) {
    $bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    $img = New-Object System.Drawing.Bitmap $bounds.Width, $bounds.Height
    $gfx = [System.Drawing.Graphics]::FromImage($img)
    $gfx.CopyFromScreen($bounds.Location, [System.Drawing.Point]::Empty, $img.Size)
    $img.Save($path)
    $gfx.Dispose()
    return $img
}

function Pixels($img) {
    $rect = New-Object System.Drawing.Rectangle 0, 0, $img.Width, $img.Height
    $data = $img.LockBits($rect, [System.Drawing.Imaging.ImageLockMode]::ReadOnly,
                          [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $bytes = New-Object byte[] ($data.Stride * $data.Height)
    [System.Runtime.InteropServices.Marshal]::Copy($data.Scan0, $bytes, 0, $bytes.Length)
    $img.UnlockBits($data)
    return ,@($bytes, $data.Stride)
}

$one = Grab 'D:\Project\winshot\obj\tw1.png'
Start-Sleep -Seconds 2
$two = Grab 'D:\Project\winshot\obj\tw2.png'

$p1 = Pixels $one
$p2 = Pixels $two
$A = $p1[0]; $s1 = $p1[1]
$B = $p2[0]; $s2 = $p2[1]
$w = $one.Width; $h = $one.Height

$diff = 0; $n = 0; $first = ''
for ($y = 0; $y -lt $h; $y += 7) {
    $o1 = $y * $s1; $o2 = $y * $s2
    for ($x = 0; $x -lt $w; $x += 7) {
        $i1 = $o1 + $x * 4; $i2 = $o2 + $x * 4
        $n++
        if ($A[$i1] -ne $B[$i2] -or $A[$i1+1] -ne $B[$i2+1] -or $A[$i1+2] -ne $B[$i2+2]) {
            $diff++
            if (-not $first) {
                $first = "($x,$y) a=$($A[$i1]),$($A[$i1+1]),$($A[$i1+2]) b=$($B[$i2]),$($B[$i2+1]),$($B[$i2])"
            }
        }
    }
}
"desktop vs desktop 2s apart: $diff of $n sampled pixels differ"
if ($first) { "first: $first" }
$one.Dispose(); $two.Dispose()
