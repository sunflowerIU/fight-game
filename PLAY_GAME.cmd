@echo off
set "GODOT_EXE=C:\Users\Amit\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe"
if not exist "%GODOT_EXE%" (
  echo Godot was not found at:
  echo %GODOT_EXE%
  echo Open project.godot in Godot and press Play Project instead.
  pause
  exit /b 1
)
start "Himalayan Duel" "%GODOT_EXE%" --path "%~dp0."
