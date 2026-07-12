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
dotnet build -c Debug -t:Rebuild > brain_build.txt 2>&1
findstr /C:"Build succeeded" brain_build.txt >nul
if errorlevel 1 (
    echo [BUILD FAILED] Showing errors:
    findstr /C:": error" brain_build.txt
    pause
    exit /b 1
)
echo Build succeeded.
echo.
echo ============ 2/2  Brain agreement harness (headless) ============
echo (5 frozen positions; prints progress per position; ~1-3 min total)
"%GODOT%" --headless --path . --script "res://Scripts/Port/BrainAgreement.gd"
echo.
pause
