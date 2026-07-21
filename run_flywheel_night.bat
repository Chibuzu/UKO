@echo off
setlocal
set GODOT="C:\Users\franc\Desktop\Godot_v4.7-stable_mono_win64\Godot_v4.7-stable_mono_win64.exe"
if defined UKO_GODOT set GODOT="%UKO_GODOT%"
cd /d "%~dp0"
if not exist %GODOT% (
    echo [ERROR] Godot not found at %GODOT% -- edit this .bat or set UKO_GODOT.
    pause
    exit /b 1
)
echo ==================== THE FLYWHEEL NIGHT -- one click ====================
echo Runs the whole generation loop in sequence, unattended:
echo   1/4  build C#      -- a minute
echo   2/4  HARVEST       -- 450 judge-armed mirror matches, ~9-10 hours
echo   3/4  FIT           -- trains the CHALLENGER from the harvest, minutes
echo   4/4  ARENA         -- challenger vs live judge, 450 matches, ~8-12 hours
echo The full loop is a weekend button: roughly 18-22 hours end to end. For a
echo single overnight, run the three bats separately across two nights instead.
echo In the morning-after: read the arena FINAL + VERDICT at the bottom here.
echo If it says PROMOTE: gates with USE_VALUE, then run_promote_value.bat.
echo.
echo ==================== 1/4  Building C# ====================
dotnet build -c Debug > flywheel_build.txt 2>&1
findstr /C:"Build succeeded" flywheel_build.txt >nul
if errorlevel 1 (
    echo [BUILD FAILED] Errors:
    findstr /C:": error" flywheel_build.txt
    pause
    exit /b 1
)
echo Build succeeded.
echo.
echo ==================== 2/4  HARVEST ====================
set UKO_MODE=harvest
%GODOT% --headless --path . --script "res://Scripts/Port/OvernightSweep.gd"
set UKO_MODE=
if errorlevel 1 echo [WARN] harvest exited with an error -- the fit will use whatever rows exist.
echo.
echo ==================== 3/4  FITTING THE CHALLENGER ====================
%GODOT% --headless --path . --script "res://Scripts/AI/Tuning/FitValue.gd"
if errorlevel 1 echo [WARN] fit reported an error -- the arena may test a STALE challenger.
echo.
echo ==================== 4/4  VALUE ARENA: challenger vs live ====================
%GODOT% --headless --path . --script "res://Scripts/Port/ValueArena.gd"
echo.
echo ==================== FLYWHEEL NIGHT DONE ====================
echo Scroll up for the fit report and the arena FINAL + VERDICT lines.
echo PROMOTE verdict: flip USE_VALUE true in PositionTests.gd, run
echo run_position_tests.bat, expect six green, flip it back to false, then
echo run_promote_value.bat. Paste me the fit report, gate rates, and verdict.
pause
