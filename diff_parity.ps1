$d  = Join-Path $env:APPDATA 'Godot\app_userdata\UKO'
$gd = Join-Path $d 'parity_gd.txt'
$cs = Join-Path $d 'parity_cs.txt'
if (-not (Test-Path $cs)) { Write-Host 'parity_cs.txt NOT found - the dump did not write it; check the run output above.'; return }
if (-not (Test-Path $gd)) { Write-Host 'parity_gd.txt NOT found - regenerate it with run_parity.bat first.'; return }
$r = Compare-Object (Get-Content $gd) (Get-Content $cs)
if ($null -eq $r -or $r.Count -eq 0) {
    Write-Host 'IDENTICAL - port verified (all 673 cases match).'
} else {
    Write-Host ('MISMATCH - {0} differing line(s). First 20:' -f $r.Count)
    $r | Select-Object -First 20 | Format-Table -AutoSize
}
