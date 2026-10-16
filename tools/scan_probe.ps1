# Diagnostic for the tray scan: what the per-column counts actually reach.
Add-Type -AssemblyName System.Drawing, System.Windows.Forms
$va = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
$x0 = $va.Right - 620; $x1 = $va.Right - 44
$y0 = $va.Bottom - 48; $y1 = $va.Bottom
$w = $x1 - $x0; $h = $y1 - $y0
"strip x=$x0..$x1 y=$y0..$y1  ($w x $h)"
$bmp = New-Object System.Drawing.Bitmap $w, $h
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen([System.Drawing.Point]::new($x0, $y0),
                  [System.Drawing.Point]::Empty, $bmp.Size)
$g.Dispose()
$c0 = $bmp.GetPixel(300, 20)
"sample pixel at 300,20 = R$($c0.R) G$($c0.G) B$($c0.B) A$($c0.A)"
$maxW = 0; $maxR = 0; $colsW = 0; $colsR = 0
for ($x = 0; $x -lt $w; $x++) {
    $nw = 0; $nr = 0
    for ($y = 0; $y -lt $h; $y++) {
        $c = $bmp.GetPixel($x, $y)
        if ($c.R -gt 230 -and $c.G -gt 230 -and $c.B -gt 230) { $nw++ }
        elseif ($c.R -gt 190 -and $c.G -lt 110 -and $c.B -lt 110) { $nr++ }
    }
    if ($nw -gt $maxW) { $maxW = $nw }
    if ($nr -gt $maxR) { $maxR = $nr }
    if ($nw -ge 6) { $colsW++ }
    if ($nr -ge 1) { $colsR++ }
}
"max white column count = $maxW   columns with >=6 white = $colsW"
"max red column count   = $maxR   columns with >=1 red   = $colsR"

# The stage that came back empty in the test: runs of white columns, then the
# red check across each run.
$white = New-Object int[] $w
$red = New-Object int[] $w
"white array: type=$($white.GetType()) length=$($white.Length)  red length=$($red.Length)"
for ($x = 0; $x -lt $w; $x++) {
    for ($y = 0; $y -lt $h; $y++) {
        $c = $bmp.GetPixel($x, $y)
        if ($c.R -gt 230 -and $c.G -gt 230 -and $c.B -gt 230) { $white[$x]++ }
        elseif ($c.R -gt 190 -and $c.G -lt 110 -and $c.B -lt 110) { $red[$x]++ }
    }
}
$nz = @()
for ($x = 0; $x -lt $w; $x++) { if ($white[$x] -gt 0) { $nz += "$x=$($white[$x])" } }
"nonzero white columns: $($nz.Count)  first 20: $(($nz | Select-Object -First 20) -join ' ')"
$runs = @(); $cur = $null
for ($x = 0; $x -lt $w; $x++) {
    if ($white[$x] -ge 6) {
        if ($null -eq $cur) { $cur = @($x, $x) } else { $cur[1] = $x }
    } elseif ($null -ne $cur) {
        if ($cur[1] - $cur[0] -ge 9) { $runs += , $cur }
        $cur = $null
    }
}
if ($null -ne $cur -and $cur[1] - $cur[0] -ge 9) { $runs += , $cur }
"runs of white columns (>=9 wide): $($runs.Count)"
$kept = 0
foreach ($r in $runs) {
    $dot = 0
    for ($x = $r[0]; $x -le $r[1]; $x++) { $dot += $red[$x] }
    "  run $($r[0])..$($r[1]) width $($r[1]-$r[0]+1) dot=$dot"
    if ($dot -ge 4) { $kept++ }
}
"runs kept (dot >= 4): $kept"
