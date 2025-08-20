@echo off
setlocal

rem --- Ustaw kodowanie konsoli na UTF-8 (ładne ogonki na ekranie) ---
chcp 65001 >NUL

rem --- Przejdź do folderu skryptów (ten sam katalog co plik .cmd) ---
pushd "%~dp0"

rem --- Preferuj PowerShell 7 (pwsh), fallback do Windows PowerShell ---
where pwsh >NUL 2>&1
if %ERRORLEVEL%==0 (
  pwsh -NoProfile -ExecutionPolicy Bypass -File ".\Watcher.ps1"
) else (
  powershell -NoProfile -ExecutionPolicy Bypass -File ".\Watcher.ps1"
)

popd
endlocal
