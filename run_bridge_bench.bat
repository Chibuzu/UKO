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
dotnet build -c Debug > bridge_build.txt 2>&1
findstr /C:"Build succeeded" bridge_build.txt >nul
if errorlevel 1 (
    echo [BUILD FAILED] Showing errors:
    findstr /C:": error" bridge_build.txt
    pause
    exit /b 1
)
echo Build succeeded.

echo.
echo ============ 2/2  Running bridge benchmark (headless) ============
echo (correctness A/B on ~330 cases, then 3x2000 timed resolves; ~10-60s)
"%GODOT%" --headless --path . --script "res://Scripts/Port/BridgeBench.gd" > bridge_run.txt 2>&1
type bridge_run.txt
echo.
pause
