@echo off
REM Code Conclave - Quick Launcher
REM Usage: ccl.bat "C:\path\to\project"

cd /d "%~dp0"

if "%~1"=="" (
    echo.
    echo   Code Conclave
    echo   =============
    echo.
    echo   Usage:
    echo     ccl.bat "C:\path\to\project"
    echo     ccl.bat "C:\path\to\project" -Agent sentinel
    echo.
    echo   First time:
    echo     ccl.bat -Init "C:\path\to\project"
    echo.
    pause
    exit /b 1
)

powershell -ExecutionPolicy Bypass -File "%~dp0ccl.ps1" -Project %*
pause
