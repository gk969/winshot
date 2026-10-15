$p = Start-Process -FilePath 'D:\Project\winshot\x64\Debug\winshot.exe' -PassThru
Start-Sleep -Seconds 3
if ($p.HasExited) {
    "EXITED code=$($p.ExitCode)"
} else {
    "ALIVE pid=$($p.Id) mainwindow=$($p.MainWindowHandle)"
    $p.Kill()
    "killed"
}
