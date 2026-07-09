@echo off
setlocal
set GODOT="C:\Users\franc\Desktop\Godot_v4.7-stable_mono_win64\Godot_v4.7-stable_mono_win64.exe"

cd /d "%~dp0"
echo Project folder: %CD%

if not exist "%GODOT%" (
    echo [ERROR] Godot not found at:
    echo   %GODOT%
    echo Edit the GODOT line in this .bat with the right path.
    pause
    exit /b 1
)
if not exist "Scripts\AI\Tuning\CollectCalibration.gd" (
    echo [ERROR] Scripts\AI\Tuning\CollectCalibration.gd is missing in THIS folder.
    echo Either the .bat is not in the UKO project folder, or the Tuning files were not copied.
    pause
    exit /b 1
)

echo Found Godot and the test script.
echo Running the tests now -- this can be SILENT for 1-3 minutes while the AI
echo thinks (63 full decisions) and Godot imports assets. Please wait...
echo.
"%GODOT%" --headless --path . --script "res://Scripts/AI/Tuning/CollectCalibration.gd" > calibration_log.txt 2>&1
echo ---------------- test output ----------------
type calibration_log.txt
echo ----------------------------------------------
echo (The same output was saved to calibration_log.txt in this folder.)
pause
