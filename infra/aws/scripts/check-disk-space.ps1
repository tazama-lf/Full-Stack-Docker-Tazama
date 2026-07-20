# SPDX-License-Identifier: Apache-2.0
<#
.SYNOPSIS
    Report disk usage on a Tazama server and, optionally, reclaim space taken by
    stale Docker images left behind after image pulls.

.DESCRIPTION
    Pulling refreshed :rc images (e.g. via restart-core-processors.ps1) leaves the
    previously-tagged image layers on disk as dangling images. Over time these fill
    the root volume on Server A. This script:

      1. Shows filesystem usage (df -h) for the whole instance.
      2. Shows Docker's own space accounting (docker system df -v is summarised).
      3. Optionally reclaims space:
           -Prune     removes only DANGLING images (safe: images with no tag that
                      no container references - typically the old :rc layers).
           -PruneAll  additionally removes ALL images not used by a running
                      container (docker image prune -a). Use with care: any image
                      that is pulled but whose service is currently stopped will be
                      removed and must be pulled again.

    Read-only by default. No changes are made unless -Prune or -PruneAll is given.

.PARAMETER Server
    Which EC2 instance to target. One of: A, B, C. Defaults to A (tazama-core).

.PARAMETER Prune
    Remove dangling (untagged) images to reclaim space. Safe.

.PARAMETER PruneAll
    Remove all images not used by a running container. Aggressive; implies a
    re-pull for any stopped service. Overrides -Prune.

.PARAMETER DryRun
    Print the prune command that would run without executing it. The df / docker
    system df reporting still runs (both read-only).

.EXAMPLE
    .\check-disk-space.ps1
    .\check-disk-space.ps1 -Prune
    .\check-disk-space.ps1 -PruneAll -DryRun
#>

[CmdletBinding()]
param(
    [ValidateSet('A', 'B', 'C')]
    [string]$Server = 'A',

    [switch]$Prune,

    [switch]$PruneAll,

    [switch]$DryRun
)

. "$PSScriptRoot\helpers.ps1"

$out = Get-TofuOutputs

switch ($Server) {
    'A' { $label = 'Server A'; $instanceId = $out.ServerA_InstanceId }
    'B' { $label = 'Server B'; $instanceId = $out.ServerB_InstanceId }
    'C' { $label = 'Server C'; $instanceId = $out.ServerC_InstanceId }
}

Write-Host ''
Write-Host "=== Disk usage: $label ===" -ForegroundColor Cyan
Write-Host ''

# -- Filesystem usage -------------------------------------------------------------------------
Write-Host "[$label] Filesystem usage (df -h):" -ForegroundColor Cyan
Invoke-RemoteCommand -InstanceId $instanceId -Command 'df -h --total | grep -E "Filesystem|/$|overlay|/var|--total|total"'

# -- Docker space accounting ------------------------------------------------------------------
Write-Host ''
Write-Host "[$label] Docker space (docker system df):" -ForegroundColor Cyan
Invoke-RemoteCommand -InstanceId $instanceId -Command 'docker system df'

# -- Reclaimable dangling images --------------------------------------------------------------
Write-Host ''
Write-Host "[$label] Dangling images (untagged, reclaimable):" -ForegroundColor Cyan
Invoke-RemoteCommand -InstanceId $instanceId -Command 'docker images --filter "dangling=true" --format "table {{.Repository}}\t{{.Tag}}\t{{.ID}}\t{{.Size}}" | head -50; echo "Dangling count: $(docker images --filter "dangling=true" -q | wc -l)"'

# -- Optional prune ---------------------------------------------------------------------------
if ($Prune -or $PruneAll) {
    $pruneCmd = if ($PruneAll) { 'docker image prune -a -f' } else { 'docker image prune -f' }
    $desc     = if ($PruneAll) { 'ALL images not used by a running container' } else { 'dangling (untagged) images' }

    Write-Host ''
    Write-Host "[$label] Prune target: $desc" -ForegroundColor Yellow

    if ($DryRun) {
        Write-Host "[$label] [DRY RUN] Would run: $pruneCmd" -ForegroundColor Yellow
    } else {
        Invoke-RemoteCommand -InstanceId $instanceId -Command $pruneCmd

        Write-Host ''
        Write-Host "[$label] Filesystem usage after prune:" -ForegroundColor Green
        Invoke-RemoteCommand -InstanceId $instanceId -Command 'df -h --total | grep -E "Filesystem|/$|overlay|--total|total"'
    }
} else {
    Write-Host ''
    Write-Host "[$label] Read-only report. Re-run with -Prune (safe, dangling only) or -PruneAll (aggressive) to reclaim space." -ForegroundColor DarkGray
}
