@echo off
setlocal
REM ---- edit this line only ----
set "GH_USER=YOUR_GITHUB_USERNAME"
REM ------------------------------
if "%GH_USER%"=="YOUR_GITHUB_USERNAME" (
  echo Open this file in Notepad and put your GitHub username on the GH_USER line first.
  pause & exit /b 1
)
cd /d "%~dp0"
echo == Launcher scripts repo ==
git remote get-url origin >nul 2>&1 || git remote add origin "https://github.com/%GH_USER%/local-voice-app-launcher.git"
git push -u origin main || goto :fail

echo.
echo == App repo ==
cd /d "%~dp0qwen-audio-agent-editable"
git remote get-url github >nul 2>&1 || git remote add github "https://github.com/%GH_USER%/local-voice-app.git"
git push -u github main jake/local-voice-app || goto :fail

echo.
echo All pushed:
echo   https://github.com/%GH_USER%/local-voice-app-launcher
echo   https://github.com/%GH_USER%/local-voice-app   (branch jake/local-voice-app has your changes)
pause
exit /b 0
:fail
echo.
echo Push failed - see the message above. Common causes: repo not created yet on GitHub,
echo wrong username, or the browser sign-in window was closed before finishing.
pause
exit /b 1
