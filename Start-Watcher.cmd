@echo off
echo === Start Watcher ===
set SCRIPT_DIR=%~dp0
powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%Watcher.ps1"
pause
