@echo off
setlocal enabledelayedexpansion

:menu
set "type="

set "auth=[ ]"
set "basiclogs=[ ]"
set "elasticlogs=[ ]"
set "elasticapm=[ ]"
set "natsutils=[ ]"
set "ui=[ ]"
set "relay=[ ]"

cls
echo Select docker deployment type:
echo 1. Public (GitHub)
echo 2. Full-service (DockerHub)
echo 3. Public (DockerHub)
@REM echo 2. Advanced
echo.
echo Choose (1-3) or quit (q):
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
@REM if /i "%type%"=="2" goto :advanced

:addons
set "choice="
cls
echo Enable optional docker configuration addons:
echo 1. %auth% Authentication
echo 2. %basiclogs% Basic Logs
echo 3. %elasticlogs% [Elastic] Logging
echo 4. %elasticapm% [Elastic] APM
echo 5. %ui% Demo UI
echo 6. %relay% Relay
echo.
echo Apply current selection (a), Toggle addon (1-6) or quit (q)
set /p "choice=Enter your choice: "

if /i "%choice%"=="q" goto :end
if /i "%choice%"=="" goto :apply
if /i "%choice%"=="a" goto :apply

if "%choice%"=="1" if "%auth%" == "[ ]" (set "auth=[X]") else (set "auth=[ ]")
if "%choice%"=="2" if "%basiclogs%" == "[ ]" (set "basiclogs=[X]") else (set "basiclogs=[ ]")
if "%choice%"=="3" if "%elasticlogs%" == "[ ]" (set "elasticlogs=[X]") else (set "elasticlogs=[ ]")
if "%choice%"=="4" if "%elasticapm%" == "[ ]" (set "elasticapm=[X]") else (set "elasticapm=[ ]")
if "%choice%"=="5" if "%ui%" == "[ ]" (set "ui=[X]") else (set "ui=[ ]")
if "%choice%"=="6" if "%relay%" == "[ ]" (set "relay=[X]") else (set "relay=[ ]")

@REM Nats utils not part of standard deployment
if "%choice%"=="99" if "%natsutils%" == "[ ]" (set "natsutils=[X]") else (set "natsutils=[ ]")

goto :addons

:apply
set "cmd=docker compose -f docker-compose.yaml -f docker-compose.override.yaml -f docker-compose.dev.db.yaml"
if "%auth%" == "[X]" (
    if "%IS_GITHUB_DEPLOYMENT%" == "1" (
        set "cmd=%cmd% -f docker-compose.dev.auth.yaml -f docker-compose.auth.base.yaml"
    ) else (
        set "cmd=%cmd% -f docker-compose.auth.yaml -f docker-compose.auth.base.yaml"
    )
)
if "%basiclogs%" == "[X]" (
    if "%IS_GITHUB_DEPLOYMENT%" == "1" (
        set "cmd=%cmd% -f docker-compose.dev.logs-base.yaml -f docker-compose.logs.yaml"
    ) else (
        set "cmd=%cmd% -f docker-compose.logs-base.yaml -f docker-compose.logs.yaml"
    )
)
if "%elasticlogs%" == "[X]" (
    if "%IS_GITHUB_DEPLOYMENT%" == "1" (
        set "cmd=%cmd% -f docker-compose.dev.logs-elastic.yaml -f docker-compose.logs-elastic.base.yaml"
    ) else (
        set "cmd=%cmd% -f docker-compose.logs-elastic.yaml -f docker-compose.logs-elastic.base.yaml"
    )
)
if "%elasticapm%" == "[X]" set "cmd=%cmd% -f docker-compose.dev.apm-elastic.yaml"
if "%natsutils%" == "[X]" set "cmd=%cmd% -f docker-compose.dev.nats-utils.yaml"
if "%ui%" == "[X]" set "cmd=%cmd% -f docker-compose.dev.ui.yaml -f docker-compose.dev.ui.override.yaml"
if "%relay%" == "[X]" if "%IS_GITHUB_DEPLOYMENT%" == "1" (
    set "cmd=%cmd% -f docker-compose.dev.relay.yaml"
) else (
    set "cmd=%cmd% -f docker-compose.relay.yaml"
)

echo.
echo Command to run: %cmd% -p tazama up -d
set /p "confirm=Press (e) to execute, (q) to quit or any other key to go back: "
if "%confirm%"=="e" (
    %cmd% -p tazama up -d --remove-orphans
    goto :end
) else ( 
    if "%confirm%"=="q" (
        goto :end
    )
) 
goto :addons

:deploy_full
cls
echo stopping existing tazama containers...
docker compose -p tazama down > nul 2>&1
echo deploying tazama from docker hub...
docker compose -p tazama -f docker-compose.yaml -f docker-compose.override.yaml -f docker-compose.db.yaml -f docker-compose.full.yaml -f docker-compose.relay.yaml -f docker-compose.dev.ui.yaml up -d
goto :end

:end
exit /b 0
