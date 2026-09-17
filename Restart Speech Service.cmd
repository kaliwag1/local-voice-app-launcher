@echo off
setlocal
echo Stopping the local speech service and the voice app...
taskkill /F /IM "speech-to-speech.exe" /T >nul 2>&1
taskkill /F /IM "Qwen Audio Agent.exe" /T >nul 2>&1
timeout /t 2 /nobreak >nul
echo Starting everything again (this reads .selected-voice and .selected-voice-model as usual)...
call "%~dp0Start My Voice App.cmd"
