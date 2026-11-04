@echo off
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Uninstall-UUF.ps1" %*
echo.
pause
