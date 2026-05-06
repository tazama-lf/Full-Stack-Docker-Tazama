# SPDX-License-Identifier: Apache-2.0
<#
.SYNOPSIS
    Patch a single environment variable in a remote .env file and optionally
    restart a Docker Compose service — without a full redeploy.

.DESCRIPTION
    Uses the shared Set-RemoteEnvOverlay helper to upsert KEY=VALUE into the
    target .env file on the specified server via SSM EICE.  If -Container,
    -ComposeFile and -ComposeProject are all supplied the service is restarted
    with `docker compose up -d --no-deps <container>`.

.PARAMETER Server
    Which EC2 server to target: A, B, or C.

.PARAMETER EnvFile
    Path to the .env file to patch, relative to the repo root on the remote
    host (e.g. "extensions/env/deapi.env").

.PARAMETER Key
    The environment variable name to set (e.g. CERT_PATH_PUBLIC).

.PARAMETER Value
    The value to assign (e.g. /auth/test-public-key.pem).

.PARAMETER Container
    Docker Compose service name to restart after patching (e.g. "deapi").
    Must be combined with -ComposeFile and -ComposeProject.

.PARAMETER ComposeDir
    Directory to run docker compose from, relative to the repo root
    (e.g. "extensions").  Required when -Container is supplied.

.PARAMETER ComposeFile
    Compose file name (relative to -ComposeDir) used for the restart
    (e.g. "docker-compose.hub.extensions.apis.yaml").
    Required when -Container is supplied.

.PARAMETER ComposeProject
    Docker Compose project name passed via -p (e.g. "tazama-core").
    Required when -Container is supplied.

.EXAMPLE
    # Patch deapi.env on Server A and restart the deapi service:
    .\patch-env.ps1 `
        -Server         A `
        -EnvFile        extensions/env/deapi.env `
        -Key            CERT_PATH_PUBLIC `
        -Value          /auth/test-public-key.pem `
        -Container      deapi `
        -ComposeDir     extensions `
        -ComposeFile    docker-compose.hub.extensions.apis.yaml `
        -ComposeProject tazama-core

.EXAMPLE
    # Patch a value without restarting anything:
    .\patch-env.ps1 `
        -Server  B `
        -EnvFile extensions/.env `
        -Key     POSTGRES_PASSWORD `
        -Value   'my-new-password'
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('A','B','C')]
    [string]$Server,

    [Parameter(Mandatory)]
    [string]$EnvFile,

    [Parameter(Mandatory)]
    [string]$Key,

    [Parameter(Mandatory)]
    [string]$Value,

    [string]$Container      = '',
    [string]$ComposeDir     = '',
    [string]$ComposeFile    = '',
    [string]$ComposeProject = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot\helpers.ps1"

# Validate restart params are all-or-nothing.
$restartParams = @($Container, $ComposeDir, $ComposeFile, $ComposeProject) |
                 Where-Object { $_ -ne '' }
if ($restartParams.Count -gt 0 -and $restartParams.Count -lt 4) {
    throw 'To restart a container, all four of -Container, -ComposeDir, -ComposeFile and -ComposeProject must be supplied.'
}
$doRestart = $restartParams.Count -eq 4

Write-Host ''
Write-Host "=== Patch env: $Key on Server $Server ===" -ForegroundColor Cyan

$out        = Get-TofuOutputs
$instanceId = switch ($Server) {
    'A' { $out.ServerA_InstanceId }
    'B' { $out.ServerB_InstanceId }
    'C' { $out.ServerC_InstanceId }
}
Write-Host "[Server $Server] Instance ID: $instanceId"

$remoteEnvFile = "$Script:RemoteRepo/$EnvFile"
Write-Host "[Server $Server] Patching $remoteEnvFile ..."

$tmp = [System.IO.Path]::GetTempFileName()
try {
    Set-Content $tmp "$Key=$Value" -Encoding ASCII
    Set-RemoteEnvOverlay -InstanceId $instanceId `
                         -OverlayFile $tmp `
                         -RemoteEnvFile $remoteEnvFile
}
finally {
    Remove-Item $tmp -Force -ErrorAction SilentlyContinue
}
Write-Host "[Server $Server] $Key patched." -ForegroundColor Green

if ($doRestart) {
    Write-Host "[Server $Server] Restarting container '$Container'..."
    $composeCmd = "cd $Script:RemoteRepo/$ComposeDir && " +
                  "docker compose -p $ComposeProject -f $ComposeFile up -d --no-deps $Container"
    Invoke-RemoteCommand -InstanceId $instanceId -Command $composeCmd
    Write-Host "[Server $Server] '$Container' restarted." -ForegroundColor Green
}

Write-Host ''
Write-Host '=== Patch complete ===' -ForegroundColor Cyan
