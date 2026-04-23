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
      - the extensions APIs (deapi, dems)
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
    Skip the image pull step.  Useful when the latest image is already
    present on the host and you only want to force a config/env recreate.

.EXAMPLE
    .\restart-service.ps1 -Server A -Service rule-001
    .\restart-service.ps1 -Server A -Service deapi
    .\restart-service.ps1 -Server B -Service tcs-api
    .\restart-service.ps1 -Server C -Service nifi
    .\restart-service.ps1 -Server C -Service automation-orchestrator -NoPull
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('A', 'B', 'C')]
    [string]$Server,

    [Parameter(Mandatory)]
    [string]$Service,

    [switch]$NoPull
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

Write-Host ''
Write-Host "=== Restart service: $Service on $label ===" -ForegroundColor Cyan
Write-Host "[$label] Project : $project"
Write-Host "[$label] Service : $Service"
Write-Host "[$label] Pull    : $(-not $NoPull)"
Write-Host ''

# -- Discover compose context from the running container's labels ----------------------------
# Docker Compose stamps every container with:
#   com.docker.compose.project.working_dir   - CWD used for 'docker compose up'
#   com.docker.compose.project.config_files  - comma-separated absolute paths to
#                                              every -f file that was passed
# Reading these labels reconstructs the exact compose command without hardcoding
# file chains in this script.
Write-Host "[$label] Discovering compose context for '$Service'..."

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
'@ -replace 'PROJECT_PLACEHOLDER', $project -replace 'SERVICE_PLACEHOLDER', $Service

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

# -- Recreate -------------------------------------------------------------------------------
$composeCmd = (
    "cd $workingDir && docker compose -p $project $fFlags " +
    "up -d --no-deps --force-recreate $pullFlag $Service"
).Trim()

Invoke-RemoteCommand -InstanceId $instanceId -Command $composeCmd

Write-Host ''
Write-Host "[$label] $Service recreated." -ForegroundColor Green

# -- Verify ---------------------------------------------------------------------------------
Write-Host "[$label] Verifying container state..."

Invoke-RemoteCommand -InstanceId $instanceId -Command @"
docker ps \
  --filter "label=com.docker.compose.project=$project" \
  --filter "label=com.docker.compose.service=$Service" \
  --format 'table {{.Names}}\t{{.Status}}\t{{.Image}}'
"@
