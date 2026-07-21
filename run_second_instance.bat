@echo off
setlocal
set GODOT="C:\Users\franc\Desktop\Godot_v4.7-stable_mono_win64\Godot_v4.7-stable_mono_win64.exe"
if defined UKO_GODOT set GODOT="%UKO_GODOT%"
cd /d "%~dp0"
echo Launching another game window -- for the two-window online duel test.
echo Window 1 can be the editor's Play; this is window 2. Both connect to the
echo server from run_server.bat via PLAY ONLINE.
start "" %GODOT% --path .
