@echo off
setlocal
cd /d "%~dp0"
set USERDIR=%APPDATA%\Godot\app_userdata\UKO
echo ==================== FAST HARVEST -- round 12 ====================
echo The game's C# brain as a console program: every CPU core, no Godot.
echo Writes training rows straight to:
echo   %USERDIR%\selfplay_v3.csv
echo Default: 16 HOURS, or Ctrl+C whenever -- finished waves are already saved.
echo Afterwards: run_fit_value.bat then run_value_arena.bat, exactly as usual.
echo.
echo ==================== 1/2  Building the runner ====================
dotnet build Tools\HarvestRunner\HarvestRunner.csproj -c Release > fast_harvest_build.txt 2>&1
findstr /C:"Build succeeded" fast_harvest_build.txt >nul
if errorlevel 1 (
    echo [BUILD FAILED] Errors:
    findstr /C:": error" fast_harvest_build.txt
    pause
    exit /b 1
)
echo Build succeeded.
echo.
echo ==================== 2/2  Harvesting for 16 hours ====================
Tools\HarvestRunner\bin\Release\net8.0\HarvestRunner.exe --minutes 960 --out "%USERDIR%\selfplay_v3.csv" --user-dir "%USERDIR%"
echo.
pause
