@echo off
setlocal
cd /d "%~dp0"

set "OMSIRoot=%~1"
if "%OMSIRoot%"=="" (
    for /f "usebackq delims=" %%I in (`powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\find-omsi.ps1"`) do set "OMSIRoot=%%I"
)
if "%OMSIRoot%"=="" set /p "OMSIRoot=OMSI 2 folder not found. Enter it: "
if "%OMSIRoot%"=="" goto :bad
if "%OMSIRoot:~-1%"=="\" set "OMSIRoot=%OMSIRoot:~0,-1%"

set "OMSI_DEBUG_TROLLEY=1"
set "OMSI_DEBUG_PHYSICS=1"
set "OMSI_TROLLEY_FILE="
set "DEBUG_LOG=%~dp0openomsi-debug.log"

echo.
echo OMSI root:        %OMSIRoot%
echo Trolley file:     %OMSI_TROLLEY_FILE%
echo Debug log:        %DEBUG_LOG%
echo.

if not exist "%OMSIRoot%\openOMSI\openomsi.exe" (
    echo ERROR: openOMSI\openomsi.exe not found.
    pause
    exit /b 1
)
cd /d "%OMSIRoot%"
"%OMSIRoot%\openOMSI\openomsi.exe" %* > "%DEBUG_LOG%" 2>&1
echo openOMSI exited. Log written to:
echo   %DEBUG_LOG%
pause
exit /b 0

:bad
echo No OMSI folder given.
pause
exit /b 1

