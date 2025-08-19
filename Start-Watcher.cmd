@echo off
setlocal

REM === KONFIGURACJA DO EDYCJI ===
set SOURCE_PATH=C:\Users\adaml\OneDrive\Pulpit\GrafikWPF - projekt - GPT mods
set REMOTE_NAME=mirror
set REMOTE_URL=https://github.com/Arder1980/GrafikWPF-mirror.git
set REMOTE_BRANCH=public
set DEBOUNCE_SECONDS=3
REM Pelna sciezka do git.exe (TO MUSI BYC git.exe, nie GitHubDesktop.exe)
set GIT_EXE=C:\Program Files\Git\cmd\git.exe
REM === KONIEC KONFIGURACJI ===

set PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe

echo === uruchamiam Watcher.ps1 ===
echo Plik: "C:\Users\adaml\OneDrive\Pulpit\GrafikWPF - projekt - GPT mods\Watcher.ps1"
echo SourcePath: "%SOURCE_PATH%"
echo GitExe: "%GIT_EXE%"
echo ================================

"%PS%" -ExecutionPolicy Bypass -NoProfile -NoExit -File "C:\Users\adaml\OneDrive\Pulpit\GrafikWPF - projekt - GPT mods\Watcher.ps1" ^
  -SourcePath "%SOURCE_PATH%" ^
  -RemoteName "%REMOTE_NAME%" ^
  -RemoteUrl "%REMOTE_URL%" ^
  -RemoteBranch "%REMOTE_BRANCH%" ^
  -DebounceSeconds %DEBOUNCE_SECONDS% ^
  -GitExe "%GIT_EXE%"

pause
endlocal
