@echo off
setlocal
cd /d "%~dp0"
set USERDIR=%APPDATA%\Godot\app_userdata\UKO
echo ==================== UKO GAME SERVER -- round 13 ====================
echo The authoritative match server: lobby codes, quick match, bot duels vs
echo EXTREME, the online clash sub-round, and a training log of every match.
echo Local address for game clients: ws://127.0.0.1:8765
echo Run "run_server.bat test" once first: the server plays full matches
echo against itself over real sockets and reports PASS or FAIL per check.
echo.
echo ==================== 1/2  Building the server ====================
dotnet build Tools\GameServer\GameServer.csproj -c Release > server_build.txt 2>&1
findstr /C:"Build succeeded" server_build.txt >nul
if errorlevel 1 (
    echo [BUILD FAILED] Errors:
    findstr /C:": error" server_build.txt
    pause
    exit /b 1
)
echo Build succeeded.
echo.
if "%1"=="test" goto selftest
echo ==================== 2/2  Serving ====================
Tools\GameServer\bin\Release\net8.0\GameServer.exe --port 8765 --value-cfg "%USERDIR%\value_fn.cfg" --log "%USERDIR%\server_matches.csv"
echo.
pause
exit /b 0
:selftest
echo ==================== 2/2  SELF-TEST ====================
Tools\GameServer\bin\Release\net8.0\GameServer.exe --selftest --port 8907 --bot-budget 60
echo.
pause
