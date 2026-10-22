@echo off
rem Universal Username Finder - installer launcher. Double-click me instead of the .ps1.
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install-UUF.ps1" -TrustSelfSigned %*
if errorlevel 1 (
  echo.
  echo Install failed. The error text is above - copy it to the chat.
) else (
  echo.
  echo Done. Shortcut 'Universal Username Finder' is on the Desktop.
)
pause
