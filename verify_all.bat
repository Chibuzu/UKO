@echo off
rem verify_all.bat -- THE one gate after any engine/brain change, both languages.
rem Runs, in order:  1) dotnet build   2) GDScript parity oracle
rem                  3) C# parity oracle   4) byte-diff of the two oracles
rem                  5) brain agreement harness (880 numeric checks)
rem Green here == the C# twin still matches the GDScript source of truth.
rem "Did I remember to edit both sides?" is now this one command, not memory.
setlocal
set GODOT="C:\Users\franc\Desktop\Godot_v4.7-stable_mono_win64\Godot_v4.7-stable_mono_win64.exe"
if defined UKO_GODOT set GODOT="%UKO_GODOT%"
cd /d "%~dp0"
set "D=%APPDATA%\Godot\app_userdata\UKO"

if not exist %GODOT% (
    echo [ERROR] Godot not found at %GODOT%
    echo Edit the GODOT line in this .bat, or set the UKO_GODOT environment variable.
    pause
    exit /b 1
)

echo ==================== 1/5  Building C# ====================
dotnet build -c Debug -t:Rebuild > verify_build.txt 2>&1
findstr /C:"Build succeeded" verify_build.txt >nul
if errorlevel 1 (
    echo [BUILD FAILED] Errors:
    findstr /C:": error" verify_build.txt
    pause
    exit /b 1
)
echo Build succeeded.

echo ==================== 2/5  GDScript parity oracle ====================
%GODOT% --headless --path . --script "res://Scripts/Port/ParityDump.gd" > verify_gd.txt 2>&1
if not exist "%D%\parity_gd.txt" (
    echo [ERROR] parity_gd.txt was not written. Output:
    type verify_gd.txt
    pause
    exit /b 1
)

echo ==================== 3/5  C# parity oracle ====================
%GODOT% --headless --path . "res://Scripts/Port/CSharp/ParityDumpCS.tscn" > verify_cs.txt 2>&1
if not exist "%D%\parity_cs.txt" (
    echo [ERROR] parity_cs.txt was not written. Output:
    type verify_cs.txt
    pause
    exit /b 1
)

echo ==================== 4/5  Byte-diff of the oracles ====================
fc /L "%D%\parity_gd.txt" "%D%\parity_cs.txt" > "%TEMP%\parity_diff.txt" 2>&1
if errorlevel 1 (
    echo ============================================================
    echo   ENGINE MISMATCH -- the two Resolvers disagree. STOP.
    echo   First lines of the diff:
    echo ============================================================
    setlocal enabledelayedexpansion
    set /a n=0
    for /f "usebackq delims=" %%L in ("%TEMP%\parity_diff.txt") do (
        echo %%L
        set /a n+=1
        if !n! geq 40 goto :cut
    )
    :cut
    endlocal
    pause
    exit /b 1
)
echo Oracles IDENTICAL.

echo ==================== 5/5  Brain agreement (880 checks) ====================
%GODOT% --headless --path . --script "res://Scripts/Port/BrainAgreement.gd"
if errorlevel 1 (
    echo ============================================================
    echo   BRAIN MISMATCH -- the C# brain diverged from GDScript. STOP.
    echo ============================================================
    pause
    exit /b 1
)

echo.
echo ============================================================
echo   ALL GREEN: build ok, engines byte-identical, brains agree.
echo ============================================================
pause
