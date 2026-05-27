# SPDX-License-Identifier: Apache-2.0
<#
.SYNOPSIS
    Deploy Server B - tazama-extensions stack (dev build).

.DESCRIPTION
    1. On Server A: adds DEMS + DEAPI to the running tazama-core project.
       These APIs must be up before TCS/TRS backends on Server B start.
    2. On Server B: waits for bootstrap, applies the env overlay, copies
       the auth public key, then starts the extensions stack.

    Run from infra/aws/scripts/ or anywhere - paths are resolved relative
    to this script's location.

.PARAMETER NoPull
    Skip pulling latest Docker images (--pull always). Useful when retrying
    after a failed start where images are already present on the host.

.EXAMPLE
    .\deploy-extensions.ps1
    .\deploy-extensions.ps1 -NoPull
#>

[CmdletBinding()]
param(
    [switch]$NoPull,

    # PostgreSQL password for Server B's database and all extension service clients.
    # If omitted, the local-dev default 'unused' values are left in place.
    [string]$Password = ''
)

. "$PSScriptRoot\helpers.ps1"

Write-Host ''
Write-Host '=== Deploy: Server B (tazama-extensions) ===' -ForegroundColor Cyan

$out = Get-TofuOutputs
$idA = $out.ServerA_InstanceId
$idB = $out.ServerB_InstanceId

Write-Host "[Server A] Instance ID: $idA"
Write-Host "[Server B] Instance ID: $idB"

# -- 1. Server A: copy auth public key
# DEMS and DEAPI both set AUTH_PUBLIC_KEY_PATH=/auth/test-public-key.pem.
# The key must exist on Server A before the containers start.
Write-Host '[Server A] Copying auth public key...'
$localKey = Join-Path $PSScriptRoot '..\..\..\core\auth\test-public-key.pem'
Invoke-RemoteCommand -InstanceId $idA -Command "mkdir -p $Script:RemoteRepo/extensions/auth"
Copy-ToRemote -InstanceId $idA `
              -LocalPath  $localKey `
              -RemotePath "$Script:RemoteRepo/extensions/auth/test-public-key.pem"
Write-Host '[Server A] Auth key copied.' -ForegroundColor Green

# -- 2. Server A: pull latest repo then add DEMS + DEAPI ---------------------
# DEMS and DEAPI run inside the tazama-core Docker project on Server A.
# They are not part of the core bat launch chain; they are added here before
# the extensions stack starts so that Server B services can reach them.
# Pull latest so any changes to extensions compose files / env are picked up.
Write-Host ''
Write-Host '[Server A] Pulling latest repo...'
Invoke-RemoteCommand -InstanceId $idA -Command "cd $Script:RemoteRepo && git fetch origin $Script:RepoBranch && git checkout $Script:RepoBranch && git reset --hard origin/$Script:RepoBranch"
Write-Host '[Server A] Repo up to date.' -ForegroundColor Green

# extensions/.env is git-tracked and arrived via git pull above.
# Apply the overlay so SERVER_B_HOST resolves to extensions.tazama.internal
# (used in CORS_ORIGINS by DEMS and DEAPI).
$overlayFile = Join-Path $PSScriptRoot '..\templates\env-extensions.tpl'
Write-Host '[Server A] Applying .env overlay to extensions/.env...'
Set-RemoteEnvOverlay -InstanceId $idA -OverlayFile $overlayFile -RemoteEnvFile "$Script:RemoteRepo/extensions/.env"
Write-Host '[Server A] .env overlay applied.' -ForegroundColor Green

Write-Host '[Server A] Adding DEMS + DEAPI to tazama-core...'

$pullFlag = if ($NoPull) { '' } else { '--pull always' }
Invoke-RemoteCommand -InstanceId $idA -Command "cd $Script:RemoteRepo/extensions && docker compose -p tazama-core -f ./docker-compose.hub.extensions.apis.yaml up -d $pullFlag".Trim()

Write-Host '[Server A] DEMS + DEAPI up.' -ForegroundColor Green

# -- 3. Server B: wait for bootstrap ------------------------------------------
Wait-Bootstrap -InstanceId $idB -ServerName 'Server B'

# -- 3a. Server B: ensure correct repo branch and pull latest -----------------
# Servers bootstrapped before the bootstrap.sh.tpl branch fix cloned the default
# 'dev' branch, which has a flat structure (no extensions/ subdirectory).
# Switch to the correct mono-repo branch and pull latest so all compose/config
# changes are present.
Write-Host '[Server B] Ensuring correct repo branch and pulling latest...'
Invoke-RemoteCommand -InstanceId $idB -Command "cd $Script:RemoteRepo && git fetch origin $Script:RepoBranch && git checkout $Script:RepoBranch && git reset --hard origin/$Script:RepoBranch"
Write-Host '[Server B] Repo up to date.' -ForegroundColor Green

# -- 4. Server B: apply .env overlay ------------------------------------------
# Replaces local-dev SERVER_A_HOST and SERVER_B_HOST defaults in extensions/.env
# with the Route 53 private DNS names (core.tazama.internal etc.).
Write-Host '[Server B] Applying .env overlay...'

$overlayFile = Join-Path $PSScriptRoot '..\templates\env-extensions.tpl'
$remoteEnvFile = "$Script:RemoteRepo/extensions/.env"
Set-RemoteEnvOverlay -InstanceId $idB -OverlayFile $overlayFile -RemoteEnvFile $remoteEnvFile

Write-Host '[Server B] .env overlay applied.' -ForegroundColor Green

# Apply credentials overlay to extensions/.env and all service env files.
# Built in-memory from the -Password parameter — never written to a committed file.
# Skipped entirely when -Password is not supplied.
if ($Password) {
    Write-Host '[Server B] Applying credentials overlay to extensions env files...'
    $extCredOverlay = @"
POSTGRES_PASSWORD=$Password
DB_PASSWORD=$Password
SPRING_DATASOURCE_PASSWORD=$Password
CONFIGURATION_DATABASE_PASSWORD=$Password
"@
    $tmpCred = [System.IO.Path]::GetTempFileName()
    try {
        Set-Content $tmpCred $extCredOverlay -Encoding ASCII
        $extEnvFiles = @(
            "$Script:RemoteRepo/extensions/.env"
            "$Script:RemoteRepo/extensions/env/cms.env"
            "$Script:RemoteRepo/extensions/env/tcs.env"
            "$Script:RemoteRepo/extensions/env/deapi.env"
            "$Script:RemoteRepo/extensions/env/dems.env"
        )
        foreach ($envFile in $extEnvFiles) {
            Set-RemoteEnvOverlay -InstanceId $idB -OverlayFile $tmpCred -RemoteEnvFile $envFile
        }
    } finally {
        Remove-Item $tmpCred -Force -ErrorAction SilentlyContinue
    }
    Write-Host '[Server B] Credentials overlay applied.' -ForegroundColor Green
} else {
    Write-Warning '[Server B] -Password not supplied — DB passwords left at local-dev defaults.'
}

# -- 6. Server B: copy auth public key ----------------------------------------
# TCS and TRS backends require the auth public key (used for JWT verification).
# On single-machine deployments it is copied from ../core/auth/ automatically
# by tazama-extensions.bat.  Here we copy it from the local repo to Server B.
Write-Host '[Server B] Copying auth public key...'

$localKey = Join-Path $PSScriptRoot '..\..\..\core\auth\test-public-key.pem'
Invoke-RemoteCommand -InstanceId $idB -Command "mkdir -p $Script:RemoteRepo/extensions/auth"
Copy-ToRemote -InstanceId $idB `
              -LocalPath  $localKey `
              -RemotePath "$Script:RemoteRepo/extensions/auth/test-public-key.pem"

Write-Host '[Server B] Auth key copied.' -ForegroundColor Green

# -- 7. Server B: start extensions stack --------------------------------------
Write-Host '[Server B] Starting tazama-extensions stack...'

$composeArgs = @(
    '-p tazama-extensions'
    '-f ./docker-compose.extensions.infrastructure.yaml'
    '-f ./docker-compose.hub.extensions.yaml'
    '-f ./docker-compose.utils.pgadmin.yaml'
) -join ' '

Invoke-RemoteCommand -InstanceId $idB -Command "cd $Script:RemoteRepo/extensions && docker compose $composeArgs up -d $pullFlag".Trim()

Write-Host ''
Write-Host '[Server B] tazama-extensions is up.' -ForegroundColor Green
Write-Host ''
Write-Host 'Next step: .\deploy-biar.ps1'
