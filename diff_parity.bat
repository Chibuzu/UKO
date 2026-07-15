@echo off
rem diff_parity.bat -- compares the two engine oracles with Windows' built-in FC.
rem No PowerShell, no execution policy, nothing to block. Always pauses at the end.
setlocal
set "D=%APPDATA%\Godot\app_userdata\UKO"
set "GD=%D%\parity_gd.txt"
set "CS=%D%\parity_cs.txt"

echo Looking in: %D%
echo.

if not exist "%GD%" (
    echo parity_gd.txt NOT found -^> run run_parity.bat first.
    goto :done
)
if not exist "%CS%" (
    echo parity_cs.txt NOT found -^> open ParityDumpCS.tscn in Godot and press F6.
    goto :done
)

echo File sizes and timestamps:
for %%F in ("%GD%") do echo   parity_gd.txt  %%~zF bytes   %%~tF
for %%F in ("%CS%") do echo   parity_cs.txt  %%~zF bytes   %%~tF
echo.

fc /L "%GD%" "%CS%" > "%TEMP%\parity_diff.txt" 2>&1
if errorlevel 1 (
    echo ============================================================
    echo   MISMATCH -- the engines disagree. STOP: do not harvest.
    echo   First differing lines below; bring them to Claude.
    echo ============================================================
    rem show only the first ~40 lines of the diff so it stays readable
    setlocal enabledelayedexpansion
    set /a n=0
    for /f "usebackq delims=" %%L in ("%TEMP%\parity_diff.txt") do (
        echo %%L
        set /a n+=1
        if !n! geq 40 goto :cut
    )
    :cut
    endlocal
) else (
    echo ============================================================
    echo   IDENTICAL -- both engines fingerprint the same game.
    echo   Safe to proceed.
    echo ============================================================
)

:done
echo.
pause
