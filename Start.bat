@echo off
setlocal
cd /d "%~dp0"
set "PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
set "LOG=%~dp0startup_error.log"
set "EXE=%~dp0UniversalUsernameFinder.exe"
if not exist "%EXE%" set "EXE=%~dp0dist\UniversalUsernameFinder.exe"
if exist "%LOG%" del /q "%LOG%"

rem Prefer the compiled executable when it sits next to this launcher (or in dist).
rem The .ps1 remains the source of truth: the .exe only embeds it, so both paths
rem run exactly the same application.
if exist "%EXE%" goto runexe

if not exist "%PS%" (
  echo Windows PowerShell was not found.
  echo Expected: "%PS%"
  echo Build the executable instead: build\Build-Exe.bat
  pause
  exit /b 1
)
"%PS%" -NoLogo -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0UniversalUsernameFinder.ps1" 2>>"%LOG%"
set "RESULT=%ERRORLEVEL%"
goto report

:runexe
"%EXE%"
set "RESULT=%ERRORLEVEL%"

:report
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
  echo Details are also written to UniversalUsernameFinder.log next to the program.
  pause
)
exit /b %RESULT%
