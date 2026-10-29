@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install-ADB.ps1"
if errorlevel 1 (
  echo.
  echo ADB installation failed. See the message above.
)
pause
