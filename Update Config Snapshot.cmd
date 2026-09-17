@echo off
cd /d "%~dp0"
copy /y "%USERPROFILE%\.config\qwaudio\config.env" config-snapshot\qwaudio\ >nul
copy /y "%USERPROFILE%\.config\qwaudio\USER.md" config-snapshot\qwaudio\ >nul
copy /y "%USERPROFILE%\.config\qwaudio\ASSISTANT.md" config-snapshot\qwaudio\ >nul
copy /y "%USERPROFILE%\.config\qwaudio\MEMORY.md" config-snapshot\qwaudio\ >nul
copy /y "%USERPROFILE%\.config\opencode\opencode.json" config-snapshot\opencode\ >nul
copy /y "%USERPROFILE%\.config\opencode\AGENTS.md" config-snapshot\opencode\ >nul
git add -A config-snapshot && git commit -q -m "Refresh config snapshot" && echo Snapshot committed. || echo Nothing changed.
timeout /t 3 >nul
