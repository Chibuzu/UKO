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
dotnet build -c Debug > harvest_build.txt 2>&1
findstr /C:"Build succeeded" harvest_build.txt >nul
if errorlevel 1 (
    echo [BUILD FAILED] Showing errors:
    findstr /C:": error" harvest_build.txt
    pause
    exit /b 1
)
echo Build succeeded.
echo.
echo ======= 2/2  NEW-PHYSICS HARVEST NIGHT (leave this window open) =======
echo 450 mirror matches: champion d3@700 vs itself under the TICK BUNDLE rules.
echo Every turn writes a v2 training row (flank/pulse/lockout features) to:
echo   %%APPDATA%%\Godot\app_userdata\UKO\selfplay_v2.csv
echo The printout doubles as new-physics telemetry: WATCH avg-turns and draw-rate.
echo Progress every 10 matches; ~9-10 hours; safe to interrupt (partials count).
echo.
set UKO_MODE=harvest
"%GODOT%" --headless --path . --script "res://Scripts/Port/OvernightSweep.gd"
echo.
echo Harvest night finished.
pause
