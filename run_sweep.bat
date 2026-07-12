@echo off
setlocal
set GODOT="C:\Users\franc\Desktop\Godot_v4.7-stable_mono_win64\Godot_v4.7-stable_mono_win64.exe"
cd /d "%~dp0"
echo Project folder: %CD%
if not exist "%GODOT%" (
    echo [ERROR] Godot not found at %GODOT%
    pause
    exit /b 1
)
echo.
echo ==================== 1/2  Building C# ====================
dotnet build -c Debug -t:Rebuild > sweep_build.txt 2>&1
findstr /C:"Build succeeded" sweep_build.txt >nul
if errorlevel 1 (
    echo [BUILD FAILED] Showing errors:
    findstr /C:": error" sweep_build.txt
    pause
    exit /b 1
)
echo Build succeeded.
echo.
echo ============ 2/2  DEPTH x BUDGET SWEEP + DATA HARVEST (leave this window open) ============
echo Phase 1: d3@1400ms vs champion d2@700ms (80 matches)
echo Phase 2: d4@2000ms vs champion (80)   Phase 3: d3@700 vs d2@700 (80)
echo Progress prints every 10 matches and is also appended to:
echo   %%APPDATA%%\Godot\app_userdata\UKO\sweep_results.txt  (+ selfplay_cs.csv training data)
echo Expected duration: several hours. Safe to interrupt; partial results persist.
echo.
"%GODOT%" --headless --path . --script "res://Scripts/Port/OvernightSweep.gd"
echo.
echo Overnight run finished.
pause
