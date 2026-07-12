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
dotnet build -c Debug -t:Rebuild > overnight_build.txt 2>&1
findstr /C:"Build succeeded" overnight_build.txt >nul
if errorlevel 1 (
    echo [BUILD FAILED] Showing errors:
    findstr /C:": error" overnight_build.txt
    pause
    exit /b 1
)
echo Build succeeded.
echo.
echo ============ 2/2  OVERNIGHT SELF-PLAY (leave this window open) ============
echo Phase 1: C# depth-3 vs C# depth-2 (150 matches)
echo Phase 2: C# depth-2 vs old EXTREME/EconomyAI (150 matches)
echo Progress prints every 10 matches and is also appended to:
echo   %%APPDATA%%\Godot\app_userdata\UKO\overnight_results.txt
echo Expected duration: several hours. Safe to interrupt; partial results persist.
echo.
"%GODOT%" --headless --path . --script "res://Scripts/Port/OvernightArena.gd"
echo.
echo Overnight run finished.
pause
