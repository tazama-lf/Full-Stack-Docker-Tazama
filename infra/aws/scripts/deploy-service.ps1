# SPDX-License-Identifier: Apache-2.0
<#
.SYNOPSIS
    Additively deploy a single NEW Docker Compose service onto a running server
    without recreating any existing container.

.DESCRIPTION
    restart-service.ps1 can only recreate a service that is *already running*,
    because it discovers the compose context (working dir + the exact -f file
    chain) from the live container's labels. A brand-new service has no running
    container, so that discovery fails.

    This script solves the first-time bring-up. Instead of discovering from the
    target service, it discovers the compose context from a SIBLING service that
    is already running in the same Compose project (and therefore shares the same
    working dir and -f file chain). The new service must be defined somewhere in
    that same chain. It then issues:

        docker compose -p <project> <-f chain> up -d --no-deps <Service>

    'up' with a single named service plus '--no-deps' creates only that one
    container. Existing containers are not stopped, recreated, or otherwise
    touched - the deployment is additive and non-destructive.

    Use this script once to introduce a new component. For subsequent image or
    config refreshes of that same (now-running) component, use restart-service.ps1.

.PARAMETER Server
    Which EC2 instance to target. One of: A, B, C.
    A = Server A (tazama-core)
    B = Server B (tazama-extensions)
    C = Server C (tazama-biar)

.PARAMETER Service
    The NEW Docker Compose service name to bring up (e.g. "tazama-demo").
    It must be defined in the same compose -f chain that -FromService uses.

.PARAMETER FromService
    The name of an already-running SIBLING service in the same Compose project,
    used only to discover the working dir and -f file chain. It is inspected
    read-only and never stopped or modified. For the core stack, "tms" or
    "nats" are reliable choices.

.PARAMETER NoPull
    Skip the DockerHub image pull step (omit --pull always). Useful when the
    image is already present on the host.

.PARAMETER RepoPull
    Controls whether the full-stack-docker-tazama repo is updated on the target
    server before the service is created.

      Omitted / 'none'        - skip the repo pull entirely (use the code already
                                on the server)
      '' (empty) or 'dev'     - fetch and reset to origin/dev
      '<branch>'              - fetch and reset to origin/<branch>

    A repo pull is normally required for a NEW service, because the service's
    compose definition and env files must exist on the server first. After the
    pull the script re-applies the per-server AWS env overlays via the shared
    Set-ServerEnvOverlays helper (private DNS names, public API URLs,
    KEYCLOAK_HOSTNAME, demo UI settings) that git reset --hard would otherwise
    discard.

.PARAMETER DryRun
    Print every mutating command that would be sent to the server without
    executing any of them. The read-only discovery and verify steps still run.

.EXAMPLE
    # First-time bring-up of the demo UI on Server A, pulling the dev branch:
    .\deploy-service.ps1 -Server A -Service tazama-demo -FromService tms -RepoPull dev

    # Same, but the code is already on the server (no repo pull):
    .\deploy-service.ps1 -Server A -Service tazama-demo -FromService tms

    # Preview without making changes:
    .\deploy-service.ps1 -Server A -Service tazama-demo -FromService tms -RepoPull dev -DryRun
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('A', 'B', 'C')]
    [string]$Server,

    [Parameter(Mandatory)]
    [string]$Service,

    [Parameter(Mandatory)]
    [string]$FromService,

    [switch]$NoPull,

    # 'none' (or omitted) = skip pull; '' or 'dev' = pull dev; '<branch>' = pull that branch.
    [string]$RepoPull = 'none',

    # Print what would be done without sending any mutating commands to the server.
    [switch]$DryRun
)

. "$PSScriptRoot\helpers.ps1"

$out = Get-TofuOutputs

# -- Per-server: project name and instance ID --------------------------------
switch ($Server) {
    'A' { $label = 'Server A'; $instanceId = $out.ServerA_InstanceId; $project = 'tazama-core'       }
    'B' { $label = 'Server B'; $instanceId = $out.ServerB_InstanceId; $project = 'tazama-extensions' }
    'C' { $label = 'Server C'; $instanceId = $out.ServerC_InstanceId; $project = 'tazama-biar'       }
}

$pullFlag = if ($NoPull) { '' } else { '--pull always' }

# Resolve the effective branch: omitted or 'none' -> skip; '' -> 'dev'; else use as-is.
$effectiveBranch = if ($RepoPull -eq 'none') { '' } elseif ($RepoPull -eq '') { 'dev' } else { $RepoPull }

Write-Host ''
Write-Host "=== Deploy new service: $Service on $label ===" -ForegroundColor Cyan
Write-Host "[$label] Project    : $project"
Write-Host "[$label] New service: $Service"
Write-Host "[$label] Discover   : $FromService (sibling, read-only)"
Write-Host "[$label] Pull image : $(-not $NoPull)"
Write-Host "[$label] RepoPull   : $(if ($effectiveBranch) { $effectiveBranch } else { 'none' })"
Write-Host "[$label] DryRun     : $([bool]$DryRun)"
Write-Host ''

# -- Discover compose context from the SIBLING service's running container ----
# Docker Compose stamps every container with:
#   com.docker.compose.project.working_dir   - CWD used for 'docker compose up'
#   com.docker.compose.project.config_files  - comma-separated absolute paths to
#                                              every -f file that was passed
# The new service is defined in that same -f chain, so cloning the sibling's
# context lets us start it without hardcoding file lists in this script.
Write-Host "[$label] Discovering compose context from sibling '$FromService'..."

$discoverCmd = @'
set -e
CONTAINER=$(docker ps \
  --filter "label=com.docker.compose.project=PROJECT_PLACEHOLDER" \
  --filter "label=com.docker.compose.service=SERVICE_PLACEHOLDER" \
  --format '{{.Names}}' | head -1)

if [ -z "$CONTAINER" ]; then
  echo "ERROR: no running container found for sibling service 'SERVICE_PLACEHOLDER' in project 'PROJECT_PLACEHOLDER'" >&2
  exit 1
fi

WORKING_DIR=$(docker inspect "$CONTAINER" \
  --format '{{ index .Config.Labels "com.docker.compose.project.working_dir" }}')
CONFIG_FILES=$(docker inspect "$CONTAINER" \
  --format '{{ index .Config.Labels "com.docker.compose.project.config_files" }}')

echo "CONTAINER=$CONTAINER"
echo "WORKING_DIR=$WORKING_DIR"
echo "CONFIG_FILES=$CONFIG_FILES"
'@ -replace 'PROJECT_PLACEHOLDER', $project -replace 'SERVICE_PLACEHOLDER', $FromService

$discovered = Invoke-RemoteCommand -InstanceId $instanceId -Command $discoverCmd

# Parse the key=value lines returned by the discovery block
$ctx = @{}
foreach ($line in ($discovered -split "`n")) {
    $line = $line.Trim()
    if ($line -match '^([^=]+)=(.*)$') { $ctx[$Matches[1]] = $Matches[2] }
}

$workingDir  = $ctx['WORKING_DIR']
$configFiles = $ctx['CONFIG_FILES']

if (-not $workingDir -or -not $configFiles) {
    throw "[$label] Failed to parse compose context from '$FromService'. Raw output:`n$discovered"
}

Write-Host "[$label] Working dir: $workingDir"

# Convert comma-separated absolute paths to '-f <path>' flags
$fFlags = ($configFiles -split ',' | ForEach-Object { "-f $_" }) -join ' '

# -- Repo pull ----------------------------------------------------------------
if ($effectiveBranch) {
    Write-Host "[$label] Pulling branch '$effectiveBranch' in $workingDir..."
    # -f forces the switch even when per-server overlays have dirtied tracked
    # files (e.g. core/.env); reset --hard + the overlay re-apply below restore
    # the intended state immediately afterwards.
    $repoCmd = "cd $workingDir && git fetch origin $effectiveBranch && git checkout -f $effectiveBranch && git reset --hard origin/$effectiveBranch"
    if ($DryRun) {
        Write-Host "[$label] [DRY RUN] Would run: $repoCmd" -ForegroundColor Yellow
    } else {
        Invoke-RemoteCommand -InstanceId $instanceId -Command $repoCmd
    }
}

# After a repo pull, re-apply the same per-server AWS env overlays the deploy
# scripts apply. git reset --hard restores committed defaults; the overlays
# below restore the AWS-specific values (private DNS names, public API URLs,
# KEYCLOAK_HOSTNAME, demo public URL, etc.) that must not be committed.
if ($effectiveBranch) {
    if ($DryRun) {
        Write-Host "[$label] [DRY RUN] Would re-apply AWS env overlays for Server $Server." -ForegroundColor Yellow
    } else {
        Set-ServerEnvOverlays -Server $Server -InstanceId $instanceId -TofuOutputs $out
        Write-Host "[$label] Overlays applied." -ForegroundColor Green
    }
}

# -- Create the new service (additive) ----------------------------------------
# 'up -d --no-deps <Service>' creates only the named container. --no-deps stops
# Compose from (re)starting dependencies, so no existing container is touched.
$composeCmd = (
    "cd $workingDir && docker compose -p $project $fFlags " +
    "up -d --no-deps $pullFlag $Service"
).Trim()

if ($DryRun) {
    Write-Host ''
    Write-Host "[$label] [DRY RUN] Would run: $composeCmd" -ForegroundColor Yellow
} else {
    Invoke-RemoteCommand -InstanceId $instanceId -Command $composeCmd
    Write-Host ''
    Write-Host "[$label] $Service created." -ForegroundColor Green
}

# -- Verify -------------------------------------------------------------------
Write-Host "[$label] $(if ($DryRun) { "[DRY RUN] Current container state for '$Service' (no changes made):" } else { 'Verifying container state...' })"

Invoke-RemoteCommand -InstanceId $instanceId -Command @"
docker ps \
  --filter "label=com.docker.compose.project=$project" \
  --filter "label=com.docker.compose.service=$Service" \
  --format 'table {{.Names}}\t{{.Status}}\t{{.Image}}'
"@
