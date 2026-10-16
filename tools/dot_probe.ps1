Add-Type -AssemblyName System.Drawing, System.Windows.Forms
$va = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
$x0 = $va.Right - 620; $x1 = $va.Right - 44
$y0 = $va.Bottom - 48; $y1 = $va.Bottom
$w = $x1 - $x0; $h = $y1 - $y0
$bmp = New-Object System.Drawing.Bitmap $w, $h
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen([System.Drawing.Point]::new($x0, $y0), [System.Drawing.Point]::Empty, $bmp.Size)
$g.Dispose()
$bmp.Save('D:\Project\winshot\obj\tray_strip.png')
$nz = @()
for ($x = 0; $x -lt $w; $x++) {
    $nr = 0
    for ($y = 0; $y -lt $h; $y++) {
        $c = $bmp.GetPixel($x, $y)
        if ($c.R -gt 190 -and $c.G -lt 110 -and $c.B -lt 110) { $nr++ }
    }
    if ($nr -gt 0) { $nz += "$x=$nr" }
}
"red columns: $($nz.Count)  $(($nz -join ' '))"
# What the strongest red column actually looks like, pixel by pixel.
$best = 0; $bx = 0
for ($x = 0; $x -lt $w; $x++) {
    $nr = 0
    for ($y = 0; $y -lt $h; $y++) {
        $c = $bmp.GetPixel($x, $y)
        if ($c.R -gt 190 -and $c.G -lt 110 -and $c.B -lt 110) { $nr++ }
    }
    if ($nr -gt $best) { $best = $nr; $bx = $x }
}
"strongest red column x=$bx (abs $($x0+$bx)) count=$best"
if ($best -gt 0) {
    $row = @()
    for ($y = 0; $y -lt $h; $y++) { $c = $bmp.GetPixel($bx, $y); $row += "$($c.R),$($c.G),$($c.B)" }
    "column pixels: $(($row -join ' | '))"
}
$bmp.Dispose()
