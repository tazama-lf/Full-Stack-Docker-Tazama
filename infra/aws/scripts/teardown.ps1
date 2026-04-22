# SPDX-License-Identifier: Apache-2.0
<#
.SYNOPSIS
    Stop all Tazama Docker Compose stacks on all three servers.

.DESCRIPTION
    SSH to each EC2 instance via EICE and runs `docker compose down` for its
    stack.  Does NOT destroy volumes - data is preserved.

    To also remove volumes (destructive - data loss):
        .\teardown.ps1 -RemoveVolumes

    To tear down infrastructure entirely, run `tofu destroy` from infra/aws/
    after this script.

    Run from infra/aws/scripts/ or anywhere - paths are resolved relative
    to this script's location.

.PARAMETER RemoveVolumes
    When set, passes --volumes to docker compose down on each server.
    WARNING: this permanently deletes all container data (databases, indexes,
    NiFi flows, etc.).

.EXAMPLE
    .\teardown.ps1
    .\teardown.ps1 -RemoveVolumes
#>

[CmdletBinding()]
param(
    [switch]$RemoveVolumes
)

. "$PSScriptRoot\helpers.ps1"

$downFlags = if ($RemoveVolumes) { '--volumes' } else { '' }

if ($RemoveVolumes) {
    Write-Warning 'RemoveVolumes is set - all container data will be permanently deleted.'
    $confirm = Read-Host 'Type YES to confirm'
    if ($confirm -ne 'YES') {
        Write-Host 'Aborted.'
        exit 0
    }
}

Write-Host ''
Write-Host '=== Teardown: all Tazama stacks ===' -ForegroundColor Yellow

$out = Get-TofuOutputs

# -- Server C - tazama-biar ----------------------------------------------------
Write-Host '[Server C] Stopping tazama-biar...'
try {
    Invoke-RemoteCommand -InstanceId $out.ServerC_InstanceId -Command @"
cd $Script:RemoteRepo/biar && \
docker compose -p tazama-biar \
  -f ./docker-compose.biar.infrastructure.yaml \
  down $downFlags
"@
    Write-Host '[Server C] Done.' -ForegroundColor Green
}
catch {
    Write-Warning "[Server C] teardown failed: $_"
}

# -- Server B - tazama-extensions ---------------------------------------------
Write-Host '[Server B] Stopping tazama-extensions...'
try {
    Invoke-RemoteCommand -InstanceId $out.ServerB_InstanceId -Command @"
cd $Script:RemoteRepo/extensions && \
docker compose -p tazama-extensions \
  -f ./docker-compose.extensions.infrastructure.yaml \
  -f ./docker-compose.dev.extensions.yaml \
  down $downFlags
"@
    Write-Host '[Server B] Done.' -ForegroundColor Green
}
catch {
    Write-Warning "[Server B] teardown failed: $_"
}

# -- Server A - tazama-core (includes DEMS/DEAPI if deployed) -----------------
Write-Host '[Server A] Stopping DEMS + DEAPI on tazama-core...'
try {
    Invoke-RemoteCommand -InstanceId $out.ServerA_InstanceId -Command @"
cd $Script:RemoteRepo/extensions && \
docker compose -p tazama-core \
  -f ./docker-compose.dev.extensions.apis.yaml \
  down $downFlags
"@
}
catch {
    Write-Warning "[Server A] DEMS/DEAPI down failed (may not have been running): $_"
}

Write-Host '[Server A] Stopping tazama-core...'
try {
    Invoke-RemoteCommand -InstanceId $out.ServerA_InstanceId -Command @"
cd $Script:RemoteRepo/core && \
docker compose -p tazama-core \
  -f ./docker-compose.base.infrastructure.yaml \
  -f ./docker-compose.base.override.yaml \
  -f ./docker-compose.hub.cfg.yaml \
  -f ./docker-compose.hub.core.yaml \
  -f ./docker-compose.hub.rules.yaml \
  -f ./docker-compose.base.auth.yaml \
  -f ./docker-compose.hub.relay.yaml \
  -f ./docker-compose.hub.logs.base.yaml \
  down $downFlags
"@
    Write-Host '[Server A] Done.' -ForegroundColor Green
}
catch {
    Write-Warning "[Server A] teardown failed: $_"
}

Write-Host ''
Write-Host 'All stacks stopped.' -ForegroundColor Green

if (-not $RemoveVolumes) {
    Write-Host ''
    Write-Host 'Volumes retained. To remove all data: .\teardown.ps1 -RemoveVolumes'
    Write-Host 'To destroy infrastructure:            cd ..\; tofu destroy'
}
