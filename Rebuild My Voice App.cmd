@echo off
setlocal
set "ROOT=%~dp0qwen-audio-agent-editable"
set "LOG=%~dp0Last Rebuild.log"
cd /d "%ROOT%" || (echo Project folder not found & pause & exit /b 1)
echo Closing the voice app so build files are not locked...
taskkill /F /IM "Qwen Audio Agent.exe" /T >nul 2>&1
echo Stopping the local speech service too (a leftover one keeps a dead session and goes silent)...
taskkill /F /IM "speech-to-speech.exe" /T >nul 2>&1
REM A force-kill never reaches the app's own shutdown, so the local model server it
REM started stays up holding its weights in VRAM with nothing attached. Release it
REM here; the helper only stops a server recorded as ours and leaves others alone.
echo Releasing the local model server if the app was holding one...
call node "%ROOT%/desktop/src/bonsai-runtime.mjs" stop unused 0 "%~dp0." || echo   Could not release it - check what is on port 8080.
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
