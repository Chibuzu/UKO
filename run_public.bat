@echo off
setlocal
cd /d "%~dp0"
echo ==================== UKO -- PUBLIC LINK ====================
echo Puts your ALREADY-RUNNING server on the internet through a free
echo Cloudflare quick tunnel: no router changes, no account, and it works
echo even when your internet provider blocks incoming connections.
echo.
echo STEP 0: run_server.bat must be running in its OWN window first.
echo.
if exist cloudflared.exe goto run
echo ==================== 1/2  Downloading cloudflared -- one time ====================
curl -L -o cloudflared.exe https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-windows-amd64.exe
if errorlevel 1 (
    echo [DOWNLOAD FAILED] Check your internet connection and rerun.
    pause
    exit /b 1
)
:run
echo ==================== 2/2  Opening the tunnel ====================
echo Watch below for a box with a line like:
echo     https://SOMETHING-SOMETHING.trycloudflare.com
echo THAT is the link to send your friend -- game page and online play in one.
echo A NEW link is made every time this window starts; closing it takes the
echo game offline for internet players. Wi-Fi play keeps working regardless.
echo.
cloudflared.exe tunnel --url http://localhost:8765
pause
