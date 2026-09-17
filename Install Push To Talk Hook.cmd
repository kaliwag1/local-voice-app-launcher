@echo off
setlocal
set "ROOT=%~dp0qwen-audio-agent-editable"
cd /d "%ROOT%" || (echo Project folder not found & pause & exit /b 1)
echo Installing the system-wide push-to-talk keyboard hook (uiohook-napi)...
call npm install --workspace desktop --no-audit --no-fund || goto :fail
echo.
echo Installed. Now run "Rebuild My Voice App.cmd", then start the app as usual.
pause
exit /b 0
:fail
echo.
echo Install FAILED. Check your internet connection and try again.
pause
exit /b 1
