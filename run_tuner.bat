@echo off
setlocal
set GODOT=C:\Users\franc\Downloads\Godot_v4.6.2-stable_win64.exe\Godot_v4.6.2-stable_win64_console.exe

cd /d "%~dp0"
echo Project folder: %CD%

if not exist "%GODOT%" (
    echo [ERROR] Godot not found at:
    echo   %GODOT%
    echo Edit the GODOT line in this .bat with the right path.
    pause
    exit /b 1
)
if not exist "Scripts\AI\Tuning\Tuner.gd" (
    echo [ERROR] Scripts\AI\Tuning\Tuner.gd is missing in THIS folder.
    echo Either the .bat is not in the UKO project folder, or the Tuning files were not copied.
    pause
    exit /b 1
)

echo Found Godot and the test script.
echo Running the TUNER -- this is SLOW ON PURPOSE (full AI-vs-AI matches);
echo expect many minutes. Progress lines appear as iterations finish.
echo.
"%GODOT%" --headless --path . --script "res://Scripts/AI/Tuning/Tuner.gd" > tuner_log.txt 2>&1
echo ---------------- tuner output ----------------
type tuner_log.txt
echo ----------------------------------------------
echo (The same output was saved to tuner_log.txt in this folder.)
pause
