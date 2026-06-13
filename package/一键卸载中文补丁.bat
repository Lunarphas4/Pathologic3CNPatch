@echo off
setlocal EnableExtensions
title Pathologic 3 CN Patch Uninstaller

set "PACKAGE_DIR=%~dp0"
set "PS_SCRIPT=%PACKAGE_DIR%patch_files\one_click_uninstall.ps1"

if not exist "%PS_SCRIPT%" (
    echo Missing uninstaller file:
    echo %PS_SCRIPT%
    echo.
    pause
    exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%PS_SCRIPT%"

echo.
pause
exit /b %errorlevel%
