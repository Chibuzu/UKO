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
echo ==================== 1/2  Building C# ====================
dotnet build -c Debug > value_arena_build.txt 2>&1
findstr /C:"Build succeeded" value_arena_build.txt >nul
if errorlevel 1 (
    echo [BUILD FAILED] Errors:
    findstr /C:": error" value_arena_build.txt
    pause
    exit /b 1
)
echo Build succeeded.
echo ==================== 2/2  VALUE ARENA: learned judge ON vs OFF ====================
echo 150 matches, d3@700 both sides. This is a LONG run -- start it overnight.
echo Progress appends to user://value_arena.txt as it goes.
%GODOT% --headless --path . --script "res://Scripts/Port/ValueArena.gd"
echo.
pause
