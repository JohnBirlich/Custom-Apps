@echo off
rem Universal Username Finder - full removal. Double-click me. Data (history, settings, vault) is removed after confirmation.
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Uninstall-UUF.ps1" %*
echo.
pause
