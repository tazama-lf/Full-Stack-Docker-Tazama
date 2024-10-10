@echo off
setlocal enabledelayedexpansion

:menu
set "type="

set "auth=[ ]"
set "basiclogs=[ ]"
set "elasticlogs=[ ]"
set "elasticapm=[ ]"
set "natsutils=[ ]"

cls
echo Select docker deployment type:
echo 1. Standard (Public)
@REM echo 2. Advanced
echo.
echo Choose (1) or quit (q):
set /p "type=Enter your choice: "

if /i "%type%"=="q" goto :end
if /i "%type%"=="" goto :menu

if /i "%type%"=="1" goto :addons
@REM if /i "%type%"=="2" goto :advanced

:addons
set "choice="
cls
echo Enable optional docker configuration addons:
echo 1. %auth% Authentication
echo 2. %basiclogs% Basic Logs
echo 3. %elasticlogs% [Elastic] Logging
echo 4. %elasticapm% [Elastic] APM
echo 5. %ui% UI
echo.
echo Apply current selection (a), Toggle addon (1-5) or quit (q)
set /p "choice=Enter your choice: "

if /i "%choice%"=="q" goto :end
if /i "%choice%"=="" goto :apply
if /i "%choice%"=="a" goto :apply

if "%choice%"=="1" if "%auth%" == "[ ]" (set "auth=[X]") else (set "auth=[ ]")
if "%choice%"=="2" if "%basiclogs%" == "[ ]" (set "basiclogs=[X]") else (set "basiclogs=[ ]")
if "%choice%"=="3" if "%elasticlogs%" == "[ ]" (set "elasticlogs=[X]") else (set "elasticlogs=[ ]")
if "%choice%"=="4" if "%elasticapm%" == "[ ]" (set "elasticapm=[X]") else (set "elasticapm=[ ]")
if "%choice%"=="5" if "%ui%" == "[ ]" (set "ui=[X]") else (set "ui=[ ]")

@REM Nats utils not part of standard deployment
if "%choice%"=="99" if "%natsutils%" == "[ ]" (set "natsutils=[X]") else (set "natsutils=[ ]")

goto :addons

:apply
set "cmd=docker compose -f docker-compose.yaml -f docker-compose.override.yaml"
if "%auth%" == "[X]" set "cmd=%cmd% -f docker-compose.dev.auth.yaml"
if "%basiclogs%" == "[X]" set "cmd=%cmd% -f docker-compose.dev.logs-base.yaml"
if "%elasticlogs%" == "[X]" set "cmd=%cmd% -f docker-compose.dev.logs-elastic.yaml"
if "%elasticapm%" == "[X]" set "cmd=%cmd% -f docker-compose.dev.apm-elastic.yaml"
if "%natsutils%" == "[X]" set "cmd=%cmd% -f docker-compose.dev.nats-utils.yaml"
if "%ui%" == "[X]" set "cmd=%cmd% -f docker-compose.dev.ui.yaml"

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

:end
exit /b 0
