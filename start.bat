@echo off
setlocal enabledelayedexpansion

:menu
set "type="

set "volumes=[ ]"
set "auth=[ ]"
set "basiclogs=[ ]"
set "elasticlogs=[ ]"
set "elasticapm=[ ]"
set "natsutils=[ ]"
set "ui=[ ]"
set "relay=[ ]"
set "test=[ ]"
set "config=[ ]"

set "IS_GITHUB_DEPLOYMENT=0"
set "IS_MULTITENANT_DEPLOYMENT=0"

cls
echo.
echo Select docker deployment type:
echo.
echo 1. Public (GitHub)
echo 2. Full-service (DockerHub)
echo 3. Public (DockerHub)
echo 4. Multi-Tenant Public (DockerHub)
echo 5. General Utilities
echo 6. Database Utilities
echo.
echo Select option (1-6), or (q)uit:
set /p "type=Enter your choice: "

if /i "%type%"=="q" goto :end
if /i "%type%"=="" goto :menu

if /i "%type%"=="1" (
    set "IS_GITHUB_DEPLOYMENT=1"
    goto :addons
)
if /i "%type%"=="2" (
    goto :deploy_full
)
if /i "%type%"=="3" (
    goto :addons
)
if /i "%type%"=="4" (
    set "IS_MULTITENANT_DEPLOYMENT=1"
    goto :multi
)
if /i "%type%"=="5" (
    goto :utils
)
if /i "%type%"=="6" (
    goto :dbutils
)

:addons
set "choice="
cls
echo.
echo Enable optional docker configuration addons:
echo.
echo 1. %auth% Authentication
echo 2. %basiclogs% Basic Logs
echo 3. %elasticlogs% [Elastic] Logging
echo 4. %elasticapm% [Elastic] APM
echo 5. %ui% Demo UI
echo 6. %relay% Relay
echo 7. %test% Hasura GraphQL API for PostgreSQL (Testing)
rem echo 8. %config% Config Service
echo.
echo Toggle addons (1-7), (a)pply current selection, (r)eturn, or (q)uit
set /p "choice=Enter your choice: "

if /i "%choice%"=="a" goto :apply
if /i "%choice%"=="r" goto :menu
if /i "%choice%"=="q" goto :end

if "%choice%"=="1" if "%auth%" == "[ ]" (set "auth=[X]") else (set "auth=[ ]")
if "%choice%"=="2" if "%basiclogs%" == "[ ]" (set "basiclogs=[X]") else (set "basiclogs=[ ]")
if "%choice%"=="3" if "%elasticlogs%" == "[ ]" (set "elasticlogs=[X]") else (set "elasticlogs=[ ]")
if "%choice%"=="4" if "%elasticapm%" == "[ ]" (set "elasticapm=[X]") else (set "elasticapm=[ ]")
if "%choice%"=="5" if "%ui%" == "[ ]" (set "ui=[X]") else (set "ui=[ ]")
if "%choice%"=="6" if "%relay%" == "[ ]" (set "relay=[X]") else (set "relay=[ ]")
if "%choice%"=="7" if "%test%" == "[ ]" (set "test=[X]") else (set "test=[ ]")
rem if "%choice%"=="8" if "%config%" == "[ ]" (set "config=[X]") else (set "config=[ ]")

@REM Nats utils not part of standard deployment
if "%choice%"=="99" if "%natsutils%" == "[ ]" (set "natsutils=[X]") else (set "natsutils=[ ]")

goto :addons

:multi
set "basiclogs=[X]"
set "relay=[X]"

cls
echo.
echo Multi-tenancy installation will contain the following addons:
echo.
echo 1. %auth% Authentication
echo 2. %test% Hasura GraphQL API for PostgreSQL (Testing)
echo 2. %basiclogs% Basic Logs
echo 3. %relay% Relay services
echo.
echo Toggle addons (1-2), (a)pply current selection, (r)eturn, or (q)uit
set /p "choice=Enter your choice: "

if /i "%choice%"=="a" goto :apply
if /i "%choice%"=="r" goto :menu
if /i "%choice%"=="q" goto :end

if "%choice%"=="1" if "%auth%" == "[ ]" (set "auth=[X]") else (set "auth=[ ]")
if "%choice%"=="2" if "%test%" == "[ ]" (set "test=[X]") else (set "test=[ ]")

@REM Nats utils not part of standard deployment
if "%choice%"=="99" if "%natsutils%" == "[ ]" (set "natsutils=[X]") else (set "natsutils=[ ]")

goto :multi

:apply
if %IS_GITHUB_DEPLOYMENT% EQU 1 (
    set "cmd=docker compose -f docker-compose.yaml -f docker-compose.override.yaml -f docker-compose.dev.db.yaml -f docker-compose.dev.rule.yaml -f docker-compose.dev.yaml"
) else (
    if %IS_MULTITENANT_DEPLOYMENT% EQU 1 (
        set "cmd=docker compose -f docker-compose.yaml -f docker-compose.override.yaml -f docker-compose.rule.yaml"
    ) else (
        set "cmd=docker compose -f docker-compose.yaml -f docker-compose.override.yaml -f docker-compose.dev.db.yaml -f docker-compose.rule.yaml"
    )
)
if "%auth%" == "[X]" (
    if %IS_GITHUB_DEPLOYMENT% EQU 1 (
        set "cmd=%cmd% -f docker-compose.dev.auth.yaml -f docker-compose.auth.base.yaml"
    ) else (
        if %IS_MULTITENANT_DEPLOYMENT% EQU 1 (
            set "cmd=%cmd% -f docker-compose.auth.yaml -f docker-compose.auth.base.yaml"
        ) else (
            set "cmd=%cmd% -f docker-compose.auth.yaml -f docker-compose.auth.base.yaml"
        )
    )
)
if "%basiclogs%" == "[X]" (
    if %IS_GITHUB_DEPLOYMENT% EQU 1 (
        set "cmd=%cmd% -f docker-compose.dev.logs-base.yaml -f docker-compose.logs.yaml"
    ) else (
        if %IS_MULTITENANT_DEPLOYMENT% EQU 1 (
            set "cmd=%cmd% -f docker-compose.logs-base.yaml -f docker-compose.logs.yaml"
        ) else (
            set "cmd=%cmd% -f docker-compose.logs-base.yaml -f docker-compose.logs.yaml"
        )
    )
)
if "%elasticlogs%" == "[X]" (
    if %IS_GITHUB_DEPLOYMENT% EQU 1 (
        set "cmd=%cmd% -f docker-compose.dev.logs-elastic.yaml -f docker-compose.logs-elastic.base.yaml"
    ) else (
        set "cmd=%cmd% -f docker-compose.logs-elastic.yaml -f docker-compose.logs-elastic.base.yaml"
    )
)
if "%test%" == "[X]" set "cmd=%cmd% -f docker-compose.dev.hasura.yaml"
if "%elasticapm%" == "[X]" set "cmd=%cmd% -f docker-compose.dev.apm-elastic.yaml"
if "%natsutils%" == "[X]" set "cmd=%cmd% -f docker-compose.dev.nats-utils.yaml"
if "%ui%" == "[X]" set "cmd=%cmd% -f docker-compose.dev.ui.yaml"
if "%relay%" == "[X]" if %IS_GITHUB_DEPLOYMENT% EQU 1 (
    set "cmd=%cmd% -f docker-compose.dev.relay.yaml"
) else (
    if %IS_MULTITENANT_DEPLOYMENT% EQU 1 (
        set "cmd=%cmd% -f docker-compose.multitenant.yaml"
    ) else (
        set "cmd=%cmd% -f docker-compose.relay.yaml"
    )
)
if "%config%" == "[X]" if %IS_GITHUB_DEPLOYMENT% EQU 1 (
    set "cmd=%cmd% -f docker-compose.dev.config.yaml"
) else (
    set "cmd=%cmd% -f docker-compose.config.yaml"
)

echo.
echo Command to run: %cmd% -p tazama up -d
echo.
set /p "confirm=Press (e) to execute, (q) to quit or any other key to go back: "
echo.
if "%confirm%"=="e" (
    echo stopping existing Tazama containers...
    echo.
    docker compose -p tazama down
    echo.
    echo Deploying Tazama from Docker Hub...
    echo.
    %cmd% -p tazama up -d --remove-orphans
    goto :end
) else ( 
    if "%confirm%"=="q" (
        goto :end
    )
) 
goto :end

:deploy_full
set "choice="
cls
echo.
echo Full deployment includes:
echo.
echo 1. Core services (PostgreSQL, NATS, ValKey)
echo 2. Core processors
echo 3. All available rule processors
echo 4. Basic Logs
echo 5. Relay services
echo 6. Demo UI
echo 7. NATS Utilities
echo 8. Test Service (Hasura GraphQL API for PostgreSQL)
echo.

set "cmd=docker compose -p tazama -f docker-compose.yaml -f docker-compose.override.yaml -f docker-compose.db.yaml -f docker-compose.full.yaml -f docker-compose.logs-base.yaml -f docker-compose.full.logs.yaml -f docker-compose.relay.yaml -f docker-compose.dev.ui.yaml -f docker-compose.dev.nats-utils.yaml -f docker-compose.dev.hasura.yaml up -d"
echo %cmd%
echo.
pause

echo.
echo Stopping existing Tazama containers...
echo.
docker compose -p tazama down
echo.
echo Deploying Tazama from Docker Hub...
echo.
echo Command to run: %cmd%
%cmd% --remove-orphans
goto :end

:utils
set "choice="
cls
echo.
echo Execute some Docker commands:
echo.
echo 1. Stop and restart ED, TP and TADP (reload network configuration)
echo 2. Stop and remove Tazama project containers
echo 3. Remove all unused containers, networks, images and volumes
echo 4. List all images
echo 5. List all containers
echo 6. List all volumes
echo 7. List all networks
echo.
echo Select function (1-7), (r)eturn or (q)uit
set /p "choice=Enter your choice: "

if /i "%choice%"=="q" goto :end
if /i "%choice%"=="r" goto :menu
if /i "%choice%"=="" goto :utils

if "%choice%"=="1" (
    set "cmd=docker restart tazama-tp-1 tazama-tadp-1 tazama-ed-1"
)
if "%choice%"=="2" (
    set "cmd=docker compose -p tazama down"
)
if "%choice%"=="3" (
    set "cmd=docker system prune -a -f --volumes"
)
if "%choice%"=="4" (
    set "cmd=docker image ls"
)
if "%choice%"=="5" (
    set "cmd=docker container ls"
)
if "%choice%"=="6" (
    set "cmd=docker volume ls"
)
if "%choice%"=="7" (
    set "cmd=docker network ls"
)

echo Executing command: %cmd%
echo.
call %cmd%
echo.
pause

goto :utils

:dbutils
set "choice="
cls
echo.
echo Execute some Docker commands in tazama-postgres-1:
echo.
echo 1. List all PostgreSQL databases
echo 2. List all PostgreSQL tables in all databases
echo.
echo Select function (1-2), (r)eturn or (q)uit
set /p "choice=Enter your choice: "

if /i "%choice%"=="q" goto :end
if /i "%choice%"=="r" goto :menu
if /i "%choice%"=="" goto :dbutils

echo Executing command...
echo.

if "%choice%"=="1" (
    call docker exec -it tazama-postgres-1 psql -U postgres -c "\l"
)
if "%choice%"=="2" (

    for %%d in (event_history raw_history configuration evaluation) do (
    echo.
    echo === %%d ===
    call docker exec -it tazama-postgres-1 psql -U postgres -d %%d -c "\dt"
    )
)

echo.
pause

goto :dbutils

:end
echo.
echo All done, quiting...
exit /b 0
