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
echo ==================== PROMOTING THE CHALLENGER JUDGE ====================
echo Copies user://value_fn_new.cfg over user://value_fn.cfg with a rollback
echo backup. Run this ONLY after the arena said PROMOTE and the gates were
echo green with USE_VALUE. Instant.
%GODOT% --headless --path . --script "res://Scripts/Port/PromoteValue.gd"
echo.
echo Done. The next EXTREME match plays with the promoted judge.
pause
