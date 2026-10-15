Add-Type -AssemblyName System.Drawing, System.Windows.Forms
$p = Start-Process -FilePath 'D:\Project\winshot\x64\Debug\winshot.exe' -PassThru
Start-Sleep -Seconds 2
if ($p.HasExited) { "EXITED code=$($p.ExitCode)"; exit 1 }
"ALIVE pid=$($p.Id)"

$screen = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
$w = [Math]::Min(500, $screen.Width)
$h = [Math]::Min(120, $screen.Height)
$rect = New-Object System.Drawing.Rectangle ($screen.Right - $w), ($screen.Bottom - $h), $w, $h
"shot rect = $rect"

$bmp = New-Object System.Drawing.Bitmap $w, $h
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($rect.Location, [System.Drawing.Point]::Empty, $bmp.Size)
$bmp.Save('D:\Project\winshot\obj\tray.png')
$g.Dispose(); $bmp.Dispose()
"saved D:\Project\winshot\obj\tray.png"
