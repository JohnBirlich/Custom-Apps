@echo off
setlocal
cd /d "%~dp0"
set "PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
set "LOG=%~dp0startup_error.log"
if exist "%LOG%" del /q "%LOG%"
if not exist "%PS%" (
  echo Windows PowerShell was not found.
  echo Expected: "%PS%"
  pause
  exit /b 1
)
"%PS%" -NoLogo -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0UniversalUsernameFinder.ps1" 2>>"%LOG%"
set "RESULT=%ERRORLEVEL%"
if not "%RESULT%"=="0" (
  echo.
  echo Universal Username Finder could not start. Exit code: %RESULT%
  if exist "%LOG%" (
    echo.
    echo Startup error details:
    type "%LOG%"
  )
  echo.
  echo Send the text above or startup_error.log if you need help.
  pause
)
exit /b %RESULT%
