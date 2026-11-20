# Cleanup-Letters.ps1 - removes the S: (EFI) and T: (recovery) letters left behind by Run-Phase3-WST.ps1. Run as admin.
$log = Join-Path $env:TEMP 'suite-phase3-wst\cleanup.txt'
foreach ($l in 'S', 'T') {
    if (-not (Test-Path "${l}:\")) { Add-Content $log "${l}: not present"; continue }
    $o = (& mountvol.exe "${l}:" /D 2>&1 | Out-String).Trim()
    Add-Content $log ("mountvol ${l}: /D -> exit $LASTEXITCODE " + $o)
}
Add-Content $log ("letters now: " + (([IO.DriveInfo]::GetDrives().Name) -join ' '))
