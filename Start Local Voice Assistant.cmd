@echo off
set "VOICE_ROOT=%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%VOICE_ROOT%Start Local Voice Assistant.ps1"
if errorlevel 1 (
  echo.
  echo The local voice assistant did not start. See the message above.
  pause
)
