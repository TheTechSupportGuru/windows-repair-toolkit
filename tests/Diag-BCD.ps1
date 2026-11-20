# Diag-BCD.ps1 - READ-ONLY diagnosis of the boot configuration after the failed bcdedit /import. Changes nothing.
$out = Join-Path $env:TEMP 'suite-phase3-wst\diag-bcd.txt'
function W($m) { Add-Content -LiteralPath $out -Value $m -Encoding UTF8 }
Set-Content -LiteralPath $out -Value "BCD diagnosis $(Get-Date)" -Encoding UTF8
W "`n--- system store hive loaded (HKLM\BCD00000000)? $(Test-Path 'HKLM:\BCD00000000')"
W "--- bcdedit /enum {bootmgr}:"; W ((& bcdedit.exe /enum '{bootmgr}' 2>&1) | Out-String)
W "--- partitions + letters:"; W ((Get-Partition -DiskNumber 0 | Format-Table PartitionNumber, DriveLetter, Type, @{n = 'Paths'; e = { $_.AccessPaths -join ' ; ' } } -AutoSize | Out-String -Width 250))
W "--- mountvol (volumes and mount points):"; W ((& mountvol.exe | Select-String '\\\\\?\\Volume|[A-Z]:\\' | ForEach-Object { $_.Line.Trim() }) -join "`n")
foreach ($d in [IO.DriveInfo]::GetDrives()) {
    $f = "$($d.Name)EFI\Microsoft\Boot\BCD"
    if (Test-Path -LiteralPath $f) {
        $fi = Get-Item -LiteralPath $f -Force
        W "--- ESP store file on $($d.Name): size $($fi.Length) bytes, modified $($fi.LastWriteTime)"
        W ("    LOG files: " + ((Get-ChildItem "$($d.Name)EFI\Microsoft\Boot" -Force -Filter 'BCD*' | ForEach-Object { "$($_.Name)=$($_.Length) $($_.LastWriteTime)" }) -join ' | '))
        $tmp = Join-Path $env:TEMP 'suite-phase3-wst\BCD-copy-of-ESP'
        try { Copy-Item -LiteralPath $f -Destination $tmp -Force -ErrorAction Stop; W "    copied for inspection -> $tmp"
              W "    bcdedit /store <copy> /enum {bootmgr}:"; W ((& bcdedit.exe /store $tmp /enum '{bootmgr}' 2>&1) | Out-String)
              W "    bcdedit /store <copy> /enum osloader:"; W ((& bcdedit.exe /store $tmp /enum osloader 2>&1) | Out-String)
        } catch { W "    could not copy: $($_.Exception.Message)" }
    }
}
W "--- baseline export we made at the start:"; $b = Join-Path $env:TEMP 'suite-phase3-wst\BCD-baseline.bak'
if (Test-Path $b) { W "    size $((Get-Item $b).Length)"; W ((& bcdedit.exe /store $b /enum osloader 2>&1) | Out-String) }
W "--- System event log, last 15 min, Bcd/boot related:"
W ((Get-WinEvent -FilterHashtable @{ LogName = 'System'; StartTime = (Get-Date).AddMinutes(-15) } -ErrorAction SilentlyContinue | Where-Object { $_.Message -match '(?i)bcd|boot config' } | Select-Object -First 10 | Format-List TimeCreated, Id, ProviderName, Message | Out-String))
W "DONE"
