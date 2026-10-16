Add-Type -AssemblyName System.Drawing, System.Windows.Forms
$va = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
$x0 = $va.Right - 620; $x1 = $va.Right - 44
$y0 = $va.Bottom - 48; $y1 = $va.Bottom
$w = $x1 - $x0; $h = $y1 - $y0
$bmp = New-Object System.Drawing.Bitmap $w, $h
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen([System.Drawing.Point]::new($x0, $y0), [System.Drawing.Point]::Empty, $bmp.Size)
$g.Dispose()
$white = New-Object int[] $w
$red = New-Object int[] $w
for ($x = 0; $x -lt $w; $x++) {
    for ($y = 0; $y -lt $h; $y++) {
        $c = $bmp.GetPixel($x, $y)
        if ($c.R -gt 230 -and $c.G -gt 230 -and $c.B -gt 230) { $white[$x]++ }
        elseif ($c.R -gt 190 -and $c.G -lt 110 -and $c.B -lt 110) { $red[$x]++ }
    }
}
$bmp.Dispose()
"red>=3 columns: $(($red | ForEach-Object -Begin {$i=0} -Process { if ($_ -ge 3) { "$i=$_" }; $i++ } | Select-Object -First 40) -join ' ')"
$runs = @(); $cur = $null; $gap = 0
for ($x = 0; $x -lt $w; $x++) {
    if ($red[$x] -ge 3) { if ($null -eq $cur) { $cur = @($x, $x) } else { $cur[1] = $x }; $gap = 0 }
    elseif ($null -ne $cur) { $gap++; if ($gap -gt 1) { $runs += , $cur; $cur = $null } }
}
if ($null -ne $cur) { $runs += , $cur }
"dot runs: $($runs.Count)"
foreach ($r in $runs) {
    $c = [int](($r[0] + $r[1]) / 2)
    $field = 0
    for ($x = [Math]::Max(0, $c - 14); $x -le [Math]::Min($w - 1, $c + 14); $x++) { if ($white[$x] -ge 2) { $field++ } }
    "  run $($r[0])..$($r[1]) c=$c field=$field keep=$($field -ge 20)"
}
