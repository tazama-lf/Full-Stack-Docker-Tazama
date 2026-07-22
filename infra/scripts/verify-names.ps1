<#
.SYNOPSIS
    Verifies compose service keys and container names against NAMING.md (the ratified naming registry).

.DESCRIPTION
    Phase 5 enforcement from the name alignment plan. For each aligned stack it asserts:
      1. Every compose service key appears in NAMING.md.
      2. Every service has an explicit container_name equal to its service key.
      3. Every tazamaorg/* image name matches its service key (exceptions listed below).
      4. No service key or container name ends in -<digit> unless whitelisted as a real replica.
      5. No env file references a retired hostname.

    Stacks are added to $AlignedStacks as their Phase 1 alignment PRs land.

.EXAMPLE
    pwsh ./infra/scripts/verify-names.ps1
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$namingFile = Join-Path $repoRoot 'NAMING.md'

if (-not (Test-Path $namingFile)) {
    Write-Error "NAMING.md not found at $namingFile"
}
$namingContent = Get-Content $namingFile -Raw

# Stacks whose Phase 1 alignment has landed. Extend as PRs merge.
$AlignedStacks = @('biar', 'extensions', 'core')

# Containers allowed a trailing -<digit> (real replicas, per NAMING.md section 5).
$ReplicaWhitelist = @('ozone-datanode-1', 'ozone-datanode-2', 'ozone-datanode-3')

# Canonical names ending in a functional digit code (not replica suffixes, per NAMING.md section 5).
$CanonicalDigitPatterns = @('^rule-\d{3}$', '-tenant-\d{3}$')

# Service keys whose tazamaorg image name legitimately differs from the key
# (deployment fan-out, per NAMING.md rules 1-2).
$ImageExceptions = @{
    'relay-service-ef'            = 'relay-service-integration-nats'
    'relay-service-tp'            = 'relay-service-integration-nats'
    'relay-service-ea'            = 'relay-service-integration-nats'
    'relay-service-ef-tenant-001' = 'relay-service-integration-nats'
    'relay-service-ef-tenant-002' = 'relay-service-integration-nats'
    'relay-service-tp-tenant-001' = 'relay-service-integration-nats'
    'relay-service-tp-tenant-002' = 'relay-service-integration-nats'
    'relay-service-ea-tenant-001' = 'relay-service-integration-nats'
    'relay-service-ea-tenant-002' = 'relay-service-integration-nats'
}

# Retired hostnames that must not appear in env files or init scripts.
# Note: bare 'postgres' is deliberately absent from the core list - it is still
# the database username (`*_DATABASE_USER=postgres`), only the hostname moved
# to core-postgres. Hostname cutover is asserted via the retired service keys.
$RetiredHostnames = @{
    biar       = @('s3g', 'scm', 'om', 'recon', 'tika', 'solr', 'nifi', 'automation-orchestrator')
    extensions = @('opensearch-node1', 'tazama-cms-flowable', 'tazama-cms-voila', 'tazama-cms-backend',
                   'tazama-cms-couchdb', 'tazama-extensions-postgres-1', 'tazama-sftp-1',
                   'tazama-dems-1', 'tazama-deapi-1')
    core       = @('tms', 'ed', 'tp', 'ef', 'auth', 'rsef', 'rstp', 'rsea')
}

$failures = New-Object System.Collections.Generic.List[string]

function Get-ComposeServices {
    param([string]$FilePath)
    # Returns a list of @{ Key; ContainerName; Image } parsed from a compose file.
    $services = @()
    $current = $null
    $inServices = $false
    foreach ($line in (Get-Content $FilePath)) {
        if ($line -match '^services:\s*$') { $inServices = $true; continue }
        if ($inServices -and $line -match '^[A-Za-z#]') { $inServices = $false }
        if (-not $inServices) { continue }
        if ($line -match '^  ([A-Za-z0-9_.-]+):\s*$') {
            $current = [PSCustomObject]@{ Key = $Matches[1]; ContainerName = $null; Image = $null }
            $services += $current
            continue
        }
        if ($null -eq $current) { continue }
        if ($line -match '^\s+container_name:\s*(\S+)') { $current.ContainerName = $Matches[1] }
        elseif ($line -match '^\s+image:\s*(\S+)') { $current.Image = $Matches[1] }
    }
    return $services
}

foreach ($stack in $AlignedStacks) {
    $stackDir = Join-Path $repoRoot $stack
    $composeFiles = Get-ChildItem $stackDir -Filter 'docker-compose*.yaml' -File

    # Aggregate service definitions across the stack's compose files: overlay
    # files legitimately extend a service without repeating container_name/image,
    # so the checks run against the merged view per service key.
    $svcAgg = [ordered]@{}
    foreach ($file in $composeFiles) {
        $rel = $file.FullName.Substring($repoRoot.Path.Length + 1)
        foreach ($svc in (Get-ComposeServices $file.FullName)) {
            if (-not $svcAgg.Contains($svc.Key)) {
                $svcAgg[$svc.Key] = New-Object System.Collections.Generic.List[object]
            }
            $svcAgg[$svc.Key].Add([PSCustomObject]@{ Rel = $rel; ContainerName = $svc.ContainerName; Image = $svc.Image })
        }
    }

    foreach ($key in $svcAgg.Keys) {
        $entries = $svcAgg[$key]

        # 1. Service key must appear in NAMING.md (rule-NNN and per-tenant
        #    variants are registered via their canonical base name).
        $lookupKey = $key
        if ($lookupKey -match '^rule-\d{3}$') { $lookupKey = 'rule-NNN' }
        $lookupKey = $lookupKey -replace '-tenant-\d{3}$', ''
        if ($namingContent -notmatch [regex]::Escape("``$lookupKey``") -and $namingContent -notmatch "\| $([regex]::Escape($lookupKey)) \|") {
            $failures.Add("${stack}: service key '$key' not found in NAMING.md")
        }

        # 2. container_name must be set (in at least one file) and equal to the key
        $named = @($entries | Where-Object { $_.ContainerName })
        if ($named.Count -eq 0) {
            $failures.Add("${stack}: service '$key' has no explicit container_name in any compose file")
        }
        foreach ($entry in $named) {
            if ($entry.ContainerName -ne $key) {
                $failures.Add("$($entry.Rel): service '$key' has container_name '$($entry.ContainerName)' (must equal the key)")
            }
        }

        # 3. tazamaorg image name must match the key (exceptions allowed)
        foreach ($entry in ($entries | Where-Object { $_.Image -and $_.Image -match '^tazamaorg/([^:]+)' })) {
            $null = $entry.Image -match '^tazamaorg/([^:]+)'
            $imageName = $Matches[1]
            $expected = if ($ImageExceptions.ContainsKey($key)) { $ImageExceptions[$key] } else { $key }
            if ($imageName -ne $expected) {
                $failures.Add("$($entry.Rel): service '$key' uses image '$imageName' (expected '$expected')")
            }
        }

        # 4. No trailing -<digit> unless a real replica or a canonical digit code
        $allNames = @($key) + @($named | ForEach-Object { $_.ContainerName }) | Sort-Object -Unique
        foreach ($name in $allNames) {
            if ($name -match '-\d+$' -and $ReplicaWhitelist -notcontains $name) {
                $isCanonical = $false
                foreach ($p in $CanonicalDigitPatterns) {
                    if ($name -match $p) { $isCanonical = $true; break }
                }
                if (-not $isCanonical) {
                    $failures.Add("${stack}: name '$name' has a trailing -<digit> and is not a whitelisted replica")
                }
            }
        }
    }

    # 5. Retired hostnames must not appear in env files or init scripts
    if ($RetiredHostnames.ContainsKey($stack)) {
        $retired = ($RetiredHostnames[$stack] | ForEach-Object { [regex]::Escape($_) }) -join '|'
        $pattern = "(https?://|@|=|\bofs://)($retired)([:/]|\s|$)"
        $checkFiles = @()
        $envDir = Join-Path $stackDir 'env'
        if (Test-Path $envDir) { $checkFiles += Get-ChildItem $envDir -File }
        $dotEnv = Join-Path $stackDir '.env'
        if (Test-Path $dotEnv) { $checkFiles += Get-Item $dotEnv }
        $checkFiles += Get-ChildItem $stackDir -Recurse -Include '*.sh' -File

        foreach ($file in $checkFiles) {
            $lineNum = 0
            foreach ($line in (Get-Content $file.FullName)) {
                $lineNum++
                if ($line.TrimStart().StartsWith('#')) { continue }
                if ($line -match $pattern) {
                    $rel = $file.FullName.Substring($repoRoot.Path.Length + 1)
                    $failures.Add("${rel}:${lineNum}: retired hostname reference: $($line.Trim())")
                }
            }
        }
    }
}

if ($failures.Count -gt 0) {
    Write-Host "verify-names: $($failures.Count) failure(s)" -ForegroundColor Red
    $failures | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
    exit 1
}

Write-Host "verify-names: all checks passed for stacks: $($AlignedStacks -join ', ')" -ForegroundColor Green
exit 0
