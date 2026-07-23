@echo off
setlocal
cd /d "%~dp0"
set USERDIR=%APPDATA%\Godot\app_userdata\UKO
rem Optional first argument = minutes (default 960 = 16 hours). Examples:
rem   run_fast_harvest.bat        -> 16 hours
rem   run_fast_harvest.bat 720    -> 12 hours
set MINUTES=%1
if "%MINUTES%"=="" set MINUTES=960
rem Fresh seed range EVERY launch (round 18b): the runner replays identical
rem matches if the seed base repeats, so each run draws a random base far
rem above every legacy range (godot 770k / runner 900k / cloud 1.9M / server 4M).
set /a SEEDBASE=10000001 + %RANDOM% * 60000
echo ==================== FAST HARVEST -- round 12 ====================
echo The game's C# brain as a console program: every CPU core, no Godot.
echo Writes training rows straight to:
echo   %USERDIR%\selfplay_v3.csv
echo This run: %MINUTES% minutes, seed base %SEEDBASE% -- or Ctrl+C whenever;
echo finished waves are already saved.
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
echo ==================== 2/2  Harvesting for %MINUTES% minutes ====================
Tools\HarvestRunner\bin\Release\net8.0\HarvestRunner.exe --minutes %MINUTES% --seed-base %SEEDBASE% --out "%USERDIR%\selfplay_v3.csv" --user-dir "%USERDIR%"
echo.
pause
