@echo off
title BAW OS - Assistant de redeploiement
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install-BAW-OS.ps1"
set EXITCODE=%ERRORLEVEL%
echo.
if not "%EXITCODE%"=="0" (
    echo Le script s'est termine avec le code %EXITCODE%.
) else (
    echo Le script s'est termine correctement.
)
echo.
pause
exit /b %EXITCODE%