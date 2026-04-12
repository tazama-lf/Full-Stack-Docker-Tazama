@echo off
setlocal enabledelayedexpansion

cd /d "%~dp0"

:menu
cls
echo.
echo ============================================================
echo  Tazama BIAR Launcher
echo ============================================================
echo.
echo  Pre-requisite: tazama-core must be running on Server A
echo.
echo    1. Deploy BIAR infrastructure
echo    2. Utilities / teardown
echo.
set /p "choice=Select option (1-2), or (q)uit: "

if /i "%choice%"=="q" goto :quit
if /i "%choice%"==""   goto :menu
if "%choice%"=="1"     goto :check_core
if "%choice%"=="2"     goto :utils
goto :menu

:: ---------------------------------------------------------------
:: Pre-flight: verify tazama-core is running
:: ---------------------------------------------------------------
:check_core
docker compose -p tazama-core ps --status running -q 2>nul | findstr . >nul 2>&1
if errorlevel 1 (
    echo.
    echo  ERROR: tazama-core is not running.
    echo         Start tazama-core.bat on Server A first, then retry.
    echo.
    pause
    goto :menu
)
goto :deploy

:: ---------------------------------------------------------------
:: Deploy
:: ---------------------------------------------------------------
:deploy
echo.
echo  Deploying BIAR infrastructure...
echo.
docker compose -p tazama-biar -f ./docker-compose.biar.infrastructure.yaml up -d
goto :done

:: ---------------------------------------------------------------
:: Utilities
:: ---------------------------------------------------------------
:utils
cls
echo.
echo  Utilities:
echo    1. Tear down BIAR
echo    b. Back
echo.
set /p "util=Select option: "
if /i "%util%"=="b"  goto :menu
if "%util%"=="1"     goto :down_biar
goto :utils

:down_biar
docker compose -p tazama-biar -f ./docker-compose.biar.infrastructure.yaml down --volumes
goto :done

:done
echo.
echo  Done.
pause
goto :menu

:quit
endlocal
exit /b 0
