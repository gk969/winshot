param([string]$src,[int]$x0,[int]$x1,[string]$out)
Add-Type -AssemblyName System.Drawing
$bmp = New-Object System.Drawing.Bitmap $src
$w = $x1 - $x0
$dst = New-Object System.Drawing.Bitmap ($w*6), ($bmp.Height*6)
$g = [System.Drawing.Graphics]::FromImage($dst)
$g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
$g.DrawImage($bmp, (New-Object System.Drawing.Rectangle 0,0,($w*6),($bmp.Height*6)),
             $x0, 0, $w, $bmp.Height, [System.Drawing.GraphicsUnit]::Pixel)
$g.Dispose(); $bmp.Dispose()
$dst.Save($out); $dst.Dispose()
"saved $out"
