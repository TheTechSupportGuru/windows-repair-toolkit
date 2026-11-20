# Diag-BCD2.ps1 - loads a COPY of the ESP's BCD as a registry hive (bypassing bcdedit) and checks the boot path. Read-only.
$out = Join-Path $env:TEMP 'suite-phase3-wst\diag-bcd2.txt'
function W($m) { Add-Content -LiteralPath $out -Value $m -Encoding UTF8 }
Set-Content -LiteralPath $out -Value "BCD hive check $(Get-Date)" -Encoding UTF8
$esp = (& mountvol.exe | Select-String 'EFI System Partition is mounted at ([A-Z]):') | ForEach-Object { $_.Matches[0].Groups[1].Value }
W "ESP letter: $esp"
$copy = Join-Path $env:TEMP 'suite-phase3-wst\BCD-esp-now.hiv'
Copy-Item -LiteralPath "${esp}:\EFI\Microsoft\Boot\BCD" -Destination $copy -Force
foreach ($f in $copy, (Join-Path $env:TEMP 'suite-phase3-wst\BCD-baseline.bak')) {
    W "`n=== $f"
    $r = (& reg.exe load 'HKLM\WST_BCD_CHECK' $f 2>&1 | Out-String).Trim(); W "reg load: $r"
    if ($r -match 'success') {
        try {
            $objs = 'HKLM:\WST_BCD_CHECK\Objects'
            $all = @(Get-ChildItem $objs)
            W "objects: $($all.Count)"
            $bm = Join-Path $objs '{9dea862c-5cdd-4e70-acc1-f32b344d4795}\Elements'
            $def = (Get-ItemProperty (Join-Path $bm '23000003') -ErrorAction SilentlyContinue).Element
            W "{bootmgr} default (23000003) = $def"
            $dorder = (Get-ItemProperty (Join-Path $bm '24000001') -ErrorAction SilentlyContinue).Element
            W "{bootmgr} displayorder = $($dorder -join ',')"
            $bmPath = (Get-ItemProperty (Join-Path $bm '12000002') -ErrorAction SilentlyContinue).Element
            W "{bootmgr} path = $bmPath"
            if ($def) {
                $le = Join-Path $objs "$def\Elements"
                W ("default loader exists: {0}" -f (Test-Path $le))
                W ("  path (12000002)        = {0}" -f (Get-ItemProperty (Join-Path $le '12000002') -ErrorAction SilentlyContinue).Element)
                W ("  description (12000004) = {0}" -f (Get-ItemProperty (Join-Path $le '12000004') -ErrorAction SilentlyContinue).Element)
                W ("  systemroot (22000002)  = {0}" -f (Get-ItemProperty (Join-Path $le '22000002') -ErrorAction SilentlyContinue).Element)
                W ("  safeboot (25000080)    = {0}" -f (Get-ItemProperty (Join-Path $le '25000080') -ErrorAction SilentlyContinue).Element)
                W ("  osdevice (21000001) present = {0}" -f [bool](Get-ItemProperty (Join-Path $le '21000001') -ErrorAction SilentlyContinue))
            }
            foreach ($o in $all) {
                $d = (Get-ItemProperty (Join-Path $o.PSPath 'Elements\12000004') -ErrorAction SilentlyContinue).Element
                if ($d) { W ("  object {0}  description: {1}" -f $o.PSChildName, $d) }
            }
        } catch { W "read error: $($_.Exception.Message)" }
        finally { [gc]::Collect(); Start-Sleep 1; W ("reg unload: " + (& reg.exe unload 'HKLM\WST_BCD_CHECK' 2>&1 | Out-String).Trim()) }
    }
}
W "`nDONE"
