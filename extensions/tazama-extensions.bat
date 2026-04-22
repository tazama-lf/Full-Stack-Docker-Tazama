@echo off
setlocal enabledelayedexpansion

cd /d "%~dp0"

:menu
set "PGADMIN=[ ]"
cls
echo.
echo ============================================================
echo  Tazama Extensions Launcher
echo ============================================================
echo.
echo  Server A pre-flight  (run on Server A before Server B):
echo    1. Deploy DEMS + DEAPI  (GitHub builds)
echo    2. Deploy DEMS + DEAPI  (DockerHub images)
echo.
echo  Server B extensions stack:
echo    3. Deploy extensions    (GitHub builds)
echo    4. Deploy extensions    (DockerHub images)
echo.
::  Utilities / teardown
echo    5. Utilities / teardown
echo.
set /p "choice=Select option (1-5), or (q)uit: "

if /i "%choice%"=="q" goto :quit
if /i "%choice%"==""   goto :menu
if "%choice%"=="1"     set "API_BUILD=dev"
if "%choice%"=="1"     goto :check_core
if "%choice%"=="2"     set "API_BUILD=hub"
if "%choice%"=="2"     goto :check_core
if "%choice%"=="3"     set "BUILD_TYPE=dev"
if "%choice%"=="3"     goto :pgadmin_prompt
if "%choice%"=="4"     set "BUILD_TYPE=hub"
if "%choice%"=="4"     goto :pgadmin_prompt
if "%choice%"=="5"     goto :utils
goto :menu

:: ---------------------------------------------------------------
:: Server A pre-flight: DEMS + DEAPI
:: ---------------------------------------------------------------
:check_core
docker compose -p tazama-core ps --status running -q 2>nul | findstr . >nul 2>&1
if errorlevel 1 (
    echo.
    echo  ERROR: tazama-core is not running.
    echo         Start tazama-core.bat on this machine first, then retry.
    echo.
    pause
    goto :menu
)

if "%API_BUILD%"=="dev" (
    set "apicmd=docker compose -p tazama-core -f ./docker-compose.dev.extensions.apis.yaml"
) else (
    set "apicmd=docker compose -p tazama-core -f ./docker-compose.hub.extensions.apis.yaml"
)

echo.
echo  Running: !apicmd! up -d
!apicmd! up -d
goto :done

:: ---------------------------------------------------------------
:: Server B extensions stack
:: ---------------------------------------------------------------
:pgadmin_prompt
cls
echo.
echo  Optional services:
echo.
set "addon="
set /p "addon=Include pgAdmin? [y/N]: "
if /i "!addon!"=="y" ( set "PGADMIN=true" ) else ( set "PGADMIN=false" )

:: Auto-copy public key for TCS/TRS volume mounts
if not exist ".\auth\" mkdir ".\auth\"
if not exist ".\auth\test-public-key.pem" (
    if exist "..\core\auth\test-public-key.pem" (
        copy /y "..\core\auth\test-public-key.pem" ".\auth\test-public-key.pem" >nul
        echo  Copied test-public-key.pem from core.
    ) else (
        echo.
        echo  ERROR: ..\core\auth\test-public-key.pem not found.
        echo         Place the public key in .\auth\ and retry.
        echo.
        pause
        goto :menu
    )
)

set "cmd=docker compose -p tazama-extensions"
set "cmd=!cmd! -f ./docker-compose.extensions.infrastructure.yaml"
if "%BUILD_TYPE%"=="dev" (
    set "cmd=!cmd! -f ./docker-compose.dev.extensions.yaml"
) else (
    set "cmd=!cmd! -f ./docker-compose.hub.extensions.yaml"
)
if "!PGADMIN!"=="true" set "cmd=!cmd! -f ./docker-compose.utils.pgadmin.yaml"

echo.
echo  Running: !cmd! up -d
!cmd! up -d
goto :done

:: ---------------------------------------------------------------
:: Utilities
:: ---------------------------------------------------------------
:utils
cls
echo.
echo  Utilities:
echo    1. Tear down extensions stack  (Server B)
echo    2. Remove DEMS + DEAPI         (Server A)
echo    3. Tear down all
echo    4. Start pgAdmin               (Server B)
echo    b. Back
echo.
set /p "util=Select option: "
if /i "%util%"=="b"  goto :menu
if "%util%"=="1"     goto :down_extensions
if "%util%"=="2"     goto :down_apis
if "%util%"=="3"     goto :down_all
if "%util%"=="4"     goto :start_pgadmin
goto :utils

:down_extensions
docker compose -p tazama-extensions -f ./docker-compose.extensions.infrastructure.yaml -f ./docker-compose.dev.extensions.yaml -f ./docker-compose.utils.pgadmin.yaml down --volumes
goto :done

:down_apis
docker compose -p tazama-core -f ./docker-compose.dev.extensions.apis.yaml down --remove-orphans
goto :done

:down_all
docker compose -p tazama-extensions -f ./docker-compose.extensions.infrastructure.yaml -f ./docker-compose.dev.extensions.yaml -f ./docker-compose.utils.pgadmin.yaml down --volumes
docker compose -p tazama-core -f ./docker-compose.dev.extensions.apis.yaml down --remove-orphans
goto :done

:start_pgadmin
docker compose -p tazama-extensions -f ./docker-compose.utils.pgadmin.yaml up -d
goto :done

:done
echo.
echo  Done.
pause
goto :menu

:quit
endlocal
exit /b 0