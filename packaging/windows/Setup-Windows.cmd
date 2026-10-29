@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Setup-Windows.ps1"
if errorlevel 1 (
  echo.
  echo Setup failed. See the message above.
) else (
  echo.
  echo Setup completed.
)
pause
