# diff_parity.ps1 -- compares the two engine oracles. ALWAYS pauses at the end so
# the verdict is readable no matter how it was launched.
try {
    $d  = Join-Path $env:APPDATA 'Godot\app_userdata\UKO'
    $gd = Join-Path $d 'parity_gd.txt'
    $cs = Join-Path $d 'parity_cs.txt'
    Write-Host "Looking in: $d"
    if (-not (Test-Path $gd)) { Write-Host 'parity_gd.txt NOT found -> run run_parity.bat first.' -ForegroundColor Yellow }
    if (-not (Test-Path $cs)) { Write-Host 'parity_cs.txt NOT found -> open ParityDumpCS.tscn in Godot and press F6.' -ForegroundColor Yellow }
    if ((Test-Path $gd) -and (Test-Path $cs)) {
        $g = Get-Item $gd; $c = Get-Item $cs
        Write-Host ("parity_gd.txt  {0,10:n0} bytes  written {1}" -f $g.Length, $g.LastWriteTime)
        Write-Host ("parity_cs.txt  {0,10:n0} bytes  written {1}" -f $c.Length, $c.LastWriteTime)
        $r = Compare-Object (Get-Content $gd) (Get-Content $cs)
        if ($null -eq $r -or $r.Count -eq 0) {
            Write-Host 'IDENTICAL - both engines fingerprint the same game. Safe to proceed.' -ForegroundColor Green
        } else {
            Write-Host ('MISMATCH - {0} differing line(s). First 20 below -- STOP, do not harvest; bring these to Claude:' -f $r.Count) -ForegroundColor Red
            $r | Select-Object -First 20 | Format-Table -AutoSize | Out-String | Write-Host
        }
    }
} catch {
    Write-Host "SCRIPT ERROR: $($_.Exception.Message)" -ForegroundColor Red
}
Read-Host 'Press Enter to close'
