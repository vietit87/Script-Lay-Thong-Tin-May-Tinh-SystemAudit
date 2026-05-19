@echo off
setlocal EnableExtensions EnableDelayedExpansion

set "SCRIPT_DIR=%~dp0"
set "PS1=%SCRIPT_DIR%SystemAudit.ps1"

if not exist "%PS1%" (
    echo Khong tim thay file: "%PS1%"
    echo Hay dat SystemAudit.ps1 cung thu muc voi file .bat
    pause
    exit /b 1
)

:: Chay PowerShell voi ExecutionPolicy bypass (chi ap dung cho phien chay nay)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%PS1%"
set "EC=%ERRORLEVEL%"
if not "%EC%"=="0" (
    echo Script ket thuc voi ma loi: %EC%
)
pause
exit /b %EC%