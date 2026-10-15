$first = Get-Process winshot -ErrorAction SilentlyContinue
if (-not $first) { "no first instance; run tray_shot.ps1 first"; exit 1 }
"first pid=$($first.Id)"

$second = Start-Process -FilePath 'D:\Project\winshot\x64\Debug\winshot.exe' -PassThru
Start-Sleep -Seconds 2
$alive = Get-Process -Id $second.Id -ErrorAction SilentlyContinue
if ($alive) {
    "second still running, window title = '$($alive.MainWindowTitle)'"
    $alive.Kill()
    "killed second"
} else {
    "second exited code=$($second.ExitCode)"
}
"winshot processes now: $((Get-Process winshot -ErrorAction SilentlyContinue | Measure-Object).Count)"
