@echo off
setlocal
cd /d "%~dp0"
set USERDIR=%APPDATA%\Godot\app_userdata\UKO
echo ==================== FIT VALUE -- FAST -- round 21 ====================
echo Fits the CHALLENGER judge from the WHOLE harvest in minutes (C#, all cores).
echo Reads:  %USERDIR%\selfplay_v3.csv
echo Writes: %USERDIR%\value_fn_new.cfg -- the challenger, never live by itself.
echo Then, exactly as usual: run_value_arena.bat, the USE_VALUE gates, and
echo run_promote_value.bat if it earns it.
echo.
echo ==================== 1/2  Building ====================
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
echo ==================== 2/2  Fitting ====================
Tools\HarvestRunner\bin\Release\net8.0\HarvestRunner.exe --fit "%USERDIR%\selfplay_v3.csv" --fit-out "%USERDIR%\value_fn_new.cfg"
echo.
pause
