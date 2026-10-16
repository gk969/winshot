# Crop a rect out of a screenshot for a look, scaled up so thin strokes read.
param([Parameter(Mandatory = $true)][string]$Src,
      [Parameter(Mandatory = $true)][int]$X, [Parameter(Mandatory = $true)][int]$Y,
      [Parameter(Mandatory = $true)][int]$W, [Parameter(Mandatory = $true)][int]$H,
      [Parameter(Mandatory = $true)][string]$Dst,
      [double]$Zoom = 2.0)
Add-Type -AssemblyName System.Drawing
$b = [System.Drawing.Bitmap]::FromFile($Src)
$ow = [int]($W * $Zoom); $oh = [int]($H * $Zoom)
$c = New-Object System.Drawing.Bitmap $ow, $oh
$g = [System.Drawing.Graphics]::FromImage($c)
$g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
$g.DrawImage($b, [System.Drawing.Rectangle]::new(0, 0, $ow, $oh),
                 [System.Drawing.Rectangle]::new($X, $Y, $W, $H),
                 [System.Drawing.GraphicsUnit]::Pixel)
$g.Dispose(); $b.Dispose()
$c.Save($Dst); $c.Dispose()
"saved $Dst ($ow x $oh)"
