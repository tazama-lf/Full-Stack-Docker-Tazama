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
:: Pre-flight: verify tazama-core is reachable
:: ---------------------------------------------------------------
:check_core
:: Read SERVER_A_HOST from .env (default: localhost for single-machine; set to private IP for AWS multi-host)
set "SERVER_A_HOST=localhost"
for /f "usebackq tokens=1,* delims==" %%A in (".env") do (
    if /i "%%A"=="SERVER_A_HOST" set "SERVER_A_HOST=%%B"
)
:: Verify core is reachable via NATS exterior port (14222)
powershell -NoProfile -Command "try { $t = New-Object Net.Sockets.TcpClient('!SERVER_A_HOST!', 14222); $t.Close(); exit 0 } catch { exit 1 }" >nul 2>&1
if errorlevel 1 (
    echo.
    echo  ERROR: tazama-core is not reachable at !SERVER_A_HOST!:14222
    echo         Ensure tazama-core is running and SERVER_A_HOST is set correctly in .env
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
echo  Deploying BIAR stack...
echo.
docker compose -p tazama-biar -f ./docker-compose.base.infrastructure.yaml -f ./docker-compose.dev.biar.yaml -f ./docker-compose.utils.init.yaml up -d
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
docker compose -p tazama-biar -f ./docker-compose.base.infrastructure.yaml -f ./docker-compose.dev.biar.yaml -f ./docker-compose.utils.init.yaml down --volumes
goto :done

:done
echo.
echo  Done.
pause
goto :menu

:quit
endlocal
exit /b 0
