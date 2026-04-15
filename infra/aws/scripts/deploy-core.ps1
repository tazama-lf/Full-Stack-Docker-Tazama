# SPDX-License-Identifier: Apache-2.0
<#
.SYNOPSIS
    Deploy Server A - tazama-core stack (hub build).

.DESCRIPTION
    1. Reads instance IDs from tofu outputs.
    2. Waits for the bootstrap script to complete on Server A.
    3. Starts the tazama-core Docker Compose stack (hub images).

    Run from infra/aws/scripts/ or anywhere - paths are resolved relative
    to this script's location.

.EXAMPLE
    .\deploy-core.ps1
#>

[CmdletBinding()]
param()

. "$PSScriptRoot\helpers.ps1"

Write-Host ''
Write-Host '=== Deploy: Server A (tazama-core) ===' -ForegroundColor Cyan

$out = Get-TofuOutputs
$idA = $out.ServerA_InstanceId

Write-Host "[Server A] Instance ID: $idA"

# -- 1. Wait for first-boot bootstrap -----------------------------------------
Wait-Bootstrap -InstanceId $idA -ServerName 'Server A'

# -- 2. Copy .env files to Server A -------------------------------------------
# .env files are gitignored and never committed; they must be pushed to the
# instance before docker compose can resolve image tags and port numbers.
Write-Host '[Server A] Copying core/.env...'
$localEnv = Join-Path $PSScriptRoot '..\..\..\core\.env'
Copy-ToRemote -InstanceId $idA -LocalPath $localEnv -RemotePath "$Script:RemoteRepo/core/.env"

# -- 3. Start the core stack ---------------------------------------------------
# Full compose chain: DockerHub-pulled images, all rule processors, pgAdmin, Hasura.
# docker-compose.base.override.yaml must always be position 2 - it publishes
# the three exterior ports that Server B and Server C depend on:
#   NATS :14222 . PostgreSQL :15432 . Valkey :16379
Write-Host '[Server A] Starting tazama-core stack...'

$composeArgs = @(
    '-p tazama-core'
    '-f ./docker-compose.base.infrastructure.yaml'
    '-f ./docker-compose.base.override.yaml'
    '-f ./docker-compose.full.cfg.yaml'
    '-f ./docker-compose.hub.core.yaml'
    '-f ./docker-compose.full.rules.yaml'
    '-f ./docker-compose.base.auth.yaml'
    '-f ./docker-compose.hub.relay.yaml'
    '-f ./docker-compose.hub.logs.base.yaml'
    '-f ./docker-compose.utils.pgadmin.yaml'
    '-f ./docker-compose.utils.hasura.yaml'
) -join ' '

Invoke-RemoteCommand -InstanceId $idA -Command "cd $Script:RemoteRepo/core && docker compose $composeArgs up -d"

Write-Host ''
Write-Host '[Server A] tazama-core is up.' -ForegroundColor Green
Write-Host ''
Write-Host 'Next step: .\deploy-extensions.ps1'
