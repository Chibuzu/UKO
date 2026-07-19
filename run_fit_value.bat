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
echo ==================== FITTING THE LEARNED VALUE FUNCTION ====================
echo Reads user://selfplay_v2.csv, writes user://value_fn.cfg. A few minutes.
%GODOT% --headless --path . --script "res://Scripts/AI/Tuning/FitValue.gd"
echo.
echo Next: run_value_arena.bat to A/B the learned judge against the hand eval.
pause
