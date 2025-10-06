@echo off
REM ===============================================
REM Run PowerShell script Launch.ps1 from batch file
REM ===============================================

REM Get the directory of this batch file
set "SCRIPT_DIR=%~dp0"

REM Run the PowerShell script
powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%Launch.ps1"

REM Pause to keep window open (optional)
pause
