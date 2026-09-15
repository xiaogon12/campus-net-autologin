@echo off
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0AutoConnect-Setup.ps1" -Remove
echo.
pause
