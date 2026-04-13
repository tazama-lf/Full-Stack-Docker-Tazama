# SPDX-License-Identifier: Apache-2.0
<#
.SYNOPSIS
    Deploy Server C - tazama-biar stack.

.DESCRIPTION
    1. Waits for the bootstrap script to complete on Server C.
    2. Applies the env overlay (SERVER_A_HOST, SERVER_B_HOST -> private DNS).
    3. Starts the biar infrastructure stack.

    Server A and Server B must be up before this script is run - NiFi on
    Server C connects to NATS (:14222) on Server A at startup.

    Run from infra/aws/scripts/ or anywhere - paths are resolved relative
    to this script's location.

.EXAMPLE
    .\deploy-biar.ps1
#>

[CmdletBinding()]
param()

. "$PSScriptRoot\helpers.ps1"

Write-Host ''
Write-Host '=== Deploy: Server C (tazama-biar) ===' -ForegroundColor Cyan

$out = Get-TofuOutputs
$idC = $out.ServerC_InstanceId

Write-Host "[Server C] Instance ID: $idC"

# -- 1. Wait for bootstrap -----------------------------------------------------
Wait-Bootstrap -InstanceId $idC -ServerName 'Server C'

# -- 2. Apply .env overlay -----------------------------------------------------
# Replaces local-dev SERVER_A_HOST and SERVER_B_HOST defaults in biar/.env
# with the Route 53 private DNS names.
Write-Host '[Server C] Applying .env overlay...'

$overlayFile  = Join-Path $PSScriptRoot '..\templates\env-biar.tpl'
$remoteEnvFile = "$Script:RemoteRepo/biar/.env"
Set-RemoteEnvOverlay -InstanceId $idC -OverlayFile $overlayFile -RemoteEnvFile $remoteEnvFile

Write-Host '[Server C] .env overlay applied.' -ForegroundColor Green

# -- 3. Start biar stack -------------------------------------------------------
Write-Host '[Server C] Starting tazama-biar stack...'

Invoke-RemoteCommand -InstanceId $idC -Command @"
cd $Script:RemoteRepo/biar && \
docker compose -p tazama-biar \
  -f ./docker-compose.biar.infrastructure.yaml \
  up -d
"@

Write-Host ''
Write-Host '[Server C] tazama-biar is up.' -ForegroundColor Green
Write-Host ''
Write-Host 'All three stacks deployed. Proceed to Phase E validation.'
