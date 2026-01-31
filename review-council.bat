@echo off
REM Review Council - Quick Launcher
REM Usage: review-council.bat "C:\path\to\project"

cd /d "%~dp0"

if "%~1"=="" (
    echo.
    echo   Review Council
    echo   ==============
    echo.
    echo   Usage:
    echo     review-council.bat "C:\path\to\project"
    echo     review-council.bat "C:\path\to\project" -Agent sentinel
    echo.
    echo   First time:
    echo     review-council.bat -Init "C:\path\to\project"
    echo.
    pause
    exit /b 1
)

powershell -ExecutionPolicy Bypass -File "%~dp0review-council.ps1" -Project %*
pause
