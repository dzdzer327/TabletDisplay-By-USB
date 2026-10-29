@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Uninstall.ps1"
if errorlevel 1 (
  echo.
  echo Uninstall did not complete. See the message above.
)
pause
