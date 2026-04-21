# SPDX-License-Identifier: Apache-2.0
<#
.SYNOPSIS
    Deploy Server C - tazama-biar stack.

.DESCRIPTION
    1. Waits for the bootstrap script to complete on Server C.
    2. Copies biar/.env to the server.
    3. Applies the env overlay (SERVER_A_HOST, SERVER_B_HOST, SERVER_C_HOST -> private DNS).
    4. Creates the Tazama warehouse host path if it does not exist.
    5. Starts the biar stack using a staged Ozone startup:
         a. SCM first (Storage Container Manager must initialise before OM)
         b. OM after a short wait
         c. Full stack (infrastructure + hub images + init helpers)

    Server A and Server B must be up before this script is run. NiFi on
    Server C connects via JDBC to PostgreSQL on Server A (:15432 - raw_history,
    event_history, configuration, evaluation) and PostgreSQL on Server B (:15433 -
    tazama_cms). Connections are established when NiFi flows run, not at container
    startup, but both database servers should be reachable before flows are activated.

    Run from infra/aws/scripts/ or anywhere - paths are resolved relative
    to this script's location.

.PARAMETER NoPull
    Skip pulling latest Docker images (--pull always). Useful when retrying
    after a failed start where images are already present on the host.

.EXAMPLE
    .\deploy-biar.ps1
    .\deploy-biar.ps1 -NoPull
#>

[CmdletBinding()]
param(
    [switch]$NoPull
)

. "$PSScriptRoot\helpers.ps1"

Write-Host ''
Write-Host '=== Deploy: Server C (tazama-biar) ===' -ForegroundColor Cyan

$out = Get-TofuOutputs
$idC = $out.ServerC_InstanceId

Write-Host "[Server C] Instance ID: $idC"

# -- 1. Wait for bootstrap -----------------------------------------------------
Wait-Bootstrap -InstanceId $idC -ServerName 'Server C'

# -- 1a. Ensure correct repo branch and pull latest ---------------------------
Write-Host '[Server C] Ensuring correct repo branch and pulling latest...'
Invoke-RemoteCommand -InstanceId $idC -Command "cd $Script:RemoteRepo && git fetch origin tazama/feat/mono-repo-phased-deployment && git checkout tazama/feat/mono-repo-phased-deployment && git pull origin tazama/feat/mono-repo-phased-deployment"
Write-Host '[Server C] Repo up to date.' -ForegroundColor Green

# -- 2. Copy .env --------------------------------------------------------------
Write-Host '[Server C] Copying biar/.env...'
$localBiarEnv = Join-Path $PSScriptRoot '..\..\..\biar\.env'
Copy-ToRemote -InstanceId $idC -LocalPath $localBiarEnv -RemotePath "$Script:RemoteRepo/biar/.env"

# -- 3. Apply .env overlay -----------------------------------------------------
# Replaces local-dev SERVER_A_HOST, SERVER_B_HOST, and SERVER_C_HOST defaults
# in biar/.env with the Route 53 private DNS names.
Write-Host '[Server C] Applying .env overlay...'

$overlayFile   = Join-Path $PSScriptRoot '..\templates\env-biar.tpl'
$remoteEnvFile = "$Script:RemoteRepo/biar/.env"
Set-RemoteEnvOverlay -InstanceId $idC -OverlayFile $overlayFile -RemoteEnvFile $remoteEnvFile

Write-Host '[Server C] .env overlay applied.' -ForegroundColor Green

# -- 4. Create warehouse host path --------------------------------------------
# automation-orchestrator and datalakehouse-api bind-mount this path.
# Docker will fail to start the containers if the directory does not exist.
Write-Host '[Server C] Creating Tazama warehouse directory...'
Invoke-RemoteCommand -InstanceId $idC -Command 'sudo mkdir -p /opt/Tazama_Warehouse && sudo chown ec2-user:ec2-user /opt/Tazama_Warehouse'
Write-Host '[Server C] Warehouse directory ready.' -ForegroundColor Green

# -- 5. Start biar stack (staged Ozone startup) --------------------------------
# Ozone requires SCM to fully initialise before OM and datanodes register.
# Starting everything at once causes datanodes to fail their initial handshake.
Write-Host '[Server C] Starting tazama-biar stack (staged Ozone startup)...'

$infraFile = './docker-compose.biar.infrastructure.yaml'
$hubFile   = './docker-compose.hub.biar.yaml'
$utilsFile = './docker-compose.utils.init.yaml'
$pullFlag  = if ($NoPull) { '' } else { '--pull always' }

# Step 5a: SCM only
Write-Host '[Server C] Starting Ozone SCM...'
Invoke-RemoteCommand -InstanceId $idC -Command "cd $Script:RemoteRepo/biar && docker compose -p tazama-biar -f $infraFile up -d scm"

# Step 5b: Wait for SCM to initialise, then start OM
Write-Host '[Server C] Waiting 20s for SCM to initialise...'
Start-Sleep -Seconds 20
Write-Host '[Server C] Starting Ozone OM...'
Invoke-RemoteCommand -InstanceId $idC -Command "cd $Script:RemoteRepo/biar && docker compose -p tazama-biar -f $infraFile up -d om"

# Step 5c: Wait for OM, then bring up the full stack
Write-Host '[Server C] Waiting 15s for OM to initialise...'
Start-Sleep -Seconds 15
Write-Host '[Server C] Starting full biar stack...'
Invoke-RemoteCommand -InstanceId $idC -Command "cd $Script:RemoteRepo/biar && docker compose -p tazama-biar -f $infraFile -f $hubFile -f $utilsFile up -d $pullFlag".Trim()

Write-Host ''
Write-Host '[Server C] tazama-biar is up.' -ForegroundColor Green
Write-Host ''
Write-Host 'Verify services:'
Write-Host "  NiFi UI              http://$($out.ServerC_PrivateIp):8088/nifi"
Write-Host "  Solr UI              http://$($out.ServerC_PrivateIp):8983/solr"
Write-Host "  Ozone Recon UI       http://$($out.ServerC_PrivateIp):9888"
Write-Host "  Automation Orch API  http://$($out.ServerC_PrivateIp):7619/docs"
Write-Host "  Datalakehouse API    http://$($out.ServerC_PrivateIp):8282/docs"
