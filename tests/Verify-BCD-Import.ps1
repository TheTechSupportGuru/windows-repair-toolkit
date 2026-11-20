# Verify-BCD-Import.ps1 - after the reboot: (1) is the BCD healthy and equal to the pre-test baseline?
# (2) does a plain "bcdedit /import" - exactly what WinSuperTool's "BCD: restore from backup" runs - work on its own?
# (3) does the Sysprep pre-flight Appx check work? Run as admin. Writes %TEMP%\suite-phase3-wst\verify.txt
$d = Join-Path $env:TEMP 'suite-phase3-wst'; New-Item -ItemType Directory -Force $d | Out-Null
$out = Join-Path $d 'verify.txt'
function W($m) { Add-Content -LiteralPath $out -Value $m -Encoding UTF8 }
Set-Content -LiteralPath $out -Value "Verify after reboot $(Get-Date)" -Encoding UTF8
W "system store loaded: $(Test-Path 'HKLM:\BCD00000000')"
$now = (& bcdedit.exe /enum all /v 2>&1 | Out-String)
W "bcdedit /enum all exit: $LASTEXITCODE"
$now | Set-Content (Join-Path $d 'bcd-enum-after-reboot.txt')
$base = Join-Path $d 'bcd-enum-before.txt'
if (Test-Path $base) {
    $diff = @(Compare-Object (Get-Content $base | Where-Object { $_.Trim() }) ($now -split "`r?`n" | Where-Object { $_.Trim() }))
    W "differences vs. pre-test baseline: $($diff.Count)"
    $diff | ForEach-Object { W ("   {0} {1}" -f $_.SideIndicator, $_.InputObject) }
}
$cur = (& bcdedit.exe /enum '{current}' | Out-String)
W ("{current}: safeboot={0}  bootmenupolicy={1}  recoveryenabled={2}" -f $(if ($cur -match '(?m)^safeboot\s+(\S+)') { $Matches[1] } else { '(none)' }), $(if ($cur -match '(?m)^bootmenupolicy\s+(\S+)') { $Matches[1] } else { '?' }), $(if ($cur -match '(?m)^recoveryenabled\s+(\S+)') { $Matches[1] } else { '?' }))
W ("Safe Mode clones left: {0}" -f ([regex]::Matches((& bcdedit.exe /enum osloader | Out-String), 'Safe Mode \(minimal\)')).Count)
W "drive letters: $(([IO.DriveInfo]::GetDrives().Name) -join ' ')"

# ---- (2) isolated import: export now -> import the same file (no ESP letter, no /store) ----
$exp = Join-Path $d 'BCD-iso-export.bak'
$o = (& bcdedit.exe /export $exp 2>&1 | Out-String).Trim(); W "`nexport: exit $LASTEXITCODE  $o"
W "IMPORT TEST starting $(Get-Date -Format HH:mm:ss) (if this run ends here, the import hung)"
$o = (& bcdedit.exe /import $exp 2>&1 | Out-String).Trim(); $rc = $LASTEXITCODE
W "import: exit $rc  $o"
W "after import: system store loaded: $(Test-Path 'HKLM:\BCD00000000'); bcdedit /enum {current} exit: $((& bcdedit.exe /enum '{current}' 2>&1 | Out-Null); $LASTEXITCODE)"
$after = (& bcdedit.exe /enum all /v 2>&1 | Out-String)
W ("differences after import vs. before import: {0}" -f @(Compare-Object ($now -split "`r?`n" | Where-Object { $_.Trim() }) ($after -split "`r?`n" | Where-Object { $_.Trim() })).Count)

# ---- (3) Appx pre-flight check ----
try { $n = @(Get-AppxProvisionedPackage -Online -ErrorAction Stop).Count; W "`nGet-AppxProvisionedPackage -Online: OK, $n packages" } catch { W "`nGet-AppxProvisionedPackage -Online FAILED: $($_.Exception.Message)" }
try { $n = @(Get-AppxPackage -AllUsers -ErrorAction Stop).Count; W "Get-AppxPackage -AllUsers: OK, $n packages" } catch { W "Get-AppxPackage -AllUsers FAILED: $($_.Exception.Message)" }
W "DONE"
