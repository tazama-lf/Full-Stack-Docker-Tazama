# SPDX-License-Identifier: Apache-2.0
<#
.SYNOPSIS
    Restart every core Tazama processor on Server A, pulling each image from DockerHub.

.DESCRIPTION
    Thin wrapper around restart-service.ps1. Iterates the list of core processor
    Docker Compose services on Server A (tazama-core) and, for each one, pulls the
    latest image from DockerHub and recreates the container in place.

    No full-stack-docker-tazama repo pull is performed (RepoPull stays 'none'), so
    the code already on the server is used unchanged - only the container images are
    refreshed from DockerHub.

    Groups can be toggled with the switches below. By default every group runs.

.PARAMETER SkipRules
    Skip the rule-NNN rule processors.

.PARAMETER SkipRelays
    Skip the relay services (rsef, rstp, rsea).

.PARAMETER SkipApis
    Skip the ingress/config/auth APIs (tms, admin-service, auth-service, batch-ppa).

.PARAMETER SkipLogging
    Skip the logging sidecar (event-sidecar, lumberjack).

.PARAMETER NoPull
    Pass through to restart-service.ps1: skip the DockerHub pull and just recreate
    with the image already on the host.

.PARAMETER DryRun
    Pass through to restart-service.ps1: print what would be done without making any
    changes on the server.

.PARAMETER ContinueOnError
    Keep going if a single service restart fails. By default the script stops on the
    first failure. A summary of failures is printed at the end regardless.

.EXAMPLE
    .\restart-core-processors.ps1
    .\restart-core-processors.ps1 -DryRun
    .\restart-core-processors.ps1 -SkipRules
    .\restart-core-processors.ps1 -SkipRules -SkipLogging -ContinueOnError
#>

[CmdletBinding()]
param(
    [switch]$SkipRules,
    [switch]$SkipRelays,
    [switch]$SkipApis,
    [switch]$SkipLogging,
    [switch]$NoPull,
    [switch]$DryRun,
    [switch]$ContinueOnError
)

$ErrorActionPreference = 'Stop'

$restartScript = Join-Path $PSScriptRoot 'restart-service.ps1'
if (-not (Test-Path $restartScript)) {
    throw "Could not find restart-service.ps1 next to this script ($restartScript)."
}

# -- Core processor service names on Server A (tazama-core) -----------------------------------
# Grouped so individual groups can be toggled off via the -Skip* switches.

# Evaluation-pipeline processors (the core processors proper).
$pipeline = @(
    'ed',                 # event-director
    'ef',                 # event-flow
    'tp',                 # typology-processor
    'event-adjudicator'
)

# Rule processors (one container per rule). Mirrors docker-pulls.bat.
$rules = @(
    'rule-001', 'rule-002', 'rule-003', 'rule-004', 'rule-006', 'rule-007',
    'rule-008', 'rule-010', 'rule-011', 'rule-016', 'rule-017', 'rule-018',
    'rule-020', 'rule-021', 'rule-024', 'rule-025', 'rule-026', 'rule-027',
    'rule-028', 'rule-030', 'rule-044', 'rule-045', 'rule-048', 'rule-054',
    'rule-063', 'rule-074', 'rule-075', 'rule-076', 'rule-078', 'rule-083',
    'rule-084', 'rule-090', 'rule-091', 'rule-901', 'rule-902'
)

# Relay services.
$relays = @(
    'rsef',   # relay-service-ef
    'rstp',   # relay-service-tp
    'rsea'    # relay-service-ea
)

# Ingress / config / auth APIs.
$apis = @(
    'tms',            # tms-service
    'admin-service',
    'auth-service',
    'batch-ppa'
)

# Logging sidecar.
$logging = @(
    'event-sidecar',
    'lumberjack'
)

# -- Assemble the ordered work list -----------------------------------------------------------
$services = @()
$services += $pipeline
if (-not $SkipRules)   { $services += $rules }
if (-not $SkipRelays)  { $services += $relays }
if (-not $SkipApis)    { $services += $apis }
if (-not $SkipLogging) { $services += $logging }

Write-Host ''
Write-Host "=== Restart core processors on Server A ($($services.Count) services) ===" -ForegroundColor Cyan
Write-Host "Pull from DockerHub : $(-not $NoPull)"
Write-Host "Repo pull           : none (no full-stack repo update)"
Write-Host "DryRun              : $([bool]$DryRun)"
Write-Host "Services            : $($services -join ', ')"
Write-Host ''

# -- Run --------------------------------------------------------------------------------------
$failures = @()
$i = 0
foreach ($svc in $services) {
    $i++
    Write-Host "--- [$i/$($services.Count)] $svc ---" -ForegroundColor Cyan

    $splat = @{
        Server  = 'A'
        Service = $svc
        # RepoPull defaults to 'none' in restart-service.ps1 - no full-stack repo pull.
    }
    if ($NoPull)  { $splat['NoPull']  = $true }
    if ($DryRun)  { $splat['DryRun']  = $true }

    try {
        & $restartScript @splat
    }
    catch {
        $failures += [pscustomobject]@{ Service = $svc; Error = $_.Exception.Message }
        Write-Host "[Server A] FAILED to restart '$svc': $($_.Exception.Message)" -ForegroundColor Red
        if (-not $ContinueOnError) {
            Write-Host ''
            Write-Host "Stopping on first failure. Re-run with -ContinueOnError to process the rest." -ForegroundColor Yellow
            break
        }
    }
}

# -- Summary ----------------------------------------------------------------------------------
Write-Host ''
Write-Host '=== Summary ===' -ForegroundColor Cyan
if ($failures.Count -eq 0) {
    Write-Host "All $($services.Count) core processor restarts completed." -ForegroundColor Green
} else {
    Write-Host "$($failures.Count) of $($services.Count) service(s) failed:" -ForegroundColor Red
    $failures | ForEach-Object { Write-Host "  - $($_.Service): $($_.Error)" -ForegroundColor Red }
    exit 1
}
