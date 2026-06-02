# SPDX-License-Identifier: Apache-2.0
<#
.SYNOPSIS
    Pull the latest image for a single service and recreate its container.

.DESCRIPTION
    Targets one Docker Compose service on a specified server, pulls its
    image from DockerHub, and recreates the container in-place without
    touching any other running containers.

    The script inspects the running container's Docker Compose labels to
    discover the working directory and exact compose file chain that were
    used to start it, then issues a targeted 'docker compose up --no-deps
    --force-recreate' for that service only.  This means the script stays
    correct even if the compose file chains change in future.

    Server A runs two compose sub-chains under the same tazama-core project:
      - the main core stack (rules, TP, TMS, auth, relay, logs, pgAdmin, Hasura)
      - the extensions APIs (deapi, dems) — deployed from extensions/ compose files
    Because the working directory and config-file list are read from the live
    container, both sub-chains are handled transparently by the same script.

.PARAMETER Server
    Which EC2 instance to target.  One of: A, B, C.
    A  = Server A (tazama-core)
    B  = Server B (tazama-extensions)
    C  = Server C (tazama-biar)

.PARAMETER Service
    The Docker Compose service name to restart (e.g. "rule-001", "deapi",
    "tcs-api", "nifi", "automation-orchestrator").

.PARAMETER NoPull
    Skip the DockerHub image pull step.  Useful when the latest image is already
    present on the host and you only want to force a config/env recreate.

.PARAMETER DryRun
    Print every command that would be sent to the server without executing any of
    them.  The container-discovery step still runs (read-only) so the resolved
    compose command is shown in full.  The verify step also runs so you can see
    the current container state before committing to the change.

.PARAMETER RepoPull
    Controls whether the full-stack-docker-tazama repo is updated on the target
    server before recreating the container.

      Omitted / 'none'        - skip the repo pull entirely (fastest; use the
                                code already on the server)
      '' (empty) or 'dev'     - fetch and reset to origin/dev
      '<branch>'              - fetch and reset to origin/<branch>

    Using a branch name switches the server to that branch before recreating,
    which is the recommended way to roll out a committed fix without a full
    redeploy.

.EXAMPLE
    .\restart-service.ps1 -Server A -Service rule-001
    .\restart-service.ps1 -Server A -Service deapi
    .\restart-service.ps1 -Server B -Service tcs-api
    .\restart-service.ps1 -Server C -Service nifi
    .\restart-service.ps1 -Server C -Service automation-orchestrator -NoPull
    .\restart-service.ps1 -Server B -Service cms-frontend
    .\restart-service.ps1 -Server B -Service cms-frontend -NoPull
    .\restart-service.ps1 -Server A -Service deapi -RepoPull fix-biar-data-pipeline
    .\restart-service.ps1 -Server A -Service deapi -RepoPull dev
    .\restart-service.ps1 -Server A -Service event-adjudicator -DiscoverService tadp -RepoPull dev
    .\restart-service.ps1 -Server A -Service rsea -DiscoverService rstadp -RepoPull dev
    .\restart-service.ps1 -Server A -Service event-adjudicator -DiscoverService tadp -RepoPull dev -DryRun
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('A', 'B', 'C')]
    [string]$Server,

    [Parameter(Mandatory)]
    [string]$Service,

    [switch]$NoPull,

    # 'none' (or omitted) = skip pull; '' or 'dev' = pull dev; '<branch>' = pull that branch.
    [string]$RepoPull = 'none',

    # When a service has been renamed, supply the OLD service name here. The running old
    # container is used for compose context discovery, the new service ($Service) is
    # started, then the old container is stopped and removed. Omit for normal restarts.
    [string]$DiscoverService = '',

    # Print what would be done without sending any mutating commands to the server.
    # Container discovery and the verify step still run (both are read-only).
    [switch]$DryRun
)

. "$PSScriptRoot\helpers.ps1"

$out = Get-TofuOutputs

# -- Per-server: project name and instance ID -------------------------------------------------------
switch ($Server) {
    'A' { $label = 'Server A'; $instanceId = $out.ServerA_InstanceId; $project = 'tazama-core'       }
    'B' { $label = 'Server B'; $instanceId = $out.ServerB_InstanceId; $project = 'tazama-extensions' }
    'C' { $label = 'Server C'; $instanceId = $out.ServerC_InstanceId; $project = 'tazama-biar'       }
}

$pullFlag = if ($NoPull) { '' } else { '--pull always' }

# Resolve the effective branch: omitted or 'none' → skip; '' → 'dev'; else use as-is.
$effectiveBranch = if ($RepoPull -eq 'none') { '' } elseif ($RepoPull -eq '') { 'dev' } else { $RepoPull }

# When renaming, discover context from the old container; otherwise use the target service.
$discoverTarget = if ($DiscoverService) { $DiscoverService } else { $Service }

Write-Host ''
Write-Host "=== Restart service: $Service on $label ===" -ForegroundColor Cyan
Write-Host "[$label] Project   : $project"
Write-Host "[$label] Service   : $Service"
Write-Host "[$label] Discover  : $(if ($DiscoverService) { "$DiscoverService (renamed → $Service)" } else { '(same)' })"
Write-Host "[$label] Pull      : $(-not $NoPull) (DockerHub image)"
Write-Host "[$label] RepoPull  : $(if ($effectiveBranch) { $effectiveBranch } else { 'none' })"
Write-Host "[$label] DryRun    : $([bool]$DryRun)"
Write-Host ''

# -- Discover compose context from the running container's labels ----------------------------
# Docker Compose stamps every container with:
#   com.docker.compose.project.working_dir   - CWD used for 'docker compose up'
#   com.docker.compose.project.config_files  - comma-separated absolute paths to
#                                              every -f file that was passed
# Reading these labels reconstructs the exact compose command without hardcoding
# file chains in this script.
Write-Host "[$label] Discovering compose context for '$discoverTarget'..."

$discoverCmd = @'
set -e
CONTAINER=$(docker ps \
  --filter "label=com.docker.compose.project=PROJECT_PLACEHOLDER" \
  --filter "label=com.docker.compose.service=SERVICE_PLACEHOLDER" \
  --format '{{.Names}}' | head -1)

if [ -z "$CONTAINER" ]; then
  echo "ERROR: no running container found for service 'SERVICE_PLACEHOLDER' in project 'PROJECT_PLACEHOLDER'" >&2
  exit 1
fi

WORKING_DIR=$(docker inspect "$CONTAINER" \
  --format '{{ index .Config.Labels "com.docker.compose.project.working_dir" }}')
CONFIG_FILES=$(docker inspect "$CONTAINER" \
  --format '{{ index .Config.Labels "com.docker.compose.project.config_files" }}')

echo "CONTAINER=$CONTAINER"
echo "WORKING_DIR=$WORKING_DIR"
echo "CONFIG_FILES=$CONFIG_FILES"
'@ -replace 'PROJECT_PLACEHOLDER', $project -replace 'SERVICE_PLACEHOLDER', $discoverTarget

$discovered = Invoke-RemoteCommand -InstanceId $instanceId -Command $discoverCmd

# Parse the key=value lines returned by the discovery block
$ctx = @{}
foreach ($line in ($discovered -split "`n")) {
    $line = $line.Trim()
    if ($line -match '^([^=]+)=(.*)$') { $ctx[$Matches[1]] = $Matches[2] }
}

$containerName = $ctx['CONTAINER']
$workingDir    = $ctx['WORKING_DIR']
$configFiles   = $ctx['CONFIG_FILES']

if (-not $containerName -or -not $workingDir -or -not $configFiles) {
    throw "[$label] Failed to parse compose context. Raw output:`n$discovered"
}

Write-Host "[$label] Container  : $containerName"
Write-Host "[$label] Working dir: $workingDir"

# Convert comma-separated absolute paths to '-f <path>' flags
$fFlags = ($configFiles -split ',' | ForEach-Object { "-f $_" }) -join ' '

# -- Repo pull ------------------------------------------------------------------------------
if ($effectiveBranch) {
    Write-Host "[$label] Pulling branch '$effectiveBranch' in $workingDir..."
    $repoCmd = "cd $workingDir && git fetch origin $effectiveBranch && git checkout $effectiveBranch && git reset --hard origin/$effectiveBranch"
    if ($DryRun) {
        Write-Host "[$label] [DRY RUN] Would run: $repoCmd" -ForegroundColor Yellow
    } else {
        Invoke-RemoteCommand -InstanceId $instanceId -Command $repoCmd
    }
}

# After a repo pull, re-apply the same per-server overlays that the deploy
# scripts apply. git reset --hard restores committed defaults; the overlays
# below restore the AWS-specific values (private DNS names, public API URLs,
# KEYCLOAK_HOSTNAME, etc.) that must not be committed.
if ($effectiveBranch) {
    if ($DryRun) {
        Write-Host "[$label] [DRY RUN] Would re-apply AWS env overlays for Server $Server." -ForegroundColor Yellow
    } else {
        switch ($Server) {
            'A' {
                # extensions/.env: SERVER_A/B/C_HOST, public API URLs, CORS origins
                $overlayFile = Join-Path $PSScriptRoot '..\templates\env-extensions.tpl'
                Write-Host "[$label] Re-applying extensions .env overlay..."
                Set-RemoteEnvOverlay -InstanceId $instanceId -OverlayFile $overlayFile `
                    -RemoteEnvFile "$Script:RemoteRepo/extensions/.env"

                # core/.env: KEYCLOAK_HOSTNAME (only present when ALB is active)
                if ($out.KeycloakHostname) {
                    Write-Host "[$label] Re-applying core .env overlay..."
                    Set-RemoteEnvOverlay -InstanceId $instanceId `
                        -OverlayContent "KEYCLOAK_HOSTNAME=$($out.KeycloakHostname)" `
                        -RemoteEnvFile "$Script:RemoteRepo/core/.env"
                }

                # KC_HOSTNAME_PORT must be absent on AWS - strip it from keycloak.env
                # which git reset --hard restores to its committed value (KC_HOSTNAME_PORT=8080).
                # TODO(#221): replace with Set-RemoteEnvOverlay deletion support.
                Write-Host "[$label] Stripping KC_HOSTNAME_PORT from keycloak.env..."
                Invoke-RemoteCommand -InstanceId $instanceId -Command `
                    "sed -i '/^KC_HOSTNAME_PORT=/d' $Script:RemoteRepo/core/env/keycloak.env"
            }
            'B' {
                # extensions/.env: SERVER_A/B/C_HOST, public API URLs, CORS origins
                $overlayFile = Join-Path $PSScriptRoot '..\templates\env-extensions.tpl'
                Write-Host "[$label] Re-applying extensions .env overlay..."
                Set-RemoteEnvOverlay -InstanceId $instanceId -OverlayFile $overlayFile `
                    -RemoteEnvFile "$Script:RemoteRepo/extensions/.env"
            }
            'C' {
                # biar/.env: SERVER_A/B/C_HOST, S3A_ENDPOINT, COUCHDB_URL
                $overlayFile = Join-Path $PSScriptRoot '..\templates\env-biar.tpl'
                Write-Host "[$label] Re-applying biar .env overlay..."
                Set-RemoteEnvOverlay -InstanceId $instanceId -OverlayFile $overlayFile `
                    -RemoteEnvFile "$Script:RemoteRepo/biar/.env"
            }
        }
        Write-Host "[$label] Overlays applied." -ForegroundColor Green
    }
}

# -- Recreate -------------------------------------------------------------------------------
$composeCmd = (
    "cd $workingDir && docker compose -p $project $fFlags " +
    "up -d --no-deps --force-recreate $pullFlag $Service"
).Trim()

if ($DryRun) {
    Write-Host ''
    Write-Host "[$label] [DRY RUN] Would run: $composeCmd" -ForegroundColor Yellow
} else {
    Invoke-RemoteCommand -InstanceId $instanceId -Command $composeCmd
    Write-Host ''
    Write-Host "[$label] $Service recreated." -ForegroundColor Green
}

# -- Verify ---------------------------------------------------------------------------------
# In dry-run mode, show the current state of the container that would be replaced so the
# operator can confirm what is running before committing. After a live run, verify the
# newly recreated container.
$verifyService = if ($DryRun) { $discoverTarget } else { $Service }
Write-Host "[$label] $(if ($DryRun) { "[DRY RUN] Current container state for '$verifyService' (no changes made):" } else { 'Verifying container state...' })"

Invoke-RemoteCommand -InstanceId $instanceId -Command @"
docker ps \
  --filter "label=com.docker.compose.project=$project" \
  --filter "label=com.docker.compose.service=$verifyService" \
  --format 'table {{.Names}}\t{{.Status}}\t{{.Image}}'
"@

# -- Remove old container after rename --------------------------------------------------------------
if ($DiscoverService) {
    Write-Host ''
    if ($DryRun) {
        Write-Host "[$label] [DRY RUN] Would stop and remove the '$DiscoverService' container." -ForegroundColor Yellow
    } else {
        Write-Host "[$label] Removing old '$DiscoverService' container (renamed to '$Service')..."
        Invoke-RemoteCommand -InstanceId $instanceId -Command @"
OLD_CTR=`$(docker ps -a \
  --filter "label=com.docker.compose.project=$project" \
  --filter "label=com.docker.compose.service=$DiscoverService" \
  --format '{{.Names}}' | head -1)
if [ -n "`$OLD_CTR" ]; then
  docker stop "`$OLD_CTR" 2>/dev/null || true
  docker rm "`$OLD_CTR"
  echo "Removed: `$OLD_CTR"
else
  echo "No '$DiscoverService' container found (already removed)."
fi
"@
        Write-Host "[$label] Old container removed." -ForegroundColor Green
    }
}
