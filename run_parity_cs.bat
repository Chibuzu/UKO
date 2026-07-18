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
if not exist "Scripts\Port\CSharp\PortParityDump.cs" (
    echo [ERROR] Scripts\Port\CSharp\PortParityDump.cs missing in this folder.
    pause
    exit /b 1
)

echo.
echo ==================== 1/3  Building C# (dotnet build) ====================
dotnet build -c Debug -t:Rebuild > parity_cs_build.txt 2>&1
findstr /C:"Build succeeded" parity_cs_build.txt >nul
if errorlevel 1 (
    echo [BUILD FAILED] Showing errors:
    findstr /C:": error" parity_cs_build.txt
    echo Full log: parity_cs_build.txt
    pause
    exit /b 1
)
echo Build succeeded.

echo.
echo ============ 2/3  Running the C# parity dump (headless) ============
"%GODOT%" --headless --path . "res://Scripts/Port/CSharp/ParityDumpCS.tscn" > parity_cs_run.txt 2>&1
type parity_cs_run.txt

echo.
echo ==================== 3/3  Diffing vs the golden file ====================
call "%~dp0diff_parity.bat"
echo.
pause
