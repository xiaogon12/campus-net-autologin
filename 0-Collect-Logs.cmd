@echo off
setlocal
cd /d "%~dp0"
set "DST=%~dp0collected"
if not exist "%DST%" mkdir "%DST%"

echo.
echo   Collecting logs from every place the script may have written them...
echo.

for %%S in ("%~dp0logs" "%LOCALAPPDATA%\CampusNet" "D:\CampusNet\campus-net-autologin\logs") do (
  if exist "%%~S" (
    echo   from: %%~S
    xcopy "%%~S\*" "%DST%\" /Y /Q >nul
  )
)

echo.
echo   Collected files:
dir /b "%DST%"
echo.
echo   Done. Tell the assistant it is ready - these files can now be read.
echo.
pause
