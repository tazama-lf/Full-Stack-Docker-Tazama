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

.PARAMETER NoPull
    Skip pulling latest Docker images (--pull always). Useful when retrying
    after a failed start where images are already present on the host.

.EXAMPLE
    .\deploy-core.ps1
    .\deploy-core.ps1 -NoPull
#>

[CmdletBinding()]
param(
    [switch]$NoPull
)
. "$PSScriptRoot\helpers.ps1"

Write-Host ''
Write-Host '=== Deploy: Server A (tazama-core) ===' -ForegroundColor Cyan

$out = Get-TofuOutputs
$idA = $out.ServerA_InstanceId

Write-Host "[Server A] Instance ID: $idA"

# -- 1. Wait for first-boot bootstrap -----------------------------------------
Wait-Bootstrap -InstanceId $idA -ServerName 'Server A'

# -- 2. Pull latest repo changes on Server A ----------------------------------
Write-Host '[Server A] Pulling latest repo changes...'
Invoke-RemoteCommand -InstanceId $idA -Command "cd $Script:RemoteRepo && git fetch origin tazama/feat/mono-repo-phased-deployment && git checkout tazama/feat/mono-repo-phased-deployment && git pull origin tazama/feat/mono-repo-phased-deployment"
Write-Host '[Server A] Repo up to date.' -ForegroundColor Green

# -- 3. Copy .env files to Server A -------------------------------------------
# .env files are gitignored and never committed; they must be pushed to the
# instance before docker compose can resolve image tags and port numbers.
Write-Host '[Server A] Copying core/.env...'
$localEnv = Join-Path $PSScriptRoot '..\..\..\core\.env'
Copy-ToRemote -InstanceId $idA -LocalPath $localEnv -RemotePath "$Script:RemoteRepo/core/.env"

# If an ALB is active, inject KEYCLOAK_HOSTNAME into the remote .env so
# Keycloak generates redirect URLs using the ALB hostname instead of localhost.
if ($out.AlbDnsName) {
    Write-Host "[Server A] Injecting KEYCLOAK_HOSTNAME=$($out.AlbDnsName) into core/.env..."
    $albHost = $out.AlbDnsName
    Invoke-RemoteCommand -InstanceId $idA -Command @"
grep -q '^KEYCLOAK_HOSTNAME=' $Script:RemoteRepo/core/.env \
  && sed -i 's|^KEYCLOAK_HOSTNAME=.*|KEYCLOAK_HOSTNAME=$albHost|' $Script:RemoteRepo/core/.env \
  || echo 'KEYCLOAK_HOSTNAME=$albHost' >> $Script:RemoteRepo/core/.env
"@
    Write-Host '[Server A] KEYCLOAK_HOSTNAME set.' -ForegroundColor Green
}

# -- 4. Copy Keycloak realm config to Server A --------------------------------
# The realm JSON is gitignored-friendly but must be present on the server
# before the stack starts so the volume mount is satisfied and Keycloak
# imports the realm on first boot (--import-realm).
Write-Host '[Server A] Copying Keycloak realm config...'
$localRealm = Join-Path $PSScriptRoot '..\..\..\core\auth\keycloak\realms\00-tazama-test-realm.json'
Invoke-RemoteCommand -InstanceId $idA -Command "mkdir -p $Script:RemoteRepo/core/auth/keycloak/realms"
Copy-ToRemote -InstanceId $idA -LocalPath $localRealm -RemotePath "$Script:RemoteRepo/core/auth/keycloak/realms/00-tazama-test-realm.json"
Write-Host '[Server A] Keycloak realm config copied.' -ForegroundColor Green

# -- 3. Start the core stack ---------------------------------------------------
# Full compose chain: DockerHub-pulled images, all rule processors, pgAdmin, Hasura.
# docker-compose.base.override.yaml must always be position 2 - it publishes
# the three exterior ports that Server B and Server C depend on:
#   NATS :14222 . PostgreSQL :15432 . Valkey :16379
#
# NOTE: Hasura depends_on postgres (service_healthy). On a cold first boot,
# Postgres runs migration scripts and can take >30s to become healthy.
# We retry the up command up to 3 times to ride out this race condition.
# The Postgres healthcheck itself has start_period:120s / retries:20 to give
# the DB enough time; but compose still exits 1 if it times out during the
# initial `up`, so the retry here is the safety net.
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

$maxAttempts = 3
$pullFlag = if ($NoPull) { '' } else { '--pull always' }
for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
    try {
        Invoke-RemoteCommand -InstanceId $idA -Command "cd $Script:RemoteRepo/core && docker compose $composeArgs up -d $pullFlag".Trim()
        break
    }
    catch {
        if ($attempt -lt $maxAttempts) {
            Write-Warning "[Server A] Stack start failed (attempt $attempt/$maxAttempts) — Postgres may still be initialising. Retrying in 30s (images already present, skipping pull)..."
            $pullFlag = ''   # subsequent retries never need to re-pull
            Start-Sleep -Seconds 30
        }
        else {
            throw
        }
    }
}

Write-Host ''
Write-Host '[Server A] tazama-core is up.' -ForegroundColor Green
Write-Host ''
Write-Host 'Next step: .\deploy-extensions.ps1'
