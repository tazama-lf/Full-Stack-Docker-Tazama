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
$AlignedStacks = @('biar')

# Containers allowed a trailing -<digit> (real replicas, per NAMING.md section 5).
$ReplicaWhitelist = @('ozone-datanode-1', 'ozone-datanode-2', 'ozone-datanode-3')

# Service keys whose tazamaorg image name legitimately differs from the key
# (deployment fan-out, per NAMING.md rules 1-2).
$ImageExceptions = @{
    # 'relay-service-ef' = 'relay-service-integration-nats'  # uncomment when core lands
}

# Retired hostnames that must not appear in env files or init scripts.
$RetiredHostnames = @{
    biar = @('s3g', 'scm', 'om', 'recon', 'tika', 'solr', 'nifi', 'automation-orchestrator')
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

    foreach ($file in $composeFiles) {
        $rel = $file.FullName.Substring($repoRoot.Path.Length + 1)
        foreach ($svc in (Get-ComposeServices $file.FullName)) {
            $key = $svc.Key

            # 1. Service key must appear in NAMING.md
            if ($namingContent -notmatch [regex]::Escape("``$key``") -and $namingContent -notmatch "\| $([regex]::Escape($key)) \|") {
                $failures.Add("${rel}: service key '$key' not found in NAMING.md")
            }

            # 2. container_name must be present and equal to the key
            if (-not $svc.ContainerName) {
                $failures.Add("${rel}: service '$key' has no explicit container_name")
            }
            elseif ($svc.ContainerName -ne $key) {
                $failures.Add("${rel}: service '$key' has container_name '$($svc.ContainerName)' (must equal the key)")
            }

            # 3. tazamaorg image name must match the key (exceptions allowed)
            if ($svc.Image -and $svc.Image -match '^tazamaorg/([^:]+)') {
                $imageName = $Matches[1]
                $expected = if ($ImageExceptions.ContainsKey($key)) { $ImageExceptions[$key] } else { $key }
                if ($imageName -ne $expected) {
                    $failures.Add("${rel}: service '$key' uses image '$imageName' (expected '$expected')")
                }
            }

            # 4. No trailing -<digit> unless a real replica
            foreach ($name in @($key, $svc.ContainerName) | Where-Object { $_ }) {
                if ($name -match '-\d+$' -and $ReplicaWhitelist -notcontains $name) {
                    $failures.Add("${rel}: name '$name' has a trailing -<digit> and is not a whitelisted replica")
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
