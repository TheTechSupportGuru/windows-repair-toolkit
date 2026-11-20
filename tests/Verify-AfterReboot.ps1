# Verify-AfterReboot.ps1 - read-only: BCD healthy + equal to the pre-test baseline, and the Sysprep pre-flight Appx check. Run as admin.
$d = Join-Path $env:TEMP 'suite-phase3-wst'; New-Item -ItemType Directory -Force $d | Out-Null
$out = Join-Path $d 'verify2.txt'
function W($m) { Add-Content -LiteralPath $out -Value $m -Encoding UTF8 }
Set-Content -LiteralPath $out -Value "Verify after 2nd reboot $(Get-Date)" -Encoding UTF8
W "system store loaded: $(Test-Path 'HKLM:\BCD00000000')"
$now = (& bcdedit.exe /enum all /v 2>&1 | Out-String); W "bcdedit /enum all exit: $LASTEXITCODE"
$base = Join-Path $d 'bcd-enum-before.txt'
if (Test-Path $base) { W ("differences vs. pre-test baseline: {0}" -f @(Compare-Object (Get-Content $base | Where-Object { $_.Trim() }) ($now -split "`r?`n" | Where-Object { $_.Trim() })).Count) }
W "drive letters: $(([IO.DriveInfo]::GetDrives().Name) -join ' ')"
try { $n = @(Get-AppxProvisionedPackage -Online -ErrorAction Stop).Count; W "Get-AppxProvisionedPackage -Online: OK, $n packages" } catch { W "Get-AppxProvisionedPackage -Online FAILED: $($_.Exception.Message)" }
try { $n = @(Get-AppxPackage -AllUsers -ErrorAction Stop).Count; W "Get-AppxPackage -AllUsers: OK, $n packages" } catch { W "Get-AppxPackage -AllUsers FAILED: $($_.Exception.Message)" }
W "DONE"
