@echo off
setlocal
cd /d "%~dp0"

set "MAIN=%~dp0CampusNet-AutoConnect.ps1"
if not exist "%MAIN%" (
  for %%F in ("%~dp0CampusNet-AutoConnect*.ps1") do set "MAIN=%%~fF"
)
if not exist "%MAIN%" (
  echo.
  echo   [ERROR] CampusNet-AutoConnect.ps1 was not found in this folder.
  echo.
  pause
  exit /b 1
)

echo.
echo   Running: %MAIN%
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%MAIN%" -Visible
set "RC=%ERRORLEVEL%"
echo.
if "%RC%"=="0" (
  echo   [OK] Campus network is connected.
) else (
  echo   [FAILED] Exit code %RC%. See: logs\CampusNet-AutoConnect.log
)
echo.
pause
