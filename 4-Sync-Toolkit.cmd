@echo off
setlocal
cd /d "%~dp0"
set "TARGET=%~1"
if "%TARGET%"=="" set "TARGET=D:\CampusNet\campus-net-autologin"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Sync-Toolkit.ps1" -Target "%TARGET%"
echo.
pause
