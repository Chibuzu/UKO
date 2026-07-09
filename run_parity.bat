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
if not exist "Scripts\Port\ParityDump.gd" (
    echo [ERROR] Scripts\Port\ParityDump.gd is missing in THIS folder.
    echo Either the .bat is not in the UKO project folder, or the Port files were not copied.
    pause
    exit /b 1
)

echo Found Godot and the parity script.
echo Generating the GDScript parity oracle (deterministic; ~673 cases). This is fast,
echo but Godot may import assets first, which can be silent for a bit. Please wait...
echo.
"%GODOT%" --headless --path . --script "res://Scripts/Port/ParityDump.gd" > parity_log.txt 2>&1
echo ---------------- parity output ----------------
type parity_log.txt
echo -----------------------------------------------
echo The golden file was written to the Godot user data dir (path printed above),
echo typically: %APPDATA%\Godot\app_userdata\UKO\parity_gd.txt
echo (The same console output was saved to parity_log.txt in this folder.)
pause
