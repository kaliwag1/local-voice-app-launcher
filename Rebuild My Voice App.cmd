@echo off
setlocal
set "ROOT=%~dp0qwen-audio-agent-editable"
set "LOG=%~dp0Last Rebuild.log"
cd /d "%ROOT%" || (echo Project folder not found & pause & exit /b 1)
echo Closing the voice app so build files are not locked...
taskkill /F /IM "Qwen Audio Agent.exe" /T >nul 2>&1
echo Building web UI... (log: "%LOG%")
call npm run build > "%LOG%" 2>&1 || goto :fail
echo Packaging desktop app (win-unpacked only, no installer)...
call npx electron-builder --config desktop/electron-builder.yml --win --x64 --dir --publish never --config.directories.output=dist/desktop-panel >> "%LOG%" 2>&1 || goto :fail
echo.
echo Rebuild finished OK. Launch the app from "My Local Voice App" as usual.
pause
exit /b 0
:fail
echo.
echo Rebuild FAILED. See "%LOG%" for details.
pause
exit /b 1
