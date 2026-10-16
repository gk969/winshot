# Crops a region of a screenshot and scales it up, for eyeballing.
param([string]$Path = 'D:\Project\winshot\obj\d_nudge.png',
      [string]$Out = 'D:\Project\winshot\obj\crop.png',
      [int]$X = 1150, [int]$Y = 900, [int]$W = 700, [int]$H = 500,
      [double]$Scale = 1.0)

Add-Type -AssemblyName System.Drawing
$img = [System.Drawing.Bitmap]::FromFile($Path)
$dst = New-Object System.Drawing.Bitmap ([int]($W * $Scale)), ([int]($H * $Scale))
$gfx = [System.Drawing.Graphics]::FromImage($dst)
$gfx.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
$gfx.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::Half
$srcRect = New-Object System.Drawing.Rectangle $X, $Y, $W, $H
$dstRect = New-Object System.Drawing.Rectangle 0, 0, ([int]($W * $Scale)), ([int]($H * $Scale))
$gfx.DrawImage($img, $srcRect, $dstRect, [System.Drawing.GraphicsUnit]::Pixel)
$gfx.Dispose()
$dst.Save($Out)
"$Out from ($X,$Y) ${W}x${H} x$Scale"
$img.Dispose(); $dst.Dispose()
