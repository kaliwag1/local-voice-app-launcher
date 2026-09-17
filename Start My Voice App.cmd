@echo off
set "VOICE_ROOT=%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%VOICE_ROOT%Start My Voice App.ps1"
if errorlevel 1 (
  echo.
  echo The desktop voice app did not start. See the message above.
  pause
)
