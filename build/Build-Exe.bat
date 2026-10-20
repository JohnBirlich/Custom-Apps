@echo off
setlocal
cd /d "%~dp0"
set "PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
set "LOG=%~dp0build_error.log"
if exist "%LOG%" del /q "%LOG%"

rem Builds dist\UUF.exe from ..\UniversalUsernameFinder.ps1.
rem The .ps1 file stays the single source of truth; the .exe only embeds it.

if not exist "%PS%" (
  echo Windows PowerShell was not found.
  echo Expected: "%PS%"
  pause
  exit /b 1
)

"%PS%" -NoLogo -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0Build-Exe.ps1" 2>>"%LOG%"
set "RESULT=%ERRORLEVEL%"
if not "%RESULT%"=="0" (
  echo.
  echo Build failed. Exit code: %RESULT%
  if exist "%LOG%" (
    echo.
    echo Build error details:
    type "%LOG%"
  )
  echo.
  echo If the message mentions PSGallery, retry: the gallery is periodically unavailable.
  echo Send the text above or build_error.log if you need help.
  pause
)
exit /b %RESULT%
