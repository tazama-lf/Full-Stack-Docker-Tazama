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

.EXAMPLE
    .\deploy-extensions.ps1
#>

[CmdletBinding()]
param()

. "$PSScriptRoot\helpers.ps1"

Write-Host ''
Write-Host '=== Deploy: Server B (tazama-extensions) ===' -ForegroundColor Cyan

$out = Get-TofuOutputs
$idA = $out.ServerA_InstanceId
$idB = $out.ServerB_InstanceId

Write-Host "[Server A] Instance ID: $idA"
Write-Host "[Server B] Instance ID: $idB"

# -- 1. Server A: copy extensions .env ---------------------------------------
Write-Host '[Server A] Copying extensions/.env...' 
$localExtEnv = Join-Path $PSScriptRoot '..\..\..\extensions\.env'
Copy-ToRemote -InstanceId $idA -LocalPath $localExtEnv -RemotePath "$Script:RemoteRepo/extensions/.env"

# -- 2. Server A: add DEMS + DEAPI to the tazama-core project -----------------
# DEMS and DEAPI run inside the tazama-core Docker project on Server A.
# They are not part of the core bat launch chain; they are added here before
# the extensions stack starts so that Server B services can reach them.
Write-Host ''
Write-Host '[Server A] Adding DEMS + DEAPI to tazama-core...'

Invoke-RemoteCommand -InstanceId $idA -Command "cd $Script:RemoteRepo/extensions && docker compose -p tazama-core -f ./docker-compose.hub.extensions.apis.yaml up -d --pull always"

Write-Host '[Server A] DEMS + DEAPI up.' -ForegroundColor Green

# -- 3. Server B: wait for bootstrap ------------------------------------------
Wait-Bootstrap -InstanceId $idB -ServerName 'Server B'

# -- 3a. Server B: ensure correct repo branch and pull latest -----------------
# Servers bootstrapped before the bootstrap.sh.tpl branch fix cloned the default
# 'dev' branch, which has a flat structure (no extensions/ subdirectory).
# Switch to the correct mono-repo branch and pull latest so all compose/config
# changes are present.
Write-Host '[Server B] Ensuring correct repo branch and pulling latest...'
Invoke-RemoteCommand -InstanceId $idB -Command "cd $Script:RemoteRepo && git fetch origin tazama/feat/mono-repo-phased-deployment && git checkout tazama/feat/mono-repo-phased-deployment && git pull origin tazama/feat/mono-repo-phased-deployment"
Write-Host '[Server B] Repo up to date.' -ForegroundColor Green

# -- 4. Server B: copy .env ---------------------------------------------------
Write-Host '[Server B] Copying extensions/.env...'
$localExtEnv = Join-Path $PSScriptRoot '..\..\..\extensions\.env'
Copy-ToRemote -InstanceId $idB -LocalPath $localExtEnv -RemotePath "$Script:RemoteRepo/extensions/.env"

# -- 5. Server B: apply .env overlay ------------------------------------------
# Replaces local-dev SERVER_A_HOST and SERVER_B_HOST defaults in extensions/.env
# with the Route 53 private DNS names (core.tazama.internal etc.).
Write-Host '[Server B] Applying .env overlay...'

$overlayFile = Join-Path $PSScriptRoot '..\templates\env-extensions.tpl'
$remoteEnvFile = "$Script:RemoteRepo/extensions/.env"
Set-RemoteEnvOverlay -InstanceId $idB -OverlayFile $overlayFile -RemoteEnvFile $remoteEnvFile

Write-Host '[Server B] .env overlay applied.' -ForegroundColor Green

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
) -join ' '

Invoke-RemoteCommand -InstanceId $idB -Command "cd $Script:RemoteRepo/extensions && docker compose $composeArgs up -d --pull always"

Write-Host ''
Write-Host '[Server B] tazama-extensions is up.' -ForegroundColor Green
Write-Host ''
Write-Host 'Next step: .\deploy-biar.ps1'
