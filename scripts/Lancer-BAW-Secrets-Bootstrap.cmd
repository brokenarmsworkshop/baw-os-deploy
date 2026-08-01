@echo off
title BAW OS - Secrets Bootstrap
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "Get-ChildItem -LiteralPath '%~dp0' -Recurse -File -ErrorAction SilentlyContinue ^| Unblock-File -ErrorAction SilentlyContinue"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0BAW-Secrets-Bootstrap.ps1"
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