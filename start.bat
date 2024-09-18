@echo off
setlocal enabledelayedexpansion

:menu
set "type="

set "eventflow=[ ]"
set "auth=[ ]"
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
echo 1. %eventflow% Event-flow
echo 2. %auth% Authentication
echo.
echo Apply current selection (a), Toggle addon (1-2) or quit (q)
set /p "choice=Enter your choice: "

if /i "%choice%"=="q" goto :end
if /i "%choice%"=="" goto :apply
if /i "%choice%"=="a" goto :apply

if "%choice%"=="1" if "%eventflow%" == "[ ]" (set "eventflow=[X]") else (set "eventflow=[ ]")
if "%choice%"=="2" if "%auth%" == "[ ]" (set "auth=[X]") else (set "auth=[ ]")

@REM Nats utils not part of standard deployment
if "%choice%"=="99" if "%natsutils%" == "[ ]" (set "natsutils=[X]") else (set "natsutils=[ ]")

goto :addons

:apply
set "cmd=docker compose -f docker-compose.yaml -f docker-compose.override.yaml"
if "%eventflow%" == "[X]" set "cmd=%cmd% -f docker-compose.dev.event-flow.yaml"
if "%auth%" == "[X]" set "cmd=%cmd% -f docker-compose.dev.auth.yaml"
if "%natsutils%" == "[X]" set "cmd=%cmd% -f docker-compose.dev.nats-utils.yaml"

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