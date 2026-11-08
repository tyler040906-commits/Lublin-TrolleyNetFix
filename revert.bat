@echo off
setlocal
cd /d "%~dp0"

set "OMSIRoot=%~1"
if "%OMSIRoot%"=="" (
    for /f "usebackq delims=" %%I in (`powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\find-omsi.ps1"`) do set "OMSIRoot=%%I"
)
if "%OMSIRoot%"=="" set /p "OMSIRoot=OMSI 2 folder not found. Enter it: "
if "%OMSIRoot%"=="" goto :bad
set "ALT="
echo.
echo Detected/selected OMSI 2:
echo   %OMSIRoot%
set /p "ALT=Press Enter to use it, or type another folder: "
if not "%ALT%"=="" set "OMSIRoot=%ALT%"
if "%OMSIRoot%"=="" goto :bad
if "%OMSIRoot:~-1%"=="\" set "OMSIRoot=%OMSIRoot:~0,-1%"

if not exist "%OMSIRoot%\maps\Projekt_Lublin_2017" (
    echo.
    echo ERROR: maps\Projekt_Lublin_2017 not found under:
    echo   %OMSIRoot%
    echo.
    pause
    exit /b 1
)

echo.
echo Reverting Lublin-TrolleyNetFix in:
echo   %OMSIRoot%
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\install.ps1" -OmsiRoot "%OMSIRoot%" -Revert
if errorlevel 1 (
    echo.
    echo REVERT FAILED. Read the message above.
    pause
    exit /b 1
)
echo.
echo Done.
pause
exit /b 0

:bad
echo No OMSI folder given.
pause
exit /b 1

